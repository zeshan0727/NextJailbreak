#!/usr/bin/env python3
"""User-authorized Next Jailbreak tweak-update batch for 28 Sep 2026.

Publishes the selected recent tweak updates with the existing original-source
writer/verifier, source-visual acquisition, SEO renderer, feed/sitemap sync and
community comments. Monetag is enforced on every resulting editorial page.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import re
from urllib.parse import urlparse

from automation import sync_editorial_indexes
from automation.community_comments import ensure_community_comments
from automation.ios_repo_news import (
    _github_material,
    _render_article,
    _render_feed,
    _slug,
    _source_page_text,
    _update_sitemap,
    _words,
    generate_article,
)
from automation.publisher import load_audit
from automation.seo_utils import seo_description
from automation.source_visuals import acquire_unique_source_visual

ROOT = Path(__file__).resolve().parents[1]
SITE = json.loads((ROOT / "automation/site.json").read_text(encoding="utf-8"))
CONFIG = json.loads((ROOT / "automation/ios_repo_news.json").read_text(encoding="utf-8"))
CONFIG = {**CONFIG, "minimum_article_words": 1000, "minimum_sections": 5}
TARGETS = json.loads((ROOT / "automation/article_batch_20260928.json").read_text(encoding="utf-8"))
AUDIT_PATH = ROOT / "automation/published-articles.json"
REPORT = ROOT / "automation/batch-20260928-result.json"
MONETAG_META = '<meta name="monetag" content="afa6c0ac5c051fa9058f934da7f2c324">'
MONETAG_LOADER = '  <script defer src="/assets/adsterra.js?v=20260910-1" data-ns-monetag-loader="1"></script>'
RUNTIME = '  <script defer src="/assets/site-runtime.js" data-ns-site-runtime="1"></script>'


def dedupe(values):
    return list(dict.fromkeys(v for v in values if v))


def build_source(target: dict) -> dict:
    material: list[str] = []
    source_urls = list(target.get("urls", []))
    for owner, repo in target.get("github", []):
        text, urls = _github_material(owner, repo)
        if text:
            material.append(f"ORIGINAL GITHUB PROJECT {owner}/{repo}:\n{text[:30000]}")
        source_urls.extend(urls)

    for url in dedupe(source_urls):
        try:
            text, _ = _source_page_text(url)
        except Exception as exc:
            material.append(f"SOURCE FETCH NOTE for {url}: {type(exc).__name__}")
            continue
        if _words(text) >= 12:
            material.append(f"ORIGINAL SOURCE PAGE {url}:\n{text[:30000]}")

    if target.get("scope_note"):
        material.append(
            "EDITORIAL BRIEF (scope guidance only; not independent evidence):\n"
            + str(target["scope_note"])
        )

    source_text = "\n\n".join(material)
    if _words(source_text) < 40:
        raise ValueError(f"{target['name']}: original source material is too thin")
    if not target.get("skip_version_check") and str(target["version"]).lower() not in source_text.lower():
        raise ValueError(f"{target['name']}: exact version {target['version']} not found in original source material")

    return {
        "name": target["name"],
        "version": target["version"],
        "description": target["description"],
        "package_id": target["package_id"],
        "source_urls": dedupe(source_urls),
        "source_text": source_text[:90000],
    }


def generate_strict(source: dict):
    errors = []
    for attempt in range(1, 4):
        try:
            return generate_article(source, SITE, CONFIG)
        except Exception as exc:
            errors.append(f"attempt {attempt}: {str(exc)[:300]}")
            print(f"QUALITY RETRY {source['name']} {source['version']} attempt {attempt}: {exc}", flush=True)
    raise ValueError(" | ".join(errors))


def monetag_normalize(text: str) -> str:
    text = re.sub(r'\s*<meta\s+name=["\']google-adsense-account["\'][^>]*>\s*', "\n", text, flags=re.I)
    text = re.sub(r'\s*<script\b[^>]*pagead2\.googlesyndication\.com/pagead/js/adsbygoogle\.js[^>]*>\s*</script>\s*', "\n", text, flags=re.I | re.S)
    text = re.sub(r'\s*<meta\s+name=["\']monetag["\'][^>]*>\s*', "\n", text, flags=re.I)
    text = re.sub(r'\s*<script[^>]+src=["\']/assets/adsterra\.js(?:\?[^"\']*)?["\'][^>]*>\s*</script>\s*', "\n", text, flags=re.I)
    text = re.sub(r'\s*<script[^>]+src=["\']/assets/site-runtime\.js(?:\?[^"\']*)?["\'][^>]*>\s*</script>\s*', "\n", text, flags=re.I)
    text, hc = re.subn(r'(?i)</head\s*>', "  " + MONETAG_META + "\n</head>", text, count=1)
    text, bc = re.subn(r'(?i)</body\s*>', MONETAG_LOADER + "\n" + RUNTIME + "\n</body>", text, count=1)
    if not hc or not bc:
        raise ValueError("Unable to normalize Monetag placement")
    return text


def remove_nextlock_pin() -> None:
    path = ROOT / "index.html"
    if not path.exists():
        return
    text = path.read_text(encoding="utf-8")
    updated = re.sub(
        r'\s*<!-- NEXTLOCK_RECENT_CARD_START -->.*?<!-- NEXTLOCK_RECENT_CARD_END -->\s*',
        "\n", text, flags=re.S
    )
    if updated != text:
        path.write_text(updated, encoding="utf-8")


def main() -> int:
    audit = load_audit(AUDIT_PATH)
    entries = list(audit.get("entries", []))
    events = list(audit.get("events", []))
    now = datetime.now(timezone.utc).replace(microsecond=0)
    results = []

    for index, target in enumerate(TARGETS):
        print(f"PROCESS {target['name']} {target['version']}", flush=True)
        try:
            existing = next(
                (
                    e for e in entries
                    if isinstance(e, dict)
                    and str(e.get("package", "")).lower() == str(target["package_id"]).lower()
                    and str(e.get("version", "")) == str(target["version"])
                ),
                None,
            )
            if existing:
                href = str(existing.get("href", ""))
                page = ROOT / href / "index.html" if href.endswith("/") else ROOT / href
                if page.exists():
                    page.write_text(monetag_normalize(page.read_text(encoding="utf-8")), encoding="utf-8")
                results.append({"name": target["name"], "version": target["version"], "status": "duplicate", "href": href})
                continue

            source = build_source(target)
            slug = target.get("slug") or _slug(f"{source['name']} {source['version']} update")
            target_path = f"{slug}/"
            html_path = ROOT / target_path / "index.html"
            if html_path.exists():
                html_path.write_text(monetag_normalize(html_path.read_text(encoding="utf-8")), encoding="utf-8")
                results.append({"name": source["name"], "version": source["version"], "status": "duplicate-path", "href": target_path})
                continue

            article, api_meta = generate_strict(source)
            media = acquire_unique_source_visual(
                source_urls=source["source_urls"], slug=slug, repository_root=ROOT
            )
            article_time = now + timedelta(seconds=index)
            rendered = ensure_community_comments(
                _render_article(article, source, media, SITE, article_time, target_path)
            )
            rendered = monetag_normalize(rendered)
            html_path.parent.mkdir(parents=True, exist_ok=True)
            html_path.write_text(rendered, encoding="utf-8")

            published_at = article_time.isoformat()
            entry = {
                "entry_type": "source-news",
                "package": source["package_id"],
                "name": source["name"],
                "version": source["version"],
                "title": article["title"],
                "description": seo_description(source["name"], source["version"]),
                "href": target_path,
                "category": target["category"],
                "source_name": urlparse(source["source_urls"][0]).netloc.removeprefix("www."),
                "source_url": source["source_urls"][0],
                "source_page_url": source["source_urls"][0],
                "selection_pool": "user-authorized-recent-tweak-batch-20260928",
                "image": media["image"],
                "media_credit": media["credit"],
                "media_source_url": media["source_url"],
                "source_visual_url": media["image_url"],
                "source_visual_origin": media["origin"],
                "published_at": published_at,
                "modified_at": published_at,
                "quality_target": int(CONFIG.get("quality_target", 9)),
            }
            entries.append(entry)
            events.append({
                "published_at": published_at,
                "action": "create",
                "package": source["package_id"],
                "version": source["version"],
                "href": target_path,
                "channel": "user-authorized-recent-tweak-batch-20260928",
                "api": api_meta,
            })
            results.append({"name": source["name"], "version": source["version"], "status": "published", "href": target_path})
        except Exception as exc:
            print(f"FAILED {target['name']} {target['version']}: {exc}", flush=True)
            results.append({"name": target["name"], "version": target["version"], "status": "failed", "reason": str(exc)[:600]})

    entries.sort(key=lambda e: str(e.get("modified_at") or e.get("published_at") or ""), reverse=True)
    updated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    AUDIT_PATH.write_text(json.dumps({
        "schema_version": 1,
        "updated_at": updated_at,
        "entries": entries,
        "events": events,
    }, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    (ROOT / "feed.xml").write_text(_render_feed(entries, SITE), encoding="utf-8")
    sitemap_path = ROOT / "sitemap.xml"
    sitemap_path.write_text(
        _update_sitemap(sitemap_path.read_text(encoding="utf-8"), entries, SITE),
        encoding="utf-8",
    )

    sync_editorial_indexes.main()
    remove_nextlock_pin()

    # Keep the already-published NoSafariFormKeyboard article on Monetag too.
    for page in [
        ROOT / "nosafariformkeyboard-1-0-0-update" / "index.html",
    ]:
        if page.exists():
            page.write_text(monetag_normalize(page.read_text(encoding="utf-8")), encoding="utf-8")

    REPORT.write_text(json.dumps({"updated_at": updated_at, "results": results}, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({"results": results}, ensure_ascii=False), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
