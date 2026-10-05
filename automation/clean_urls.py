#!/usr/bin/env python3
"""Generate clean GitHub Pages routes from root HTML files.

The repository keeps root ``*.html`` files as legacy publisher targets, while
public URLs are served from ``/<slug>/index.html``. This script is idempotent
and also rewrites site navigation, canonical URLs, feed/sitemap URLs, and
social preview metadata to GitHub-Pages-safe values.
"""

from __future__ import annotations

import html
from pathlib import Path
import re
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
SITE = "https://nextjailbreak.com"
SOCIAL_IMAGE = f"{SITE}/assets/brand/next-jailbreak-social-card-whatsapp.jpg"
SOCIAL_IMAGE_WIDTH = "1200"
SOCIAL_IMAGE_HEIGHT = "630"

ATTR_RE = re.compile(
    r"(?P<prefix>\b(?:href|src|poster|action)\s*=\s*)(?P<quote>[\"'])(?P<url>.*?)(?P=quote)",
    re.IGNORECASE,
)
META_IMAGE_RE = re.compile(
    r"(?P<prefix><meta\s+[^>]*(?:property|name)=[\"'](?:og:image|twitter:image)[\"'][^>]*content=[\"'])(?P<url>[^\"']+)(?P<suffix>[\"'][^>]*>)",
    re.IGNORECASE,
)
META_IMAGE_RE_REVERSED = re.compile(
    r"(?P<prefix><meta\s+[^>]*content=[\"'])(?P<url>[^\"']+)(?P<middle>[\"'][^>]*(?:property|name)=[\"'](?:og:image|twitter:image)[\"'][^>]*>)",
    re.IGNORECASE,
)
REDIRECT_MARKER = "data-clean-url-redirect"
REDIRECT_SCRIPT = """  <script data-clean-url-redirect>\n    (function () {\n      var path = window.location.pathname;\n      if (/\\.html$/i.test(path) && path.toLowerCase() !== '/index.html') {\n        window.location.replace(path.slice(0, -5) + '/' + window.location.search + window.location.hash);\n      }\n    }());\n  </script>\n"""


def page_names() -> set[str]:
    return {
        path.name
        for path in ROOT.glob("*.html")
        if path.name.lower() not in {"index.html", "404.html"}
    }


def clean_path(filename: str) -> str:
    return f"/{filename[:-5]}/"


def _assemble(path: str, query: str, fragment: str) -> str:
    value = path
    if query:
        value += "?" + query
    if fragment:
        value += "#" + fragment
    return value


def rewrite_url(value: str, pages: set[str]) -> str:
    raw = value.strip()
    if not raw or raw.startswith("#") or raw.startswith("//"):
        return value
    if re.match(r"^[A-Za-z][A-Za-z0-9+.-]*:", raw):
        parsed = urlsplit(raw)
        if parsed.scheme not in {"http", "https"} or parsed.netloc.lower() not in {
            "nextjailbreak.com",
            "www.nextjailbreak.com",
        }:
            return value
        local = parsed.path.lstrip("/")
        if local == "index.html":
            path = "/"
        elif local in pages:
            path = clean_path(local)
        else:
            return value
        return f"{SITE}{_assemble(path, parsed.query, parsed.fragment)}"

    parsed = urlsplit(raw)
    local = parsed.path
    normalized = local.lstrip("/")
    while normalized.startswith("./"):
        normalized = normalized[2:]

    if normalized in {"", "."}:
        path = "/"
    elif normalized == "index.html":
        path = "/"
    elif normalized in pages:
        path = clean_path(normalized)
    elif local.startswith("/"):
        path = local
    else:
        # Root HTML files historically resolve relative assets from /. Their
        # clean copies live one directory deeper, so make those references
        # root-absolute to preserve the existing site layout and assets.
        path = "/" + normalized
    return _assemble(path, parsed.query, parsed.fragment)


