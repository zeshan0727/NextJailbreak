#!/usr/bin/env python3
"""Inject Next Jailbreak community comments, canonical brand links and social-preview metadata."""

from __future__ import annotations

import html
import re

COMMENTS_CSS = '<link rel="stylesheet" href="/assets/community-comments.css">'
COMMENTS_JS = '<script src="/assets/community-comments.js" defer></script>'
REPO_LINK = '<li><a href="https://repo.nextjailbreak.com/">Repo</a></li>'
COMMENTS_MARKER = 'data-nj-comments'

COMMENTS_HTML = '''
  <!-- NEXTJAILBREAK_COMMUNITY_COMMENTS_START -->
  <section class="container nj-comments" data-nj-comments data-comments-api="https://comments.nextjailbreak.com" aria-labelledby="community-comments-title">
    <div class="nj-comments-head">
      <div><h2 id="community-comments-title">Community comments</h2><p>Questions, setup notes and experiences from Next Jailbreak readers. Be respectful and do not post personal information.</p></div>
      <span class="nj-comments-count"><strong data-comment-count>0</strong> comments</span>
    </div>
    <form class="nj-comment-form" data-comment-form>
      <label>Your name<input type="text" name="name" minlength="2" maxlength="60" autocomplete="name" required></label>
      <label class="nj-honeypot" aria-hidden="true">Website<input type="text" name="website" tabindex="-1" autocomplete="off"></label>
      <label class="comment-body">Comment<textarea name="body" minlength="2" maxlength="2000" placeholder="Share a useful comment or ask a question…" required></textarea></label>
      <div class="nj-comment-actions"><span class="nj-comment-status" data-comment-status>Loading comments…</span><button type="submit">Post comment</button></div>
    </form>
    <div class="nj-comment-list" data-comment-list></div>
  </section>
  <!-- NEXTJAILBREAK_COMMUNITY_COMMENTS_END -->
'''


def normalize_editorial_links(text: str) -> str:
    """Move only the old primary site hostname to Next Jailbreak; keep files.nextsolution.cc intact."""
    text = re.sub(
        r'https?://(?:www\.)?nextsolution\.cc(?=[:/"\'\s<]|$)',
        'https://nextjailbreak.com',
        text,
        flags=re.I,
    )
    return text


def _meta_content(text: str, attr: str, key: str) -> str:
    pattern = re.compile(
        rf'<meta\s+{attr}=["\']{re.escape(key)}["\']\s+content=["\']([^"\']+)["\'][^>]*>',
        re.I,
    )
    match = pattern.search(text)
    return html.unescape(match.group(1)).strip() if match else ''


def _title(text: str) -> str:
    value = _meta_content(text, 'property', 'og:title') or _meta_content(text, 'name', 'twitter:title')
    if value:
        return value
    match = re.search(r'<title>(.*?)</title>', text, re.I | re.S)
    return html.unescape(re.sub(r'\s+', ' ', match.group(1))).strip() if match else 'Next Jailbreak'


def _insert_head_tag(text: str, tag: str) -> str:
    if '</head>' not in text.lower():
        return text
    return re.sub(r'</head>', f'  {tag}\n</head>', text, count=1, flags=re.I)


def ensure_social_preview(text: str) -> str:
    """Ensure article cards have the metadata X/Twitter and Open Graph crawlers expect."""
    image = _meta_content(text, 'property', 'og:image') or _meta_content(text, 'name', 'twitter:image')
    title = _title(text)
    escaped_title = html.escape(title, quote=True)
    if '<meta name="twitter:site"' not in text.lower():
        text = _insert_head_tag(text, '<meta name="twitter:site" content="@nextjailbreak">')
    if image:
        escaped_image = html.escape(image, quote=True)
        if '<meta property="og:image:secure_url"' not in text.lower():
            text = _insert_head_tag(text, f'<meta property="og:image:secure_url" content="{escaped_image}">')
        if '<meta property="og:image:alt"' not in text.lower():
            text = _insert_head_tag(text, f'<meta property="og:image:alt" content="{escaped_title}">')
        if '<meta name="twitter:image:alt"' not in text.lower():
            text = _insert_head_tag(text, f'<meta name="twitter:image:alt" content="{escaped_title}">')
        if image.lower().split('?', 1)[0].endswith('.png') and '<meta property="og:image:type"' not in text.lower():
            text = _insert_head_tag(text, '<meta property="og:image:type" content="image/png">')
        elif image.lower().split('?', 1)[0].endswith(('.jpg', '.jpeg')) and '<meta property="og:image:type"' not in text.lower():
            text = _insert_head_tag(text, '<meta property="og:image:type" content="image/jpeg">')
    return text


def ensure_repo_nav(text: str) -> str:
    text = re.sub(
        r'<a href="/repo/">Repo</a>',
        '<a href="https://repo.nextjailbreak.com/">Repo</a>',
        text,
        count=1,
        flags=re.I,
    )
    if re.search(r'<a[^>]+href="https://repo\.nextjailbreak\.com/?"[^>]*>\s*Repo\s*</a>', text, re.I):
        return text
    patterns = [
        r'(<li><a href="/videos(?:\.html|/)?"[^>]*>Videos</a></li>)',
        r'(<li><a href="/videos/"[^>]*>Videos</a></li>)',
    ]
    for pattern in patterns:
        updated, count = re.subn(pattern, r'\1' + REPO_LINK, text, count=1, flags=re.I)
        if count:
            return updated
    return text


def ensure_community_comments(text: str) -> str:
    """Return article HTML with canonical brand links, social cards, comments and Repo navigation."""
    if not text or '</html>' not in text.lower():
        return text
    text = normalize_editorial_links(text)
    text = ensure_social_preview(text)
    text = ensure_repo_nav(text)
    if COMMENTS_CSS not in text and '</head>' in text.lower():
        text = re.sub(r'</head>', f'  {COMMENTS_CSS}\n</head>', text, count=1, flags=re.I)
    if COMMENTS_MARKER not in text:
        if '</main>' in text.lower():
            text = re.sub(r'</main>', COMMENTS_HTML + '\n</main>', text, count=1, flags=re.I)
        elif '</article>' in text.lower():
            text = re.sub(r'</article>', '</article>\n' + COMMENTS_HTML, text, count=1, flags=re.I)
        elif '</footer>' in text.lower():
            text = re.sub(r'<footer', COMMENTS_HTML + '\n<footer', text, count=1, flags=re.I)
    if COMMENTS_JS not in text and '</body>' in text.lower():
        text = re.sub(r'</body>', f'  {COMMENTS_JS}\n</body>', text, count=1, flags=re.I)
    return text
