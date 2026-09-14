#!/usr/bin/env python3
"""Quarantine three Sep-14 catch-up pages whose published version did not match fresh discovery."""

from __future__ import annotations

from datetime import datetime, timezone
import json
from pathlib import Path
import re
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / "automation" / "published-articles.json"
SITEMAP = ROOT / "sitemap.xml"

BAD = {
    "watusi-3-for-whatsapp-1-3-24-update/": "watusi-3-for-whatsapp-1-3-23-update/",
    "lockglass-1-0-update/": None,
    "replyactions-1-0-3-update/": None,
}


def quarantine_page(href: str, replacement: str | None) -> None:
    page = ROOT / href / "index.html"
    if not page.exists():
        return
    text = page.read_text(encoding="utf-8")
    text = re.sub(
        r'<meta\s+name=["\']robots["\']\s+content=["\'][^"\']*["\']\s*/?>',
        '<meta name="robots" content="noindex,nofollow">',
        text,
        count=1,
        flags=re.I,
    )
    if 'name="robots"' not in text.lower():
        text = text.replace('</head>', '  <meta name="robots" content="noindex,nofollow">\n</head>', 1)
    if replacement:
        canonical = f"https://nextjailbreak.com/{replacement}"
        text = re.sub(
            r'<link\s+rel=["\']canonical["\']\s+href=["\'][^"\']+["\']\s*/?>',
            f'<link rel="canonical" href="{canonical}">',
            text,
            count=1,
            flags=re.I,
        )
    marker = 'NEXTJAILBREAK_STALE_VERSION_NOTICE'
    if marker not in text and '<main' in text.lower():
        notice = (
            '<!-- NEXTJAILBREAK_STALE_VERSION_NOTICE -->\n'
            '<div class="container" style="margin-top:18px;padding:14px 18px;border:1px solid #d9a441;border-radius:14px;background:#fff8e7">'
            '<strong>Archived version notice:</strong> This page was removed from Next Jailbreak listings after a source-version mismatch was detected. '
            'Use the current original-source article or package information instead.'
            '</div>\n'
        )
        text = re.sub(r'(<main[^>]*>)', r'\1\n' + notice, text, count=1, flags=re.I)
    page.write_text(text, encoding="utf-8")


def clean_sitemap() -> None:
    if not SITEMAP.exists():
        return
    tree = ElementTree.parse(SITEMAP)
    root = tree.getroot()
    namespace = "http://www.sitemaps.org/schemas/sitemap/0.9"
    for node in list(root.findall(f"{{{namespace}}}url")):
        loc = node.find(f"{{{namespace}}}loc")
        if loc is None or not loc.text:
            continue
        if any(loc.text.rstrip('/').endswith('/' + href.rstrip('/')) for href in BAD):
            root.remove(node)
    ElementTree.register_namespace('', namespace)
    tree.write(SITEMAP, encoding='utf-8', xml_declaration=True)


def main() -> None:
    data = json.loads(AUDIT.read_text(encoding="utf-8"))
    entries = data.get("entries", [])
    removed = [e for e in entries if isinstance(e, dict) and str(e.get("href", "")) in BAD]
    data["entries"] = [e for e in entries if not (isinstance(e, dict) and str(e.get("href", "")) in BAD)]
    maintenance = data.setdefault("maintenance_events", [])
    existing = {(str(e.get("action")), str(e.get("href"))) for e in maintenance if isinstance(e, dict)}
    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    for entry in removed:
        href = str(entry.get("href"))
        key = ("stale-version-quarantine", href)
        if key not in existing:
            maintenance.append({
                "action": "stale-version-quarantine",
                "at": now,
                "href": href,
                "package": entry.get("package"),
                "published_version": entry.get("version"),
                "reason": "fresh discovery/source version mismatch found during manual audit",
            })
    data["updated_at"] = now
    AUDIT.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    for href, replacement in BAD.items():
        quarantine_page(href, replacement)
    clean_sitemap()
    print(json.dumps({"quarantined": [str(e.get("href")) for e in removed]}, indent=2))


if __name__ == "__main__":
    main()
