#!/usr/bin/env python3
"""Discover iOS package news, then publish only from original developer sources.

ios-repo-updates.com is used strictly as a discovery feed. It is never a
public article source. The publisher resolves the package's original repo,
developer page or GitHub project, gathers source material there, requires a
unique source visual, writes a substantial article, verifies it, and publishes
only when all 9/10 quality gates pass.
"""

from __future__ import annotations

import argparse
import bz2
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import gzip
from html.parser import HTMLParser
import html
import json
import os
from pathlib import Path
import re
import sys
from typing import Any, Iterable
from urllib.parse import urljoin, urlparse, quote_plus
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo

from automation.openai_api import OpenAIAPIError, structured_response
from automation.publisher import _render_feed, _update_sitemap, load_audit
from automation.schemas import VERDICT_SCHEMA
from automation.source_visuals import acquire_unique_source_visual


USER_AGENT = "Mozilla/5.0 (compatible; NextJailbreakNewsBot/1.0; +https://nextjailbreak.com/)"
DISCOVERY_HOSTS = {"ios-repo-updates.com", "www.ios-repo-updates.com"}
MAX_TEXT_BYTES = 3 * 1024 * 1024

ARTICLE_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "title": {"type": "string", "minLength": 25, "maxLength": 100},
        "meta_description": {"type": "string", "minLength": 110, "maxLength": 165},
        "summary": {"type": "string", "minLength": 120},
        "key_takeaways": {
            "type": "array", "minItems": 4, "maxItems": 6,
            "items": {"type": "string", "minLength": 25},
        },
        "sections": {
            "type": "array", "minItems": 5, "maxItems": 8,
            "items": {
                "type": "object",
                "properties": {
                    "heading": {"type": "string", "minLength": 5},
                    "paragraphs": {
                        "type": "array", "minItems": 2, "maxItems": 4,
                        "items": {"type": "string", "minLength": 90},
                    },
                    "bullets": {
                        "type": "array", "minItems": 0, "maxItems": 6,
                        "items": {"type": "string", "minLength": 15},
                    },
                },
                "required": ["heading", "paragraphs", "bullets"],
                "additionalProperties": False,
            },
        },
        "faq": {
            "type": "array", "minItems": 3, "maxItems": 5,
            "items": {
                "type": "object",
                "properties": {
                    "question": {"type": "string", "minLength": 10},
                    "answer": {"type": "string", "minLength": 60},
                },
                "required": ["question", "answer"],
                "additionalProperties": False,
            },
        },
        "social_post": {"type": "string", "minLength": 50, "maxLength": 220},
    },
    "required": ["title", "meta_description", "summary", "key_takeaways", "sections", "faq", "social_post"],
    "additionalProperties": False,
}

WRITER_INSTRUCTIONS = """You are the Next Jailbreak technical news editor.
Write one original, useful news/guide article from the ORIGINAL SOURCE MATERIAL supplied.

Hard rules:
- iOS Repo Updates is only a discovery mechanism and must never be cited, mentioned, linked or treated as evidence.
- Every release-specific fact, version, compatibility statement, feature, change, dependency, developer claim, or installation statement must be supported by ORIGINAL SOURCE MATERIAL.
- Never invent testing. Do not say we/I tested, verified on-device, installed, measured, or confirmed behavior unless the original source explicitly says Next Jailbreak did so.
- Do not provide pirated, cracked, mirrored, bypassed, or unofficial downloads.
- Do not include URLs in generated fields. The renderer adds verified original-source links.
- Focus on what changed, why the update matters to users, compatibility implications that are explicitly supported, and what readers should verify before installing.
- Avoid package-metadata filler, keyword stuffing, repetitive wording, fake quotes, popularity claims, and unsupported recommendations.
- Stable technical background may be used only to explain terminology already present in the source; do not use it to expand compatibility or feature claims.
- Target 1,000-1,400 useful words across the article and FAQ.
"""

VERIFIER_INSTRUCTIONS = """You are a strict factual verifier for Next Jailbreak.
Compare the proposed article only against ORIGINAL SOURCE MATERIAL. Reject unsupported release facts, compatibility, features, behavior, installation claims, testing claims, invented changelogs, URLs inside model fields, piracy/bypass content, thin/repetitive SEO prose, or any mention/citation of iOS Repo Updates. Stable explanatory background is acceptable only when it does not expand source-specific claims. Return approved=true only if the draft is substantial and source-grounded.
"""

REPAIR_INSTRUCTIONS = """Rewrite the rejected Next Jailbreak article. Fix every rejection reason. Use ORIGINAL SOURCE MATERIAL for all source-specific claims, remove unsupported claims rather than inventing replacements, never mention iOS Repo Updates, do not include URLs, and keep the article substantive (1,000-1,400 useful words)."""