def rewrite_attributes(text: str, pages: set[str]) -> str:
    def repl(match: re.Match[str]) -> str:
        url = rewrite_url(match.group("url"), pages)
        return f"{match.group('prefix')}{match.group('quote')}{url}{match.group('quote')}"

    return ATTR_RE.sub(repl, text)


def rewrite_absolute_page_urls(text: str, pages: set[str]) -> str:
    for filename in sorted(pages, key=len, reverse=True):
        slug = filename[:-5]
        text = text.replace(f"https://nextjailbreak.com/{filename}", f"https://nextjailbreak.com/{slug}/")
        text = text.replace(f"https://www.nextjailbreak.com/{filename}", f"https://nextjailbreak.com/{slug}/")
        text = text.replace(f"http://nextjailbreak.com/{filename}", f"https://nextjailbreak.com/{slug}/")
        text = text.replace(f"http://www.nextjailbreak.com/{filename}", f"https://nextjailbreak.com/{slug}/")
    return text


def stabilize_social_images(text: str) -> str:
    """Preserve each page's own topic image instead of forcing the site card."""
    return text

def _meta_value(text: str, *, attr: str, key: str) -> str | None:
    pattern = re.compile(
        rf'<meta\s+[^>]*{attr}=["\']{re.escape(key)}["\'][^>]*content=["\'](?P<value>[^"\']*)["\'][^>]*>',
        re.IGNORECASE,
    )
    match = pattern.search(text)
    if match:
        return html.unescape(match.group("value")).strip()
    reversed_pattern = re.compile(
        rf'<meta\s+[^>]*content=["\'](?P<value>[^"\']*)["\'][^>]*{attr}=["\']{re.escape(key)}["\'][^>]*>',
        re.IGNORECASE,
    )
    match = reversed_pattern.search(text)
    return html.unescape(match.group("value")).strip() if match else None


def _canonical_value(text: str) -> str | None:
    pattern = re.compile(
        r'<link\s+[^>]*rel=["\']canonical["\'][^>]*href=["\'](?P<value>[^"\']+)["\'][^>]*>',
        re.IGNORECASE,
    )
    match = pattern.search(text)
    if match:
        return html.unescape(match.group("value")).strip()
    reversed_pattern = re.compile(
        r'<link\s+[^>]*href=["\'](?P<value>[^"\']+)["\'][^>]*rel=["\']canonical["\'][^>]*>',
        re.IGNORECASE,
    )
    match = reversed_pattern.search(text)
    return html.unescape(match.group("value")).strip() if match else None


def _title_value(text: str) -> str | None:
    match = re.search(r"<title>(?P<value>.*?)</title>", text, re.IGNORECASE | re.DOTALL)
    if not match:
        return None
    return html.unescape(re.sub(r"\s+", " ", match.group("value"))).strip()


def _upsert_meta(text: str, *, attr: str, key: str, content: str) -> str:
    escaped = html.escape(content, quote=True)
    replacement = f'<meta {attr}="{key}" content="{escaped}">'
    pattern = re.compile(
        rf'<meta\s+[^>]*{attr}=["\']{re.escape(key)}["\'][^>]*>',
        re.IGNORECASE,
    )
    if pattern.search(text):
        return pattern.sub(replacement, text, count=1)
    if "</head>" in text:
        return text.replace("</head>", f"  {replacement}\n</head>", 1)
    return text


def _absolute_preview_url(value: str) -> str | None:
    value = html.unescape(value).strip()
    if not value:
        return None
    if value.startswith("https://") or value.startswith("http://"):
        return value
    if value.startswith("//"):
        return "https:" + value
    if value.startswith("/"):
        return SITE + value
    return SITE + "/" + value.lstrip("/")


def _local_preview_path(url: str) -> Path | None:
    """Resolve only first-party preview assets that exist in this repository."""
    value = _absolute_preview_url(url)
    if not value:
        return None
    parsed = urlsplit(value)
    if parsed.scheme not in {"http", "https"}:
        return None
    if parsed.netloc.lower() not in {"nextjailbreak.com", "www.nextjailbreak.com"}:
        return None
    if not parsed.path.startswith("/assets/"):
        return None
    candidate = (ROOT / parsed.path.lstrip("/")).resolve()
    root = ROOT.resolve()
    if candidate != root and root not in candidate.parents:
        return None
    return candidate if candidate.is_file() else None


