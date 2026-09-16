#!/usr/bin/env python3
"""One-off verified original-source batch for 16 Sep 2026.

This deliberately bypasses discovery/rate scheduling only. It does NOT bypass the
existing writer/verifier quality gate, duplicate checks, source-media rules, SEO
renderer, feed/sitemap generation, or public index synchronization.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
from urllib.parse import urlparse

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
AUDIT_PATH = ROOT / "automation/published-articles.json"

TARGETS = [
    {
        "name": "Rocket for Instagram", "version": "4.18.0", "package_id": "me.alfhaily.rocket",
        "description": "All-in-one tweak for Instagram.",
        "urls": [
            "https://apt.getrocketapp.io/",
            "https://apt.getrocketapp.io/changelogs/4EYOXC",
            "https://apt.getrocketapp.io/Packages",
        ],
    },
    {
        "name": "ShowVolumeControl", "version": "1.0.0", "package_id": "com.ichitaso.showvolume",
        "description": "Always show the volume control in iOS 16 media controls.",
        "urls": [
            "https://cydia.ichitaso.com/depiction/showvolume.html",
            "https://github.com/ichitaso/ShowVolumeControls",
            "https://raw.githubusercontent.com/ichitaso/ShowVolumeControls/main/control",
        ],
        "github": [("ichitaso", "ShowVolumeControls")],
    },
    {
        "name": "YTVideoOverlay", "version": "2.3.8", "package_id": "com.ps.ytvideooverlay",
        "description": "A helper tweak that adds buttons to YouTube's video overlay.",
        "urls": [
            "https://poomsmart.github.io/repo/depictions/ytvideooverlay.html",
            "https://github.com/PoomSmart/YTVideoOverlay",
            "https://raw.githubusercontent.com/PoomSmart/YTVideoOverlay/main/control",
        ],
        "github": [("PoomSmart", "YTVideoOverlay")],
    },
    {
        "name": "NextUp 3", "version": "1.2", "package_id": "com.yves.nextup3",
        "description": "Adds an Up Next row that shows the next track and its artwork in supported now-playing interfaces.",
        "urls": ["https://havoc.app/package/nextup3"],
        "scope_note": (
            "SOURCE-SCOPE NOTE DERIVED FROM THE OFFICIAL HAVOC LISTING: The listing description documents an "
            "Up Next row showing the next track and its artwork. Do not describe a generic or broader control set. "
            "The listing title/feature wording refers to seeing and skipping what is next; keep any skip claim tied "
            "to that exact wording and do not expand it into undocumented controls."
        ),
    },
    {
        "name": "HALO2", "version": "1.0.1", "package_id": "jp.uzra.halo2",
        "description": "Lock Screen media-player customization tweak.",
        "urls": ["https://havoc.app/package/halo2"],
    },
    {
        "name": "Watusi 3", "version": "1.3.24", "package_id": "com.fouadraheb.watusi3",
        "description": "WhatsApp enhancement tweak with privacy, protection, status and customization features.",
        "urls": ["https://tweaks.fouadraheb.com/apps/watusi3"],
    },
    {
        "name": "Apollo Reborn", "version": "3.7.1", "package_id": "apollo-reborn",
        "description": "Community-maintained Apollo for Reddit tweak with API-key support and app enhancements.",
        "urls": [
            "https://github.com/Apollo-Reborn/Apollo-Reborn",
            "https://raw.githubusercontent.com/Apollo-Reborn/Apollo-Reborn/main/CHANGELOG.md",
        ],
        "github": [("Apollo-Reborn", "Apollo-Reborn")],
    },
    {
        "name": "SideInstaller", "version": "1.0.0", "package_id": "sideinstaller",
        "description": "Install SideStore and LiveContainer directly on an iPhone without a PC.",
        "urls": [
            "https://github.com/FrizzleM/SideInstaller",
            "https://github.com/FrizzleM/SideInstaller/releases/tag/v1.0.0",
        ],
        "github": [("FrizzleM", "SideInstaller")],
    },
]


def build_source(target: dict) -> dict:
    material: list[str] = []
    source_urls: list[str] = list(target["urls"])
    for owner, repo in target.get("github", []):
        text, urls = _github_material(owner, repo)
        if text:
            material.append(text)
        source_urls.extend(urls)

    for url in list(dict.fromkeys(source_urls)):
        try:
            text, _ = _source_page_text(url)
        except Exception as exc:
            material.append(f"SOURCE FETCH NOTE for {url}: {type(exc).__name__}")
            continue
        if _words(text) >= 12:
            material.append(f"ORIGINAL SOURCE PAGE {url}:\n{text[:24000]}")

    if target.get("scope_note"):
        material.append(str(target["scope_note"]))
    source_text = "\n\n".join(material)
    if _words(source_text) < 40:
        raise ValueError(f"{target['name']}: original source material is too thin")
    if target["version"].lower() not in source_text.lower():
        raise ValueError(f"{target['name']}: exact version {target['version']} not found in original source material")
    return {
        "name": target["name"],
        "version": target["version"],
        "description": target["description"],
        "package_id": target["package_id"],
        "source_urls": list(dict.fromkeys(source_urls)),
        "source_text": source_text[:65000],
    }


def generate_strict(source: dict):
    errors: list[str] = []
    for attempt in range(1, 4):
        try:
            return generate_article(source, SITE, CONFIG)
        except ValueError as exc:
            errors.append(f"attempt {attempt}: {exc}")
            print(f"QUALITY RETRY {source['name']} {source['version']} attempt {attempt}: {exc}", flush=True)
    raise ValueError(f"{source['name']} {source['version']} failed strict gate after 3 independent drafts: " + " | ".join(errors))


def main() -> int:
    audit = load_audit(AUDIT_PATH)
    entries = list(audit.get("entries", []))
    events = list(audit.get("events", []))
    now = datetime.now(timezone.utc).replace(microsecond=0)
    results: list[dict] = []

    for index, target in enumerate(TARGETS):
        source = build_source(target)
        slug = _slug(f"{source['name']} {source['version']} update")
        target_path = f"{slug}/"
        html_path = ROOT / target_path / "index.html"
        existing = next((e for e in entries if isinstance(e, dict) and e.get("href") == target_path), None)
        if html_path.exists() or existing:
            results.append({"name": source["name"], "version": source["version"], "status": "duplicate", "href": target_path})
            continue

        article, api_meta = generate_strict(source)
        media = acquire_unique_source_visual(
            source_urls=source["source_urls"], slug=slug, repository_root=ROOT
        )
        article_time = now + timedelta(seconds=index)
        rendered = ensure_community_comments(_render_article(article, source, media, SITE, article_time, target_path))
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
            "category": {"id": "system-utilities", "label": "System & Utilities"},
            "source_name": urlparse(source["source_urls"][0]).netloc.removeprefix("www."),
            "source_url": source["source_urls"][0],
            "source_page_url": source["source_urls"][0],
            "selection_pool": "manual-verified-original-source-batch",
            "image": media["image"],
            "media_credit": media["credit"],
            "media_source_url": media["source_url"],
            "source_visual_url": media["image_url"],
            "source_visual_origin": media["origin"],
            "published_at": published_at,
            "modified_at": published_at,
            "quality_target": int(CONFIG.get("quality_target", 9)),
        }
        entries = [e for e in entries if not (isinstance(e, dict) and e.get("href") == target_path)]
        entries.append(entry)
        events.append({
            "published_at": published_at, "action": "create", "package": source["package_id"],
            "version": source["version"], "href": target_path,
            "channel": "manual-verified-original-source-batch", "api": api_meta,
        })
        results.append({
            "name": source["name"], "version": source["version"], "status": "published",
            "href": target_path, "image": media["image"], "media_source_url": media["source_url"]
        })

    entries.sort(key=lambda e: str(e.get("modified_at") or e.get("published_at") or ""), reverse=True)
    updated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    AUDIT_PATH.write_text(json.dumps({
        "schema_version": 1, "updated_at": updated_at, "entries": entries, "events": events
    }, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")
    (ROOT / "feed.xml").write_text(_render_feed(entries, SITE), encoding="utf-8")
    sitemap_path = ROOT / "sitemap.xml"
    sitemap_path.write_text(_update_sitemap(sitemap_path.read_text(encoding="utf-8"), entries, SITE), encoding="utf-8")
    result_path = ROOT / "automation/batch-20260916-result.json"
    result_path.write_text(json.dumps({"updated_at": updated_at, "results": results}, indent=2) + "\n", encoding="utf-8")

    published = sum(1 for item in results if item["status"] == "published")
    print(json.dumps({"published": published, "results": results}, ensure_ascii=False))
    return 0 if len(results) == len(TARGETS) else 2


if __name__ == "__main__":
    raise SystemExit(main())
