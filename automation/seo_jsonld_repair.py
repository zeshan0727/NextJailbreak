#!/usr/bin/env python3
"""Normalize existing SEO tags and make TechArticle JSON-LD match them."""

from __future__ import annotations

import html
import json
from pathlib import Path
import re

from automation.seo_utils import seo_description, seo_title

ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / "automation" / "published-articles.json"
SITE = ROOT / "automation" / "site.json"
SCRIPT_RE = re.compile(r'(<script\s+type=["\']application/ld\+json["\']>)(.*?)(</script>)', re.I | re.S)


def _replace_all_meta(text: str, *, attr: str, key: str, value: str) -> str:
    pattern = re.compile(
        rf'<meta\s+{attr}=(["\']){re.escape(key)}\1\s+content=(["\'])(.*?)\2\s*/?>',
        re.I | re.S,
    )
    tag = f'<meta {attr}="{key}" content="{html.escape(value, quote=True)}">'
    text, count = pattern.subn("", text)
    if "</title>" in text:
        text = text.replace("</title>", "</title>\n  " + tag, 1)
    else:
        text = text.replace("</head>", "  " + tag + "\n</head>", 1)
    return text


def _replace_canonical(text: str, canonical: str) -> str:
    pattern = re.compile(r'<link\s+rel=(["\'])canonical\1\s+href=(["\'])(.*?)\2\s*/?>', re.I | re.S)
    tag = f'<link rel="canonical" href="{html.escape(canonical, quote=True)}">'
    text = pattern.sub("", text)
    return text.replace("</head>", "  " + tag + "\n</head>", 1)


def _update_payload(payload: object, *, description: str, alternative: str) -> bool:
    changed = False
    if isinstance(payload, dict):
        types = payload.get("@type")
        is_article = types == "TechArticle" or (isinstance(types, list) and "TechArticle" in types)
        if is_article:
            if payload.get("description") != description:
                payload["description"] = description
                changed = True
            if payload.get("alternativeHeadline") != alternative:
                payload["alternativeHeadline"] = alternative
                changed = True
        graph = payload.get("@graph")
        if isinstance(graph, list):
            for node in graph:
                if _update_payload(node, description=description, alternative=alternative):
                    changed = True
    elif isinstance(payload, list):
        for node in payload:
            if _update_payload(node, description=description, alternative=alternative):
                changed = True
    return changed


def main() -> None:
    audit = json.loads(AUDIT.read_text(encoding="utf-8"))
    site = json.loads(SITE.read_text(encoding="utf-8"))
    site_name = str(site.get("site_name", "Next Jailbreak"))
    base = str(site.get("base_url", "https://nextjailbreak.com")).rstrip("/")
    repaired = 0
    article_blocks = 0

    for entry in audit.get("entries", []):
        if not isinstance(entry, dict) or not entry.get("href"):
            continue
        href = str(entry["href"]).lstrip("/")
        page = ROOT / href
        if href.endswith("/"):
            page = page / "index.html"
        if not page.exists():
            continue
        name = str(entry.get("name") or entry.get("title") or "Next Jailbreak").strip()
        version = str(entry.get("version") or "").strip()
        category = entry.get("category") if isinstance(entry.get("category"), dict) else {}
        is_jailbreak = str(category.get("id", "")).lower() == "jailbreak" or str(entry.get("entry_type", "")) == "cluster"
        kind_title = "iOS Jailbreak Guide" if is_jailbreak else "iOS Jailbreak Tweak"
        kind_desc = "iOS jailbreak guide" if is_jailbreak else "iOS jailbreak tweak"
        title = seo_title(name, "" if is_jailbreak else version, site_name, kind=kind_title)
        description = seo_description(name, "" if is_jailbreak else version, kind=kind_desc)
        alternative = title.split(" | ", 1)[0]
        canonical = f"{base}/{href}"
        text = page.read_text(encoding="utf-8")
        original = text

        text = re.sub(r"<title>.*?</title>", f"<title>{html.escape(title)}</title>", text, count=1, flags=re.I | re.S)
        text = _replace_all_meta(text, attr="name", key="description", value=description)
        text = _replace_all_meta(text, attr="property", key="og:title", value=title)
        text = _replace_all_meta(text, attr="property", key="og:description", value=description)
        text = _replace_all_meta(text, attr="name", key="twitter:title", value=title)
        text = _replace_all_meta(text, attr="name", key="twitter:description", value=description)
        text = _replace_all_meta(text, attr="name", key="robots", value="index,follow,max-image-preview:large")
        text = _replace_canonical(text, canonical)

        def rewrite(match: re.Match[str]) -> str:
            nonlocal article_blocks
            raw = html.unescape(match.group(2).strip())
            try:
                payload = json.loads(raw)
            except json.JSONDecodeError:
                return match.group(0)
            if _update_payload(payload, description=description, alternative=alternative):
                article_blocks += 1
                after = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
                return match.group(1) + after + match.group(3)
            return match.group(0)

        text = SCRIPT_RE.sub(rewrite, text)
        if text != original:
            page.write_text(text, encoding="utf-8")
            repaired += 1

    print(json.dumps({"pages_normalized": repaired, "techarticle_blocks_repaired": article_blocks}))


if __name__ == "__main__":
    main()
