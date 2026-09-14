#!/usr/bin/env python3
"""Inject Next Jailbreak community comments and the repo navigation link into article HTML."""

from __future__ import annotations

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


def ensure_repo_nav(text: str) -> str:
    if 'href="https://repo.nextjailbreak.com/"' in text:
        return text
    # Current article templates use an unordered primary navigation list. Insert after Videos.
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
    """Return article HTML with one comments block, required assets, and Repo nav link."""
    if not text or '</html>' not in text.lower():
        return text
    text = ensure_repo_nav(text)
    if COMMENTS_CSS not in text and '</head>' in text.lower():
        text = re.sub(r'</head>', f'  {COMMENTS_CSS}\n</head>', text, count=1, flags=re.I)
    if COMMENTS_MARKER not in text and '</main>' in text.lower():
        text = re.sub(r'</main>', COMMENTS_HTML + '\n</main>', text, count=1, flags=re.I)
    if COMMENTS_JS not in text and '</body>' in text.lower():
        text = re.sub(r'</body>', f'  {COMMENTS_JS}\n</body>', text, count=1, flags=re.I)
    return text