def _preview_dimensions(path: Path) -> tuple[int, int] | None:
    try:
        from PIL import Image

        with Image.open(path) as image:
            return int(image.width), int(image.height)
    except Exception:
        return None


def _social_ready_preview(url: str) -> bool:
    """Use topic artwork only when it is crawler-friendly; otherwise use the branded card."""
    path = _local_preview_path(url)
    if not path:
        return False
    try:
        # WhatsApp has historically been sensitive to large preview assets.
        if path.stat().st_size > 240 * 1024:
            return False
    except OSError:
        return False
    dims = _preview_dimensions(path)
    if not dims:
        return False
    width, height = dims
    if width < 600 or height < 315:
        return False
    ratio = width / max(height, 1)
    return 1.20 <= ratio <= 2.20


def _article_preview_image(text: str) -> str:
    candidates: list[str] = []

    existing = _meta_value(text, attr="property", key="og:image")
    if existing:
        candidates.append(existing)

    for script in re.finditer(
        r'<script[^>]*type=["\']application/ld\+json["\'][^>]*>(?P<body>.*?)</script>',
        text,
        re.IGNORECASE | re.DOTALL,
    ):
        body = html.unescape(script.group("body"))
        image = re.search(
            r'"image"\s*:\s*(?:"(?P<single>[^"\\]+)"|\[\s*"(?P<array>[^"\\]+)")',
            body,
            re.IGNORECASE,
        )
        if image:
            candidates.append(image.group("single") or image.group("array"))

    figure = re.search(
        r'<figure[^>]*class=["\'][^"\']*(?:article-visual|authentic-media)[^"\']*["\'][^>]*>.*?<img[^>]*src=["\'](?P<src>[^"\']+)["\']',
        text,
        re.IGNORECASE | re.DOTALL,
    )
    if figure:
        candidates.append(figure.group("src"))

    article_img = re.search(
        r'<article\b[^>]*>.*?<img[^>]*src=["\'](?P<src>[^"\']+)["\']',
        text,
        re.IGNORECASE | re.DOTALL,
    )
    if article_img:
        candidates.append(article_img.group("src"))

    for candidate in candidates:
        resolved = _absolute_preview_url(candidate)
        if resolved and resolved != SOCIAL_IMAGE and _social_ready_preview(resolved):
            return resolved

    return SOCIAL_IMAGE


def _remove_meta(text: str, *, attr: str, key: str) -> str:
    pattern = re.compile(
        rf'\s*<meta\s+[^>]*{attr}=["\']{re.escape(key)}["\'][^>]*>\s*',
        re.IGNORECASE,
    )
    return pattern.sub("\n", text)


