#!/usr/bin/env python3
from __future__ import annotations

import html
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / "automation" / "published-articles.json"
HOME = ROOT / "index.html"
TUTORIALS = [ROOT / "tutorials.html", ROOT / "tutorials" / "index.html"]
HOME_START = "<!-- AUTO_ARTICLES_HOME_START -->"
HOME_END = "<!-- AUTO_ARTICLES_HOME_END -->"
TWEAK_START = "<!-- AUTO_ARTICLES_TUTORIALS_START -->"
TWEAK_END = "<!-- AUTO_ARTICLES_TUTORIALS_END -->"
JAIL_START = "<!-- AUTO_ARTICLES_JAILBREAK_START -->"
JAIL_END = "<!-- AUTO_ARTICLES_JAILBREAK_END -->"


def ordered(entries):
    return sorted(
        [e for e in entries if isinstance(e, dict) and e.get("href")],
        key=lambda e: str(e.get("modified_at") or e.get("published_at") or ""),
        reverse=True,
    )


def newest_package_entries(entries):
    """Keep only the newest public index card for each package/article identity."""
    result = []
    seen = set()
    for e in entries:
        package = str(e.get("package") or "").strip().lower()
        name = str(e.get("name") or e.get("title") or "").strip().lower()
        key = ("package", package) if package else ("name", name)
        if key in seen:
            continue
        seen.add(key)
        result.append(e)
    return result


def is_jailbreak(e):
    c = e.get("category") or {}
    return isinstance(c, dict) and (
        str(c.get("id") or "").lower() == "jailbreak"
        or str(c.get("label") or "").lower() == "jailbreak"
    )


def href(v):
    value = str(v or "").strip()
    if value.startswith(("/", "http://", "https://", "#")):
        return value
    value = value.lstrip("/")
    # The audit retains historical .html file paths; link to their canonical
    # directory routes so readers and search engines do not encounter duplicates.
    if value.endswith(".html"):
        value = value[:-5].rstrip("/") + "/"
    return "/" + value


def image(v):
    value = str(v or "").strip()
    if not value:
        return "/assets/brand/next-jailbreak-social-card.png"
    if value.startswith(("/", "http://", "https://")):
        return value
    return "/" + value.lstrip("/")


