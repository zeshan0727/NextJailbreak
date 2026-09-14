#!/usr/bin/env python3
"""Roll community comments and the dedicated repo URL across existing and future articles."""

from __future__ import annotations

import json
from pathlib import Path

from automation.community_comments import ensure_community_comments, ensure_repo_nav

ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / "automation" / "published-articles.json"

NON_ARTICLE_ROOTS = {
    ".github", "assets", "automation", "cloudflare", "debfiles", "depictions", "repo-site",
    "AITradingDemo", "DailyLedger", "DailyTweaks", "Diagnostics", "ModuleGlassPreview",
    "NextLedger.xcodeproj", "NextWebsiteApp",
}
NON_ARTICLE_NAMES = {
    "index.html", "tutorials.html", "videos.html", "about.html", "contact.html", "privacy.html",
    "terms.html", "repo.html", "applications.html", "404.html",
}
NON_ARTICLE_DIRS = {"tutorials", "videos", "about", "contact", "privacy", "terms", "repo", "applications"}


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
        "sileo://source/https://nextjailbreak.com": "sileo://source/https://repo.nextjailbreak.com/",
        "source=https://nextjailbreak.com/": "source=https://repo.nextjailbreak.com/",
        "source=https://nextjailbreak.com": "source=https://repo.nextjailbreak.com/",
        "zbra://sources/add/https://nextjailbreak.com/": "zbra://sources/add/https://repo.nextjailbreak.com/",
        "installer://add/repo=https://nextjailbreak.com/": "installer://add/repo=https://repo.nextjailbreak.com/",
        "Repo: nextjailbreak.com": "Repo: repo.nextjailbreak.com",
        "Add https://nextjailbreak.com/ to Sileo": "Add https://repo.nextjailbreak.com/ to Sileo",
        "add https://nextjailbreak.com/ to Sileo": "add https://repo.nextjailbreak.com/ to Sileo",
        "add https://nextjailbreak.com as a source": "add https://repo.nextjailbreak.com/ as a source",
        "Add https://nextjailbreak.com as a source": "Add https://repo.nextjailbreak.com/ as a source",
        "source served by nextjailbreak.com": "source served by repo.nextjailbreak.com",
        "Open nextjailbreak.com": "Open repo.nextjailbreak.com",
        'href="https://nextjailbreak.com">Repo: repo.nextjailbreak.com</a>': 'href="https://repo.nextjailbreak.com/">Repo: repo.nextjailbreak.com</a>',
    }
    for old, new in replacements.items():
        text = text.replace(old, new)
    return text


def resolve_audit_pages() -> tuple[set[Path], int]:
    audit = json.loads(AUDIT.read_text(encoding="utf-8"))
    pages: set[Path] = set()
    missing = 0
    for entry in audit.get("entries", []):
        if not isinstance(entry, dict) or not entry.get("href"):
            continue
        href = str(entry["href"]).lstrip("/")
        page = ROOT / href
        if href.endswith("/"):
            page = page / "index.html"
        if page.exists():
            pages.add(page)
        else:
            missing += 1
    return pages, missing


def looks_like_article(path: Path) -> bool:
    relative = path.relative_to(ROOT)
    if not relative.parts:
        return False
    if relative.parts[0] in NON_ARTICLE_ROOTS:
        return False
    if len(relative.parts) == 1 and relative.name in NON_ARTICLE_NAMES:
        return False
    if relative.parts[0] in NON_ARTICLE_DIRS:
        return False
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return False
    lower = text.lower()
    if "<article" not in lower or "</html>" not in lower:
        return False
    # Exclude listing/catalog pages that use article cards rather than one editorial article.
    if "latest articles" in lower and "news-feed" in lower:
        return False
    return True


def all_article_pages() -> tuple[set[Path], int]:
    pages, missing = resolve_audit_pages()
    for page in ROOT.rglob("*.html"):
        if looks_like_article(page):
            pages.add(page)
    return pages, missing


def patch_existing_articles() -> tuple[int, int, int]:
    pages, missing = all_article_pages()
    changed = 0
    for page in sorted(pages):
        text = page.read_text(encoding="utf-8")
        updated = ensure_community_comments(replace_repo_deep_links(text))
        if updated != text:
            page.write_text(updated, encoding="utf-8")
            changed += 1
    return changed, missing, len(pages)


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
    existing, missing, total = patch_existing_articles()
    core = patch_core_navigation()
    legacy_repo = patch_legacy_repo_page()
    result = {
        "article_pages_detected": total,
        "existing_articles_updated": existing,
        "missing_audit_article_files": missing,
        "future_publishers_updated": future,
        "core_navigation_updated": core,
        "legacy_repo_page_updated": legacy_repo,
    }
    print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