@dataclass(frozen=True)
class Candidate:
    discovery_url: str
    package_id: str
    repo_slug: str
    label: str
    rank: int


class _DiscoveryParser(HTMLParser):
    def __init__(self, base_url: str) -> None:
        super().__init__(convert_charrefs=True)
        self.base_url = base_url
        self.current_href: str | None = None
        self.current_text: list[str] = []
        self.links: list[tuple[str, str]] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() != "a":
            return
        values = {str(k).lower(): str(v or "") for k, v in attrs}
        href = values.get("href", "").strip()
        if href:
            self.current_href = urljoin(self.base_url, href)
            self.current_text = []

    def handle_data(self, data: str) -> None:
        if self.current_href:
            self.current_text.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() == "a" and self.current_href:
            label = " ".join("".join(self.current_text).split())
            self.links.append((self.current_href, label))
            self.current_href = None
            self.current_text = []


class _SourceLinkParser(HTMLParser):
    def __init__(self, base_url: str) -> None:
        super().__init__(convert_charrefs=True)
        self.base_url = base_url
        self.links: list[str] = []
        self.text: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() == "a":
            values = {str(k).lower(): str(v or "") for k, v in attrs}
            href = values.get("href", "").strip()
            if href:
                self.links.append(urljoin(self.base_url, href))

    def handle_data(self, data: str) -> None:
        value = " ".join(data.split())
        if value:
            self.text.append(value)


def _request(url: str, *, accept: str = "text/html,*/*;q=0.7", max_bytes: int = MAX_TEXT_BYTES) -> tuple[bytes, str]:
    request = Request(url, headers={"User-Agent": USER_AGENT, "Accept": accept, "Accept-Language": "en-US,en;q=0.8"})
    with urlopen(request, timeout=25) as response:  # nosec - URLs come from configured/public source discovery
        body = response.read(max_bytes + 1)
        if len(body) > max_bytes:
            raise ValueError("source exceeded maximum allowed size")
        content_type = str(response.headers.get("Content-Type", "")).split(";", 1)[0].lower()
        return body, content_type


def _fetch_text(url: str) -> str:
    body, content_type = _request(url)
    if "gzip" in content_type or url.lower().endswith(".gz"):
        body = gzip.decompress(body)
    elif "bzip" in content_type or url.lower().endswith(".bz2"):
        body = bz2.decompress(body)
    return body.decode("utf-8", errors="replace")


def _html_text(value: str) -> tuple[str, list[str]]:
    parser = _SourceLinkParser("https://invalid.local/")
    parser.feed(value)
    return " ".join(parser.text), parser.links


def _source_page_text(url: str) -> tuple[str, list[str]]:
    body, content_type = _request(url)
    text = body.decode("utf-8", errors="replace")
    if "html" not in content_type and not text.lstrip().lower().startswith(("<!doctype", "<html")):
        return text, []
    parser = _SourceLinkParser(url)
    parser.feed(text)
    return "\n".join(parser.text), parser.links


def _words(value: str) -> int:
    return len(re.findall(r"\b[\w’'-]+\b", value, re.UNICODE))