def clean_description(value):
    text = " ".join(str(value or "").split()).strip()
    fallback = "Read the full article for verified details, compatibility notes and source information."
    if not text:
        return fallback

    # Never expose visibly chopped generated metadata such as "release-" or "call-rec".
    chopped_hyphen_token = re.search(r"\b[A-Za-z][A-Za-z0-9]{2,}-[A-Za-z]{1,4}$", text)
    if text.endswith(("-", "–", "—")) or chopped_hyphen_token:
        last_sentence = max(text.rfind(". "), text.rfind("! "), text.rfind("? "))
        if last_sentence >= 0:
            text = text[: last_sentence + 1].strip()
        else:
            # Prefer dropping the final list fragment rather than publishing a guessed word.
            last_break = max(text.rfind(", "), text.rfind("; "))
            if last_break >= max(40, len(text) // 2):
                text = text[:last_break].rstrip(" ,;:-–—").strip()
            else:
                text = text.rsplit(" ", 1)[0].rstrip("-–—,;:").strip()
            if text and text[-1] not in ".!?":
                text += "."

    # Metadata cards should end as complete sentences. Preserve the text; only add punctuation.
    if text and text[-1] not in ".!?":
        text += "."
    return text or fallback


def normalize_manifest_descriptions(data):
    changed = False
    for e in data.get("entries") or []:
        if not isinstance(e, dict) or "description" not in e:
            continue
        cleaned = clean_description(e.get("description"))
        if cleaned != e.get("description"):
            e["description"] = cleaned
            changed = True
    return changed


def card(e, indent="          "):
    esc = lambda v: html.escape(str(v or ""), quote=True)
    c = e.get("category") or {}
    label = c.get("label") if isinstance(c, dict) else "Tweak"
    title = e.get("title") or e.get("name") or "Next Jailbreak article"
    description = clean_description(e.get("description"))
    source = e.get("source_name") or "Next Jailbreak"
    return "\n".join([
        f'{indent}<article class="content-card has-visual">',
        f'{indent}  <div class="card-meta"><span class="tag">{esc(label or "Tweak")}</span><span class="tag">{esc(source)}</span></div>',
        f'{indent}  <a class="card-media" href="{esc(href(e.get("href")))}" aria-label="Open {esc(title)}"><img src="{esc(image(e.get("image")))}" alt="{esc(title)}" width="1600" height="900" loading="lazy"></a>',
        f'{indent}  <h3>{esc(title)}</h3>',
        f'{indent}  <p>{esc(description)}</p>',
        f'{indent}  <a class="card-link" href="{esc(href(e.get("href")))}">Read article →</a>',
        f'{indent}</article>',
    ])


def replace(text, start, end, body):
    if text.count(start) != 1 or text.count(end) != 1:
        raise RuntimeError(f"expected exactly one marker pair: {start} / {end}")
    before, tail = text.split(start, 1)
    _, after = tail.split(end, 1)
    return before + start + "\n" + body.rstrip() + "\n          " + end + after


def dedupe_blogposting_jsonld(text):
    """Remove duplicate BlogPosting URLs from homepage Blog JSON-LD."""
    pattern = re.compile(r'(<script\s+type="application/ld\+json">\s*)(\{.*?\})(\s*</script>)', re.S)

    def rewrite(match):
        try:
            payload = json.loads(match.group(2))
        except json.JSONDecodeError:
            return match.group(0)
        if payload.get("@type") != "Blog" or not isinstance(payload.get("blogPost"), list):
            return match.group(0)
        seen = set()
        posts = []
        for post in payload["blogPost"]:
            if not isinstance(post, dict):
                continue
            key = str(post.get("url") or post.get("headline") or "").strip().lower()
            if not key or key in seen:
                continue
            seen.add(key)
            posts.append(post)
        payload["blogPost"] = posts
        rendered = json.dumps(payload, ensure_ascii=False, indent=2)
        rendered = "\n".join("  " + line for line in rendered.splitlines())
        return match.group(1) + rendered.lstrip() + match.group(3)

    return pattern.sub(rewrite, text)



def render_article_archive(entries):
    """Build a lightweight crawlable archive without overcrowding the homepage."""
    rows = []
    seen = set()
    for entry in entries:
        link = href(entry.get("href"))
        if link in seen:
            continue
        seen.add(link)
        title = esc(entry.get("title") or entry.get("name") or "Read article")
        summary = esc(clean_description(entry.get("description")))
        date_text = str(entry.get("published_at") or entry.get("published") or entry.get("modified_at") or "")
        date = date_text[:10] if re.match(r"^\d{4}-\d\d-\d\d", date_text) else ""
        category = entry.get("category") or {}
        label = esc(category.get("label") or "Jailbreak article") if isinstance(category, dict) else "Jailbreak article"
        rows.append(
            '<li class="archive-item" data-archive-entry>'
            f'<a href="{esc(link)}">{title}</a>'
            f'<p><span>{label}</span>' + (f' · <time datetime="{date}">{date}</time>' if date else "") + '</p>'
            f'<p>{summary}</p></li>'
        )

    body = "\n".join(rows)
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
  <title>All Jailbreak Articles, Tweaks &amp; Guides | Next Jailbreak</title>
  <meta name="description" content="Browse verified-source jailbreak news, iOS tutorials, TrollStore and RootHide guides, Cydia tweaks, and technical comparisons from Next Jailbreak.">
  <meta name="robots" content="index,follow,max-image-preview:large">
  <link rel="canonical" href="https://nextjailbreak.com/articles/">
  <link rel="stylesheet" href="/assets/site.css">
  <link rel="icon" type="image/svg+xml" href="/assets/brand/next-jailbreak-mark.svg">
  <style>
    .archive-shell{{max-width:900px;margin:2.5rem auto;padding:0 1.2rem}}
    .archive-intro{{max-width:65ch;margin-bottom:1.5rem}}
    .archive-search{{display:block;width:100%;box-sizing:border-box;padding:.85rem 1rem;border:1px solid #8a969e;border-radius:.65rem;background:transparent;color:inherit;font:inherit;margin:1rem 0 1.8rem}}
    .archive-list{{list-style:none;padding:0;margin:0}}
    .archive-item{{padding:1rem 0;border-bottom:1px solid #adb5bd55}}
    .archive-item a{{font-size:1.07rem;font-weight:700}}
    .archive-item p{{margin:.3rem 0;line-height:1.55}}
    .archive-item p:nth-child(2){{font-size:.88rem;opacity:.75}}
    .archive-empty{{padding:1rem 0}}
  </style>
</head>
<body>
<header class="site-header"><div class="nav-shell">
  <a class="brand" href="/" aria-label="Next Jailbreak home"><img class="brand-logo" src="/assets/brand/next-jailbreak-mark.svg" alt="" width="52" height="52"><span class="brand-name"><strong>Next</strong> Jailbreak</span></a>
  <nav aria-label="Primary navigation"><ul class="nav-links"><li><a href="/">Blog</a></li><li><a href="/tutorials/">Guides</a></li><li><a href="/videos/">Videos</a></li><li><a href="/articles/" aria-current="page">All articles</a></li></ul></nav>
</div></header>
<main class="archive-shell"><h1>All Jailbreak Articles &amp; Guides</h1>
<p class="archive-intro">Browse our editorial archive of source-backed release coverage, compatibility explainers, iOS jailbreak guides and tweak comparisons. Newest entries appear first.</p>
<label for="archive-search">Filter articles by title, topic or version</label>
<input class="archive-search" id="archive-search" type="search" placeholder="Search article titles and descriptions…" autocomplete="off">
<p id="archive-count" aria-live="polite">{len(rows)} articles</p>
<ul class="archive-list" id="archive-list">
{body}
</ul><p class="archive-empty" id="archive-empty" hidden>No articles match your search.</p>
</main>
<footer class="site-footer"><div class="container"><p>Next Jailbreak · <a href="/">Home</a> · <a href="/feed.xml">RSS feed</a></p></div></footer>
<script>
  (() => {{
    const input = document.getElementById('archive-search');
    const items = Array.from(document.querySelectorAll('[data-archive-entry]'));
    const count = document.getElementById('archive-count');
    const empty = document.getElementById('archive-empty');
    input.addEventListener('input', () => {{
      const q = input.value.trim().toLocaleLowerCase();
      let shown = 0;
      for (const item of items) {{
        item.hidden = !item.textContent.toLocaleLowerCase().includes(q);
        if (!item.hidden) shown++;
      }}
      count.textContent = shown + ' articles';
      empty.hidden = shown !== 0;
    }});
  }})();
</script>
</body></html>
"""



def ensure_archive_navigation(text):
    """Ensure the full archive is reachable through a normal, crawlable link."""
    if 'href="/articles/"' in text:
        return text
    needle = '<li><a href="/videos/">Videos</a></li>'
    if needle not in text:
        raise RuntimeError("Main navigation has no Videos link anchor")
    return text.replace(needle, needle + '\n          <li><a href="/articles/">All articles</a></li>', 1)


def main():
    data = json.loads(AUDIT.read_text(encoding="utf-8"))
    manifest_changed = normalize_manifest_descriptions(data)
    if manifest_changed:
        AUDIT.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    all_entries = ordered(data.get("entries") or [])
    entries = newest_package_entries(all_entries)
    if not entries:
        raise RuntimeError("published article manifest is empty")

    home_text = HOME.read_text(encoding="utf-8")
    home_text = replace(home_text, HOME_START, HOME_END, "\n".join(card(e) for e in entries[:5]))
    home_text = ensure_archive_navigation(dedupe_blogposting_jsonld(home_text))
    HOME.write_text(home_text, encoding="utf-8")

    tweaks = [e for e in entries if not is_jailbreak(e)]
    jailbreaks = [e for e in entries if is_jailbreak(e)]
    for path in TUTORIALS:
        text = path.read_text(encoding="utf-8")
        text = replace(text, TWEAK_START, TWEAK_END, "\n".join(card(e) for e in tweaks[:60]))
        if JAIL_START in text and JAIL_END in text:
            text = replace(text, JAIL_START, JAIL_END, "\n".join(card(e) for e in jailbreaks[:60]))
        path.write_text(ensure_archive_navigation(text), encoding="utf-8")

    archive = ROOT / "articles" / "index.html"
    archive.parent.mkdir(parents=True, exist_ok=True)
    archive.write_text(render_article_archive(all_entries), encoding="utf-8")

    print(f"Synchronized {len(entries)} unique published entries and {len(all_entries)} archive records")


if __name__ == "__main__":
    main()
