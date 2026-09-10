#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from pathlib import Path

from automation.publisher import _render_feed, _update_sitemap

ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / "automation" / "published-articles.json"
SITE = ROOT / "automation" / "site.json"
FEED = ROOT / "feed.xml"
SITEMAP = ROOT / "sitemap.xml"
VERSION_RE = re.compile(r"(?<![A-Za-z0-9])v?(\d+(?:\.\d+){1,4}(?:[-.]\d+)?)(?![A-Za-z0-9])", re.I)
ADSENSE_META_RE = re.compile(r'\s*<meta\s+name=["\']google-adsense-account["\'][^>]*>\s*', re.I)
ADSENSE_SCRIPT_RE = re.compile(r'\s*<script\b[^>]*pagead2\.googlesyndication\.com/pagead/js/adsbygoogle\.js[^>]*>\s*</script>\s*', re.I | re.S)
ROBOTS_RE = re.compile(r'<meta\s+name=["\']robots["\]\s+content=["\'][^"\']*["\']\s*/?>', re.I)


def title_versions(title: str) -> set[str]:
    return {m.group(1).lower() for m in VERSION_RE.finditer(title or "")}


def quarantine_page(href: str) -> None:
    rel = str(href or "").strip().lstrip("/")
    if not rel:
        return
    path = ROOT / rel
    if path.is_dir() or rel.endswith("/"):
        path = path / "index.html"
    if not path.exists() or path.suffix.lower() != ".html":
        return
    text = path.read_text(encoding="utf-8")
    if ROBOTS_RE.search(text):
        text = ROBOTS_RE.sub('<meta name="robots" content="noindex,nofollow">', text, count=1)
    elif "</head>" in text:
        text = text.replace("</head>", '  <meta name="robots" content="noindex,nofollow">\n</head>', 1)
    text = ADSENSE_META_RE.sub("\n", text)
    text = ADSENSE_SCRIPT_RE.sub("\n", text)
    path.write_text(text, encoding="utf-8")


def enforce_manifest_consistency() -> int:
    data = json.loads(AUDIT.read_text(encoding="utf-8"))
    entries = data.get("entries") or []
    kept = []
    quarantined = []
    for entry in entries:
        if not isinstance(entry, dict):
            kept.append(entry)
            continue
        version = str(entry.get("version") or "").strip().lower()
        versions = title_versions(str(entry.get("title") or ""))
        # Fail closed only when the title itself makes a concrete dotted-version claim
        # and that claim does not include the manifest/source version.
        if version and versions and version not in versions:
            quarantine_page(str(entry.get("href") or ""))
            quarantined.append({"href": entry.get("href"), "version": version, "title_versions": sorted(versions)})
            continue
        kept.append(entry)
    if quarantined:
        data["entries"] = kept
        data.setdefault("maintenance_events", []).append({"action": "integrity-quarantine", "items": quarantined})
        AUDIT.write_text(json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({"quarantined": quarantined}, ensure_ascii=False))
    return len(quarantined)


def repair_rocket_415() -> bool:
    """One-time repair for the known Rocket 4.15.0 article published under 3.8.38 metadata."""
    old_href = "rocket-for-instagram-3-8-38-update/"
    new_href = "rocket-for-instagram-4-15-0-update/"
    data = json.loads(AUDIT.read_text(encoding="utf-8"))
    entry = next((e for e in data.get("entries", []) if isinstance(e, dict) and e.get("href") == old_href), None)
    old_path = ROOT / old_href / "index.html"
    new_path = ROOT / new_href / "index.html"
    if entry is None or not old_path.exists():
        return False

    source = old_path.read_text(encoding="utf-8")
    source = source.replace(old_href, new_href)
    new_path.parent.mkdir(parents=True, exist_ok=True)
    new_path.write_text(source, encoding="utf-8")

    entry["href"] = new_href
    entry["version"] = "4.15.0"
    data.setdefault("maintenance_events", []).append({
        "action": "repair-version-metadata",
        "package": entry.get("package"),
        "from_href": old_href,
        "to_href": new_href,
        "from_version": "3.8.38",
        "to_version": "4.15.0",
        "reason": "official depiction/headline used 4.15.0 while manifest and slug used older package stanza version",
    })
    AUDIT.write_text(json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")

    title = "Rocket for Instagram article moved | Next Jailbreak"
    canonical = "https://nextjailbreak.com/" + new_href
    old = f'''<!DOCTYPE html>\n<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{title}</title><meta name="robots" content="noindex,nofollow"><link rel="canonical" href="{canonical}"><link rel="stylesheet" href="/assets/site.css"></head><body><main class="container article-main"><article><header class="article-hero"><h1>Rocket for Instagram 4.15.0</h1><p class="article-summary">This article URL was corrected because the previous path used conflicting package-version metadata.</p><p><a class="button button-primary" href="/{new_href}">Open the corrected article</a></p></header></article></main></body></html>\n'''
    old_path.write_text(old, encoding="utf-8")
    return True


def rebuild_feed_and_sitemap() -> None:
    data = json.loads(AUDIT.read_text(encoding="utf-8"))
    site = json.loads(SITE.read_text(encoding="utf-8"))
    entries = data.get("entries") or []
    FEED.write_text(_render_feed(entries, site), encoding="utf-8")
    SITEMAP.write_text(_update_sitemap(SITEMAP.read_text(encoding="utf-8"), entries, site), encoding="utf-8")


def main() -> None:
    repaired = repair_rocket_415()
    quarantined = enforce_manifest_consistency()
    rebuild_feed_and_sitemap()
    print(f"editorial integrity: repaired_rocket_415={repaired} quarantined={quarantined}")


if __name__ == "__main__":
    main()
