#!/usr/bin/env python3
"""Roll community comments and the dedicated repo URL across existing and future articles."""

from __future__ import annotations

import json
from pathlib import Path
import re

from automation.community_comments import ensure_community_comments, ensure_repo_nav

ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / "automation" / "published-articles.json"


def patch_future_publishers() -> list[str]:
    changed: list[str] = []
    configs = {
        "automation/publisher.py": ("rendered_article", 'target.write_text(rendered_article, encoding="utf-8")'),
        "automation/ios_repo_news.py": ("rendered", 'target.write_text(rendered, encoding="utf-8")'),
        "automation/dopamine_cluster.py": ("rendered", 'target.write_text(rendered, encoding="utf-8")'),
    }
    for relative, (variable, write_line) in configs.items():
        path = ROOT / relative
        text = path.read_text(encoding="utf-8")
        original = text
        import_line = "from automation.community_comments import ensure_community_comments\n"
        if import_line not in text:
            anchor = "from automation.openai_api import" if "from automation.openai_api import" in text else "from automation.draft_pipeline import"
            text = text.replace(anchor, import_line + anchor, 1)
        guarded = f"{variable} = ensure_community_comments({variable})\n    {write_line}"
        if guarded not in text:
            if write_line not in text:
                raise RuntimeError(f"future publisher write point not found: {relative}")
            text = text.replace(write_line, guarded, 1)
        if text != original:
            path.write_text(text, encoding="utf-8")
            changed.append(relative)
    return changed


def replace_repo_deep_links(text: str) -> str:
    replacements = {
        "sileo://source/https://nextjailbreak.com/": "sileo://source/https://repo.nextjailbreak.com/",
        "source=https://nextjailbreak.com/": "source=https://repo.nextjailbreak.com/",
        "zbra://sources/add/https://nextjailbreak.com/": "zbra://sources/add/https://repo.nextjailbreak.com/",
        "installer://add/repo=https://nextjailbreak.com/": "installer://add/repo=https://repo.nextjailbreak.com/",
        "Repo: nextjailbreak.com": "Repo: repo.nextjailbreak.com",
    }
    for old, new in replacements.items():
        text = text.replace(old, new)
    return text


def patch_existing_articles() -> tuple[int, int]:
    audit = json.loads(AUDIT.read_text(encoding="utf-8"))
    changed = 0
    missing = 0
    seen: set[Path] = set()
    for entry in audit.get("entries", []):
        if not isinstance(entry, dict) or not entry.get("href"):
            continue
        href = str(entry["href"]).lstrip("/")
        page = ROOT / href
        if href.endswith("/"):
            page = page / "index.html"
        if page in seen:
            continue
        seen.add(page)
        if not page.exists():
            missing += 1
            continue
        text = page.read_text(encoding="utf-8")
        updated = ensure_community_comments(replace_repo_deep_links(text))
        if updated != text:
            page.write_text(updated, encoding="utf-8")
            changed += 1
    return changed, missing


def patch_core_navigation() -> list[str]:
    changed: list[str] = []
    candidates = [
        "index.html", "tutorials.html", "tutorials/index.html", "videos.html", "videos/index.html",
        "about.html", "about/index.html", "contact.html", "contact/index.html",
    ]
    for relative in candidates:
        path = ROOT / relative
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        original = text
        text = ensure_repo_nav(text)
        # A few legacy layouts do not use <li> navigation.
        if 'https://repo.nextjailbreak.com/' not in text:
            for marker in ('<a href="/videos/">Videos</a>', '<a href="/videos.html">Videos</a>'):
                if marker in text:
                    text = text.replace(marker, marker + '<a href="https://repo.nextjailbreak.com/">Repo</a>', 1)
                    break
        if text != original:
            path.write_text(text, encoding="utf-8")
            changed.append(relative)
    return changed


def patch_legacy_repo_page() -> bool:
    path = ROOT / "repo" / "index.html"
    if not path.exists():
        return False
    text = path.read_text(encoding="utf-8")
    original = text
    text = text.replace("Repository URL: <strong>https://nextjailbreak.com/</strong>", "Repository URL: <strong>https://repo.nextjailbreak.com/</strong>")
    text = replace_repo_deep_links(text)
    if "installer://add/repo=https://repo.nextjailbreak.com/" not in text:
        marker = '</div>\n      </aside>'
        installer = '          <a class="repo-button" href="installer://add/repo=https://repo.nextjailbreak.com/"><span class="repo-icon">I</span><span><b>Add to Installer 5</b><br><span class="small">Open the source in Installer</span></span><span>›</span></a>\n'
        if marker in text:
            text = text.replace(marker, installer + marker, 1)
    # Point visitors to the dedicated portal while keeping the old page available during migration.
    if "Dedicated repo portal" not in text:
        needle = '<div class="actions"><a class="button primary" href="/tutorial-rootless-basics/">Read compatibility guide</a></div>'
        replacement = '<div class="actions"><a class="button primary" href="https://repo.nextjailbreak.com/">Dedicated repo portal</a><a class="button" href="/tutorial-rootless-basics/">Compatibility guide</a></div>'
        text = text.replace(needle, replacement, 1)
    if text != original:
        path.write_text(text, encoding="utf-8")
        return True
    return False


def main() -> None:
    future = patch_future_publishers()
    existing, missing = patch_existing_articles()
    core = patch_core_navigation()
    legacy_repo = patch_legacy_repo_page()
    result = {
        "existing_articles_updated": existing,
        "missing_article_files": missing,
        "future_publishers_updated": future,
        "core_navigation_updated": core,
        "legacy_repo_page_updated": legacy_repo,
    }
    print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