def ensure_social_preview_meta(text: str) -> str:
    title = _title_value(text) or "Next Jailbreak | Jailbreaks, Tweaks, Apps & Guides"
    description = _meta_value(text, attr="name", key="description") or (
        "Next Jailbreak covers jailbreak news, Cydia and Sileo tweaks, useful apps, tutorials and troubleshooting."
    )
    canonical = _canonical_value(text) or SITE + "/"
    is_homepage = canonical.rstrip("/") == SITE
    page_type = "website" if is_homepage else ("article" if "<article" in text.lower() else "website")
    social_image = _article_preview_image(text) if page_type == "article" else SOCIAL_IMAGE
    image_alt = title if page_type == "article" else "Next Jailbreak — jailbreaks, tweaks, apps and guides"

    values = (
        ("property", "og:type", page_type),
        ("property", "og:site_name", "Next Jailbreak"),
        ("property", "og:url", canonical),
        ("property", "og:title", title),
        ("property", "og:description", description),
        ("property", "og:image", social_image),
        ("property", "og:image:secure_url", social_image),
        ("property", "og:image:alt", image_alt),
        ("name", "twitter:card", "summary_large_image"),
        ("name", "twitter:site", "@nextjailbreak"),
        ("name", "twitter:title", title),
        ("name", "twitter:description", description),
        ("name", "twitter:image", social_image),
        ("name", "twitter:image:alt", image_alt),
    )
    for attr, key, value in values:
        text = _upsert_meta(text, attr=attr, key=key, content=value)

    preview_path = _local_preview_path(social_image)
    preview_dims = _preview_dimensions(preview_path) if preview_path else None
    suffix = preview_path.suffix.lower() if preview_path else ""
    mime = "image/jpeg" if suffix in {".jpg", ".jpeg"} else ("image/png" if suffix == ".png" else None)
    if mime:
        text = _upsert_meta(text, attr="property", key="og:image:type", content=mime)
    else:
        text = _remove_meta(text, attr="property", key="og:image:type")
    if preview_dims:
        text = _upsert_meta(text, attr="property", key="og:image:width", content=str(preview_dims[0]))
        text = _upsert_meta(text, attr="property", key="og:image:height", content=str(preview_dims[1]))
    else:
        text = _remove_meta(text, attr="property", key="og:image:width")
        text = _remove_meta(text, attr="property", key="og:image:height")
    return text

def ensure_legacy_redirect(text: str) -> str:
    if REDIRECT_MARKER in text or "</head>" not in text:
        return text
    return text.replace("</head>", REDIRECT_SCRIPT + "</head>", 1)


def normalize_html(text: str, pages: set[str], *, legacy_redirect: bool) -> str:
    text = rewrite_attributes(text, pages)
    text = rewrite_absolute_page_urls(text, pages)
    text = stabilize_social_images(text)
    text = ensure_social_preview_meta(text)
    if legacy_redirect:
        text = ensure_legacy_redirect(text)
    return text


def update_discovery_file(path: Path, pages: set[str]) -> None:
    if not path.exists():
        return
    old = path.read_text(encoding="utf-8")
    new = rewrite_absolute_page_urls(old, pages)
    if new != old:
        path.write_text(new, encoding="utf-8")


def main() -> int:
    pages = page_names()
    if not pages:
        raise SystemExit("no root HTML pages found")

    # Keep the homepage at /, but make every link it emits clean.
    index = ROOT / "index.html"
    if index.exists():
        old = index.read_text(encoding="utf-8")
        new = normalize_html(old, pages, legacy_redirect=False)
        if new != old:
            index.write_text(new, encoding="utf-8")

    for filename in sorted(pages):
        source = ROOT / filename
        old = source.read_text(encoding="utf-8")
        normalized = normalize_html(old, pages, legacy_redirect=True)
        if normalized != old:
            source.write_text(normalized, encoding="utf-8")

        target_dir = ROOT / filename[:-5]
        if target_dir.exists():
            unexpected = [p for p in target_dir.iterdir() if p.name != "index.html"]
            if unexpected:
                raise RuntimeError(
                    f"clean URL target conflicts with existing directory content: {target_dir}"
                )
        target_dir.mkdir(parents=True, exist_ok=True)
        target = target_dir / "index.html"
        if not target.exists() or target.read_text(encoding="utf-8") != normalized:
            target.write_text(normalized, encoding="utf-8")

    # Some newer publishers write directly to /<slug>/index.html instead of
    # creating a legacy root .html file. Normalize those article routes too so
    # every shareable article receives crawler-safe Open Graph metadata.
    for target in sorted(ROOT.glob("*/index.html")):
        if target.parent.name in {"assets", "automation", "apps", "repo-site", "transfer"}:
            continue
        old = target.read_text(encoding="utf-8")
        lower = old.lower()
        if "<article" not in lower and 'property="og:type" content="article"' not in lower:
            continue
        normalized = ensure_social_preview_meta(old)
        if normalized != old:
            target.write_text(normalized, encoding="utf-8")

    update_discovery_file(ROOT / "feed.xml", pages)
    update_discovery_file(ROOT / "sitemap.xml", pages)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