def _slug(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")[:80] or "ios-update"


def _external(url: str) -> bool:
    return urlparse(url).netloc.lower() not in DISCOVERY_HOSTS


def _candidate_parts(url: str) -> tuple[str, str] | None:
    path = urlparse(url).path
    match = re.search(r"/repository/([^/]+)/package/([^/]+)/?", path, re.I)
    if not match:
        return None
    return match.group(1), match.group(2)


def _score(label: str, config: dict[str, Any]) -> int:
    lowered = label.lower()
    score = 0
    for section, value in config.get("section_score", {}).items():
        if str(section).lower() in lowered:
            score += int(value)
    for keyword, value in config.get("keyword_score", {}).items():
        if str(keyword).lower() in lowered:
            score += int(value)
    return score


def discover(config: dict[str, Any]) -> list[Candidate]:
    url = str(config["discovery_url"])
    html_text = _fetch_text(url)
    parser = _DiscoveryParser(url)
    parser.feed(html_text)
    found: dict[str, Candidate] = {}
    for href, label in parser.links:
        parts = _candidate_parts(href)
        if not parts:
            continue
        repo_slug, package_id = parts
        key = f"{repo_slug}/{package_id}"
        if key in found:
            continue
        found[key] = Candidate(href, package_id, repo_slug, label, _score(label, config))
    return sorted(found.values(), key=lambda item: (-item.rank, item.discovery_url))


def _parse_package_stanzas(text: str) -> list[dict[str, str]]:
    stanzas: list[dict[str, str]] = []
    current: dict[str, str] = {}
    last_key: str | None = None
    for line in text.replace("\r\n", "\n").split("\n"):
        if not line.strip():
            if current:
                stanzas.append(current)
                current = {}
                last_key = None
            continue
        if line[:1].isspace() and last_key:
            current[last_key] = current[last_key] + "\n" + line.strip()
            continue
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        last_key = key.strip()
        current[last_key] = value.strip()
    if current:
        stanzas.append(current)
    return stanzas


def _candidate_hint_links(candidate: Candidate) -> list[str]:
    # Discovery page is used ONLY to locate original-source URLs. Its prose is never
    # passed to the writer/verifier and never appears in the public article.
    text = _fetch_text(candidate.discovery_url)
    parser = _SourceLinkParser(candidate.discovery_url)
    parser.feed(text)
    result: list[str] = []
    for url in parser.links:
        parsed = urlparse(url)
        if parsed.scheme not in {"http", "https"} or not parsed.netloc or not _external(url):
            continue
        result.append(url)
    return list(dict.fromkeys(result))


def _repo_roots(hints: Iterable[str]) -> list[str]:
    roots: list[str] = []
    for url in hints:
        parsed = urlparse(url)
        if parsed.scheme not in {"http", "https"} or not parsed.netloc:
            continue
        if parsed.netloc.lower() in {"github.com", "www.github.com"}:
            continue
        root = f"{parsed.scheme}://{parsed.netloc}/"
        roots.append(root)
    return list(dict.fromkeys(roots))


def _official_stanza(candidate: Candidate, hints: list[str]) -> tuple[dict[str, str] | None, str | None]:
    paths = ("Packages", "Packages.gz", "Packages.bz2", "dists/stable/main/binary-iphoneos-arm/Packages", "dists/stable/main/binary-iphoneos-arm64/Packages")
    for root in _repo_roots(hints):
        for path in paths:
            url = urljoin(root, path)
            try:
                raw = _fetch_text(url)
            except Exception:
                continue
            for stanza in _parse_package_stanzas(raw):
                if stanza.get("Package", "").strip().lower() == candidate.package_id.lower():
                    return stanza, url
    return None, None


def _github_repo_from_url(url: str) -> tuple[str, str] | None:
    parsed = urlparse(url)
    if parsed.netloc.lower() not in {"github.com", "www.github.com"}:
        return None
    parts = [p for p in parsed.path.split("/") if p]
    if len(parts) < 2:
        return None
    if parts[0] in {"topics", "search", "features", "marketplace"}:
        return None
    return parts[0], parts[1].removesuffix(".git")


def _github_material(owner: str, repo: str) -> tuple[str, list[str]]:
    api = f"https://api.github.com/repos/{owner}/{repo}"
    material: list[str] = []
    source_urls = [f"https://github.com/{owner}/{repo}"]
    try:
        repo_meta = json.loads(_fetch_text(api))
        if isinstance(repo_meta, dict):
            material.append("OFFICIAL GITHUB REPOSITORY METADATA:\n" + json.dumps({
                "full_name": repo_meta.get("full_name"),
                "description": repo_meta.get("description"),
                "homepage": repo_meta.get("homepage"),
                "default_branch": repo_meta.get("default_branch"),
                "updated_at": repo_meta.get("updated_at"),
            }, ensure_ascii=False))
            branch = str(repo_meta.get("default_branch") or "main")
            try:
                readme = _fetch_text(f"https://raw.githubusercontent.com/{owner}/{repo}/{branch}/README.md")
                material.append("OFFICIAL README:\n" + readme[:18000])
            except Exception:
                pass
    except Exception:
        pass
    try:
        commits = json.loads(_fetch_text(f"{api}/commits?per_page=3"))
        if isinstance(commits, list):
            for item in commits[:3]:
                sha = str(item.get("sha", "")) if isinstance(item, dict) else ""
                if not sha:
                    continue
                detail = json.loads(_fetch_text(f"{api}/commits/{sha}"))
                if not isinstance(detail, dict):
                    continue
                compact = {
                    "sha": detail.get("sha"),
                    "html_url": detail.get("html_url"),
                    "commit": detail.get("commit"),
                    "files": [
                        {"filename": f.get("filename"), "status": f.get("status"), "patch": str(f.get("patch") or "")[:9000]}
                        for f in detail.get("files", [])[:8] if isinstance(f, dict)
                    ],
                }
                material.append("OFFICIAL RECENT COMMIT:\n" + json.dumps(compact, ensure_ascii=False)[:24000])
                if detail.get("html_url"):
                    source_urls.append(str(detail["html_url"]))
    except Exception:
        pass
    return "\n\n".join(material), list(dict.fromkeys(source_urls))


def resolve_original_source(candidate: Candidate, config: dict[str, Any]) -> dict[str, Any]:
    hints = _candidate_hint_links(candidate)
    stanza, packages_url = _official_stanza(candidate, hints)
    source_urls: list[str] = []
    material: list[str] = []
    name = candidate.package_id
    version = ""
    description = ""

    if stanza:
        name = stanza.get("Name") or name
        version = stanza.get("Version", "")
        description = stanza.get("Description", "")
        material.append("OFFICIAL REPOSITORY PACKAGE STANZA:\n" + "\n".join(f"{k}: {v}" for k, v in stanza.items()))
        if packages_url:
            source_urls.append(packages_url)
        for key in ("Homepage", "Depiction", "SileoDepiction", "Website"):
            value = stanza.get(key, "").strip()
            if value.startswith(("http://", "https://")):
                source_urls.append(value)

    # External discovery links are pointers only. Once followed, the original page
    # becomes the evidence. Prefer developer/project pages over binary downloads.
    for url in hints:
        lowered = url.lower()
        if lowered.endswith(".deb") or "/download" in lowered:
            continue
        source_urls.append(url)

    source_urls = [u for u in dict.fromkeys(source_urls) if _external(u)]

    github_repos: list[tuple[str, str]] = []
    for url in source_urls:
        repo = _github_repo_from_url(url)
        if repo and repo not in github_repos:
            github_repos.append(repo)

    # If the official repo stanza did not expose GitHub, use GitHub repository
    # search only as a locator, then verify against the actual repository content.
    if not github_repos and name:
        try:
            query = quote_plus(f'"{name}"')
            search = json.loads(_fetch_text(f"https://api.github.com/search/repositories?q={query}+in:name,description&per_page=5"))
            if isinstance(search, dict):
                for item in search.get("items", []):
                    if not isinstance(item, dict):
                        continue
                    full = str(item.get("full_name", ""))
                    if "/" not in full:
                        continue
                    owner, repo = full.split("/", 1)
                    github_repos.append((owner, repo))
                    break
        except Exception:
            pass

    for owner, repo in github_repos[:2]:
        text, urls = _github_material(owner, repo)
        if text:
            material.append(text)
            source_urls.extend(urls)

    # Fetch original depiction/homepage/project text. Do not fetch discovery URLs.
    for url in list(dict.fromkeys(source_urls))[:8]:
        if urlparse(url).netloc.lower() in DISCOVERY_HOSTS:
            continue
        if url.lower().endswith(("packages", "packages.gz", "packages.bz2")):
            continue
        try:
            text, outbound = _source_page_text(url)
        except Exception:
            continue
        if _words(text) >= 40:
            material.append(f"ORIGINAL SOURCE PAGE {url}:\n{text[:18000]}")
        for outbound_url in outbound:
            if _github_repo_from_url(outbound_url):
                source_urls.append(outbound_url)

    source_urls = [u for u in dict.fromkeys(source_urls) if _external(u)]
    source_text = "\n\n".join(material)
    if not stanza and not source_text.strip():
        raise ValueError("could not resolve an original developer/repository source")
    if _words(source_text) < int(config.get("minimum_source_words", 180)):
        raise ValueError("original source material is too thin for a high-value article")
    if any(host in source_text.lower() for host in DISCOVERY_HOSTS):
        # Package pages can occasionally echo referrers. Never let discovery content
        # become model evidence.
        source_text = re.sub(r"https?://(?:www\.)?ios-repo-updates\.com/\S*", "", source_text, flags=re.I)

    return {
        "name": str(name),
        "version": str(version),
        "description": str(description),
        "package_id": candidate.package_id,
        "source_urls": source_urls,
        "source_text": source_text[:65000],
    }


def validate_article(article: dict[str, Any], source: dict[str, Any], config: dict[str, Any]) -> list[str]:
    issues: list[str] = []
    serialized = json.dumps(article, ensure_ascii=False)
    if "ios repo updates" in serialized.lower() or "ios-repo-updates" in serialized.lower():
        issues.append("discovery site must not be mentioned or cited")
    if re.search(r"https?://", serialized, re.I):
        issues.append("model-generated fields must not contain URLs")
    if re.search(r"\b(?:we|i)\s+(?:tested|installed|verified|confirmed|used)\b", serialized, re.I):
        issues.append("unsupported hands-on testing claim")
    if re.search(r"\b(?:crack(?:ed)?|pirated?|warez|license bypass|iap bypass)\b", serialized, re.I):
        issues.append("piracy/bypass language")
    meta = str(article.get("meta_description", ""))
    if not 110 <= len(meta) <= 165:
        issues.append("meta description must be 110-165 characters")
    prose: list[str] = [str(article.get("summary", ""))]
    prose.extend(str(v) for v in article.get("key_takeaways", []))
    sections = article.get("sections", [])
    if not isinstance(sections, list) or len(sections) < int(config.get("minimum_sections", 5)):
        issues.append("article does not contain enough substantive sections")
    for section in sections if isinstance(sections, list) else []:
        if isinstance(section, dict):
            prose.extend(str(v) for v in section.get("paragraphs", []))
            prose.extend(str(v) for v in section.get("bullets", []))
    for item in article.get("faq", []):
        if isinstance(item, dict):
            prose.append(str(item.get("answer", "")))
    count = _words(" ".join(prose))
    minimum = int(config.get("minimum_article_words", 900))
    if count < minimum:
        issues.append(f"article is too thin: {count} words; minimum {minimum}")
    weak = ("supplied package facts", "listed architectures", "listed dependencies", "package overview")
    if sum(serialized.lower().count(v) for v in weak) >= 2:
        issues.append("article is package-metadata/template heavy")
    return sorted(set(issues))


def generate_article(source: dict[str, Any], site: dict[str, Any], config: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    model = os.environ.get("OPENAI_MODEL", str(site.get("default_model", "gpt-5.6-luna")))
    payload = {
        "package_name": source["name"],
        "package_id": source["package_id"],
        "official_version": source["version"],
        "official_description": source["description"],
        "ORIGINAL_SOURCE_MATERIAL": source["source_text"],
    }
    article, writer_meta = structured_response(
        model=model, instructions=WRITER_INSTRUCTIONS, input_payload=payload,
        schema_name="nextjailbreak_original_source_news", schema=ARTICLE_SCHEMA, max_output_tokens=10000,
    )
    verifier, verifier_meta = structured_response(
        model=model, instructions=VERIFIER_INSTRUCTIONS,
        input_payload={"ORIGINAL_SOURCE_MATERIAL": source["source_text"], "article": article},
        schema_name="nextjailbreak_original_source_news_verdict", schema=VERDICT_SCHEMA, max_output_tokens=1800,
    )
    issues = validate_article(article, source, config)
    reasons = issues + list(verifier.get("issues", [])) + list(verifier.get("unsupported_claims", []))
    if issues or verifier.get("approved") is not True or reasons:
        article, repair_meta = structured_response(
            model=model, instructions=REPAIR_INSTRUCTIONS,
            input_payload={"ORIGINAL_SOURCE_MATERIAL": source["source_text"], "rejected_article": article, "reasons": list(dict.fromkeys(reasons or ["verifier rejected draft"]))},
            schema_name="nextjailbreak_original_source_news_repair", schema=ARTICLE_SCHEMA, max_output_tokens=10000,
        )
        verifier, final_meta = structured_response(
            model=model, instructions=VERIFIER_INSTRUCTIONS,
            input_payload={"ORIGINAL_SOURCE_MATERIAL": source["source_text"], "article": article},
            schema_name="nextjailbreak_original_source_news_final_verdict", schema=VERDICT_SCHEMA, max_output_tokens=1800,
        )
        issues = validate_article(article, source, config)
        if issues or verifier.get("approved") is not True or verifier.get("issues") or verifier.get("unsupported_claims"):
            raise ValueError("article failed 9/10 quality gate: " + "; ".join(issues + list(verifier.get("issues", [])) + list(verifier.get("unsupported_claims", []))))
        return article, {"writer": writer_meta, "initial_verifier": verifier_meta, "repair": repair_meta, "verifier": final_meta}
    return article, {"writer": writer_meta, "verifier": verifier_meta}


def _render_article(article: dict[str, Any], source: dict[str, Any], media: dict[str, str], site: dict[str, Any], now: datetime, target_path: str) -> str:
    esc = lambda value: html.escape(str(value), quote=True)
    base = str(site["base_url"]).rstrip("/")
    canonical = f"{base}/{target_path}"
    hero_url = f"{base}/{media['image']}"
    date = now.date().isoformat()
    takeaways = "".join(f"<li>{esc(v)}</li>" for v in article["key_takeaways"])
    sections: list[str] = []
    for section in article["sections"]:
        paragraphs = "".join(f"<p>{esc(v)}</p>" for v in section["paragraphs"])
        bullets = "<ul>" + "".join(f"<li>{esc(v)}</li>" for v in section["bullets"]) + "</ul>" if section["bullets"] else ""
        sections.append(f"<h2>{esc(section['heading'])}</h2>{paragraphs}{bullets}")
    faqs = "".join(f"<details><summary>{esc(v['question'])}</summary><p>{esc(v['answer'])}</p></details>" for v in article["faq"])
    source_buttons = "".join(
        f'<a class="button button-primary" href="{esc(url)}" rel="nofollow noopener noreferrer">Open original source</a>'
        for url in source["source_urls"][:3]
        if urlparse(url).netloc.lower() not in DISCOVERY_HOSTS
    )
    client = str(site.get("adsense_client", "")).strip()
    adsense_meta = f'<meta name="google-adsense-account" content="{esc(client)}">' if client else ""
    adsense_script = f'<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client={esc(client)}" crossorigin="anonymous"></script>' if client else ""
    structured = {
        "@context": "https://schema.org", "@type": "TechArticle",
        "headline": article["title"], "description": article["meta_description"],
        "datePublished": date, "dateModified": date,
        "author": {"@type": "Person", "name": site.get("author_name", "Next Jailbreak")},
        "publisher": {"@type": "Organization", "name": site.get("site_name", "Next Jailbreak"), "url": base},
        "mainEntityOfPage": canonical, "image": hero_url,
    }
    return f'''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <meta name="theme-color" content="#f3f5f6">
  <title>{esc(article['title'])} | Next Jailbreak</title>
  <meta name="description" content="{esc(article['meta_description'])}">
  <meta name="robots" content="index,follow,max-image-preview:large">
  <link rel="canonical" href="{esc(canonical)}">
  <link rel="alternate" type="application/rss+xml" title="Next Jailbreak articles" href="/feed.xml">
  <link rel="icon" type="image/svg+xml" href="/assets/brand/next-jailbreak-mark.svg">
  <link rel="stylesheet" href="/assets/site.css">
  <meta property="og:type" content="article">
  <meta property="og:site_name" content="Next Jailbreak">
  <meta property="og:url" content="{esc(canonical)}">
  <meta property="og:title" content="{esc(article['title'])}">
  <meta property="og:description" content="{esc(article['meta_description'])}">
  <meta property="og:image" content="{esc(hero_url)}">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="{esc(article['title'])}">
  <meta name="twitter:description" content="{esc(article['meta_description'])}">
  <meta name="twitter:image" content="{esc(hero_url)}">
  {adsense_meta}
  {adsense_script}
  <script type="application/ld+json">{json.dumps(structured, ensure_ascii=False)}</script>
</head>
<body>
  <div class="topline"><div class="topline-inner"><span>iPhone jailbreak guides, tweak reviews and practical fixes</span><span class="topline-status"><i aria-hidden="true"></i> Direct links to original sources</span></div></div>
  <header class="site-header"><div class="nav-shell"><a class="brand" href="/" aria-label="Next Jailbreak home"><img class="brand-logo" src="/assets/brand/next-jailbreak-mark.svg" alt="" width="52" height="52"><span class="brand-name"><strong>Next</strong> Jailbreak</span></a><nav aria-label="Primary navigation"><ul class="nav-links"><li><a href="/">Blog</a></li><li><a href="/tutorials/#verified-articles">Tweaks</a></li><li><a href="/tutorials/#jailbreak-guides">Jailbreak</a></li><li><a href="/videos/">Videos</a></li></ul></nav></div></header>
  <main class="container article-main">
    <nav class="breadcrumbs" aria-label="Breadcrumb"><a href="/">Home</a><span aria-hidden="true">/</span><a href="/tutorials/#verified-articles">Latest updates</a><span aria-hidden="true">/</span><span>{esc(source['name'])}</span></nav>
    <article>
      <header class="article-hero"><span class="article-kicker">Latest update · Original-source editorial</span><h1>{esc(article['title'])}</h1><p class="article-summary">{esc(article['summary'])}</p></header>
      <figure class="article-visual"><img src="/{esc(media['image'])}" alt="Original source visual for {esc(source['name'])}" fetchpriority="high"><figcaption>{esc(media['credit'])}. The article is based on the developer/repository sources linked below.</figcaption></figure>
      <div class="article-layout"><div class="article-content">
        <h2>Key points</h2><ul>{takeaways}</ul>
        {''.join(sections)}
        <h2>Frequently asked questions</h2><div class="faq-list">{faqs}</div>
        <div class="article-disclaimer"><strong>Before installing:</strong> confirm the current package version, compatibility and dependencies at the original developer/repository source for your exact device and jailbreak.</div>
        <p class="article-footnote">Original-source editorial · Published {date} · Next Jailbreak</p>
      </div><aside class="article-sidebar" aria-label="Original source information"><h2>Original sources</h2><p>These are the developer/repository pages used to verify this article.</p><div class="button-stack">{source_buttons}</div><p class="source-note">Next Jailbreak does not mirror the package binary on this page.</p></aside></div>
    </article>
  </main>
  <footer class="site-footer"><div class="footer-shell"><div class="footer-brand"><a class="brand" href="/"><img class="brand-logo" src="/assets/brand/next-jailbreak-mark.svg" alt="" width="52" height="52"><span class="brand-name"><strong>Next</strong> Jailbreak</span></a><p>Jailbreak news, useful tweak information, practical guides, and original videos.</p></div><div class="footer-column"><strong>Read</strong><a href="/#latest">Latest articles</a><a href="/tutorials/#verified-articles">Tweaks</a><a href="/tutorials/#jailbreak-guides">Jailbreak</a></div><div class="footer-column"><strong>Legal</strong><a href="/privacy/">Privacy</a><a href="/terms/">Terms</a></div></div><div class="footer-bottom"><div class="container"><span>© 2026 Next Jailbreak</span></div></div></footer>
  <script defer src="/assets/site-runtime.js" data-ns-site-runtime="1"></script>
</body>
</html>\n'''


def _load_json(path: Path, default: Any = None) -> Any:
    if not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def _publication_times(audit: dict[str, Any]) -> list[datetime]:
    result: list[datetime] = []
    for entry in audit.get("entries", []):
        if not isinstance(entry, dict):
            continue
        value = entry.get("modified_at") or entry.get("published_at")
        if not isinstance(value, str):
            continue
        try:
            dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
            if dt.tzinfo:
                result.append(dt.astimezone(timezone.utc))
        except ValueError:
            pass
    return result


def preflight(config: dict[str, Any], audit: dict[str, Any], now: datetime) -> tuple[bool, str]:
    if config.get("enabled") is not True:
        return False, "disabled"
    tz = ZoneInfo(str(config.get("timezone", "Asia/Qatar")))
    local_day = now.astimezone(tz).date()
    today = 0
    for entry in audit.get("entries", []):
        if not isinstance(entry, dict) or entry.get("entry_type") != "source-news":
            continue
        value = entry.get("published_at")
        if not isinstance(value, str):
            continue
        try:
            dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
            if dt.tzinfo and dt.astimezone(tz).date() == local_day:
                today += 1
        except ValueError:
            pass
    if today >= int(config.get("max_per_day", 2)):
        return False, "daily-source-news-limit"
    times = _publication_times(audit)
    if times:
        gap = timedelta(minutes=int(config.get("minimum_site_gap_minutes", 90)))
        if now.astimezone(timezone.utc) - max(times) < gap:
            return False, "site-publication-gap"
    return True, "ready"


def _is_duplicate(audit: dict[str, Any], package_id: str, version: str) -> bool:
    for entry in audit.get("entries", []):
        if not isinstance(entry, dict):
            continue
        if str(entry.get("package", "")).lower() == package_id.lower():
            if not version or str(entry.get("version", "")) == version:
                return True
    return False


def _write_output(path: Path | None, values: dict[str, Any]) -> None:
    if path is None:
        return
    with path.open("a", encoding="utf-8") as handle:
        for key, value in values.items():
            text = str(value).lower() if isinstance(value, bool) else str(value)
            if "\n" in text:
                continue
            handle.write(f"{key}={text}\n")


def publish(*, repository_root: Path, now: datetime, run_id: str, github_output: Path | None, confirm_live: bool) -> dict[str, Any]:
    if not confirm_live:
        raise ValueError("live publication requires --confirm-live")
    site = _load_json(repository_root / "automation/site.json")
    config = _load_json(repository_root / "automation/ios_repo_news.json")
    audit_path = repository_root / "automation/published-articles.json"
    audit = load_audit(audit_path)
    allowed, reason = preflight(config, audit, now)
    if not allowed:
        result = {"published": False, "reason": reason, "target_path": ""}
        _write_output(github_output, result)
        return result

    state_path = repository_root / "automation/ios-repo-news-state.json"
    state = _load_json(state_path, {"schema_version": 1, "attempts": {}, "events": []})
    attempts = state.setdefault("attempts", {})
    candidates = discover(config)
    failures: list[str] = []
    selected_source: dict[str, Any] | None = None
    selected_candidate: Candidate | None = None
    max_attempts = int(config.get("max_candidate_attempts", 8))

    for candidate in candidates[:max_attempts]:
        previous = attempts.get(candidate.discovery_url, {})
        if isinstance(previous, dict) and previous.get("status") == "failed":
            stamp = previous.get("checked_at")
            try:
                checked = datetime.fromisoformat(str(stamp).replace("Z", "+00:00"))
                if checked.tzinfo and now - checked.astimezone(timezone.utc) < timedelta(hours=20):
                    continue
            except ValueError:
                pass
        try:
            source = resolve_original_source(candidate, config)
            source_version = str(source.get("version", "")).strip()
            expected_slug = _slug(f"{source['name']} {source_version} update".strip())
            expected_target_path = f"{expected_slug}/"
            expected_target = repository_root / expected_target_path / "index.html"
            if _is_duplicate(audit, candidate.package_id, source_version) or expected_target.exists():
                attempts[candidate.discovery_url] = {
                    "status": "duplicate",
                    "checked_at": now.isoformat(),
                    "package": candidate.package_id,
                    "version": source_version,
                    "target_path": expected_target_path,
                }
                continue
            if not source.get("source_urls"):
                raise ValueError("no original source URLs resolved")
            selected_candidate, selected_source = candidate, source
            break
        except Exception as exc:
            failures.append(f"{candidate.package_id}: {str(exc)[:180]}")
            attempts[candidate.discovery_url] = {"status": "failed", "checked_at": now.isoformat(), "package": candidate.package_id, "reason": str(exc)[:300]}

    if selected_candidate is None or selected_source is None:
        state["events"].append({"at": now.isoformat(), "action": "no-op", "reason": "no-high-quality-original-source-candidate", "failures": failures[:8]})
        state_path.write_text(json.dumps(state, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")
        result = {"published": False, "reason": "no-high-quality-original-source-candidate", "target_path": ""}
        _write_output(github_output, result)
        return result

    article, api_meta = generate_article(selected_source, site, config)
    version = str(selected_source.get("version", "")).strip()
    slug_base = f"{selected_source['name']} {version} update".strip()
    slug = _slug(slug_base)
    target_path = f"{slug}/"
    target = repository_root / target_path / "index.html"
    if target.exists():
        attempts[selected_candidate.discovery_url] = {
            "status": "duplicate",
            "checked_at": now.isoformat(),
            "package": selected_candidate.package_id,
            "version": version,
            "target_path": target_path,
        }
        state["events"].append({
            "at": now.isoformat(),
            "action": "no-op",
            "reason": "target-already-exists",
            "package": selected_candidate.package_id,
            "version": version,
            "target_path": target_path,
        })
        state_path.write_text(json.dumps(state, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")
        result = {"published": False, "reason": "target-already-exists", "target_path": target_path}
        _write_output(github_output, result)
        return result

    media = acquire_unique_source_visual(
        source_urls=selected_source["source_urls"],
        slug=slug,
        repository_root=repository_root,
    )
    rendered = _render_article(article, selected_source, media, site, now, target_path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(rendered, encoding="utf-8")

    published_at = now.astimezone(timezone.utc).replace(microsecond=0).isoformat()
    entry = {
        "entry_type": "source-news",
        "package": selected_candidate.package_id,
        "name": selected_source["name"],
        "version": version,
        "title": article["title"],
        "description": article["meta_description"],
        "href": target_path,
        "category": {"id": "system-utilities", "label": "System & Utilities"},
        "source_name": urlparse(selected_source["source_urls"][0]).netloc.removeprefix("www."),
        "source_url": selected_source["source_urls"][0],
        "source_page_url": selected_source["source_urls"][0],
        "selection_pool": "ios-repo-discovery-original-source",
        "image": media["image"],
        "media_credit": media["credit"],
        "media_source_url": media["source_url"],
        "source_visual_url": media["image_url"],
        "source_visual_origin": media["origin"],
        "published_at": published_at,
        "modified_at": published_at,
        "quality_target": int(config.get("quality_target", 9)),
    }
    entries = [e for e in audit["entries"] if not (isinstance(e, dict) and e.get("href") == target_path)]
    entries.append(entry)
    entries.sort(key=lambda e: str(e.get("modified_at") or e.get("published_at") or ""), reverse=True)
    next_audit = {"schema_version": 1, "updated_at": published_at, "entries": entries, "events": audit.get("events", []) + [{"published_at": published_at, "action": "create", "package": selected_candidate.package_id, "version": version, "href": target_path, "channel": "ios-repo-discovery-original-source", "run_id": run_id}]}
    audit_path.write_text(json.dumps(next_audit, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")
    (repository_root / "feed.xml").write_text(_render_feed(entries, site), encoding="utf-8")
    sitemap_path = repository_root / "sitemap.xml"
    sitemap_path.write_text(_update_sitemap(sitemap_path.read_text(encoding="utf-8"), entries, site), encoding="utf-8")

    attempts[selected_candidate.discovery_url] = {"status": "published", "checked_at": published_at, "package": selected_candidate.package_id, "version": version, "target_path": target_path}
    state["events"].append({"at": published_at, "action": "published", "package": selected_candidate.package_id, "version": version, "target_path": target_path, "api": api_meta})
    state_path.write_text(json.dumps(state, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")

    result = {"published": True, "reason": "published", "target_path": target_path, "title": article["title"], "package": selected_candidate.package_id, "version": version}
    _write_output(github_output, result)
    return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository-root", type=Path, default=Path("."))
    parser.add_argument("--now")
    parser.add_argument("--run-id", default="local")
    parser.add_argument("--github-output", type=Path)
    parser.add_argument("--confirm-live", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        now = datetime.fromisoformat(args.now.replace("Z", "+00:00")) if args.now else datetime.now(timezone.utc)
        if now.tzinfo is None:
            raise ValueError("--now must include a timezone")
        result = publish(repository_root=args.repository_root.resolve(), now=now.astimezone(timezone.utc), run_id=args.run_id, github_output=args.github_output, confirm_live=args.confirm_live)
        print(json.dumps(result, sort_keys=True, ensure_ascii=False))
        return 0
    except (OpenAIAPIError, ValueError, json.JSONDecodeError) as exc:
        print(f"iOS Repo original-source publisher error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
