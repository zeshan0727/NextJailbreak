#!/usr/bin/env python3
"""Resolve authentic, attributable source screenshots for published tweak articles."""

from __future__ import annotations

import html
import json
from pathlib import Path
import re
from typing import Any
from urllib.parse import urlparse
from urllib.error import URLError
from urllib.request import Request, urlopen


TRUSTED_MEDIA_HOSTS = {
    "media.havoc.app",
    "cdn.chariz.cloud",
    "tools4hack.santalab.me",
    "raw.githubusercontent.com",
    # Curated, attributed primary/first-hand article visuals only.
    "images.macrumors.com",
    "besiktasliseba.github.io",
}
LOCAL_MEDIA = re.compile(
    r"^(?:assets/articles|video-production)/[A-Za-z0-9._/-]+\.(?:jpe?g|png|webp)$",
    re.IGNORECASE,
)
HAVOC_MEDIA = re.compile(r"https://media\.havoc\.app/[A-Za-z0-9._~!$&'()*+,;=:@%/-]+")
CHARIZ_MEDIA = re.compile(
    r"https://cdn\.chariz\.cloud/screenshot/[A-Za-z0-9._~!$&'()*+,;=:@%/-]+"
)


class SourceMediaError(RuntimeError):
    """Raised when authentic source media cannot be established."""


def is_safe_media_reference(value: Any) -> bool:
    if not isinstance(value, str) or not value:
        return False
    if LOCAL_MEDIA.fullmatch(value):
        return ".." not in Path(value).parts
    parsed = urlparse(value)
    return (
        parsed.scheme == "https"
        and parsed.hostname in TRUSTED_MEDIA_HOSTS
        and not parsed.username
        and not parsed.password
        and (not parsed.query or (parsed.hostname == "images.macrumors.com" and parsed.query == "lossy="))
        and not parsed.fragment
    )


def _validate_item(item: Any, *, label: str) -> dict[str, str]:
    if not isinstance(item, dict):
        raise SourceMediaError(f"{label} must be an object")
    url = item.get("url")
    alt = item.get("alt")
    if not is_safe_media_reference(url):
        raise SourceMediaError(f"{label} uses an untrusted media URL")
    if not isinstance(alt, str) or len(alt.strip()) < 12:
        raise SourceMediaError(f"{label} requires useful alternative text")
    return {"url": url, "alt": alt.strip()}


def _validate_record(record: Any) -> dict[str, Any]:
    if not isinstance(record, dict):
        raise SourceMediaError("source media record must be an object")
    source_page_url = record.get("source_page_url")
    parsed = urlparse(str(source_page_url))
    if parsed.scheme != "https" or not parsed.netloc or parsed.username or parsed.password:
        raise SourceMediaError("source media credit URL must be public HTTPS")
    credit = record.get("credit_label")
    if not isinstance(credit, str) or len(credit.strip()) < 5:
        raise SourceMediaError("source media credit label is missing")
    hero = _validate_item(record.get("hero"), label="hero")
    screenshots = record.get("screenshots", [])
    if not isinstance(screenshots, list):
        raise SourceMediaError("screenshots must be an array")
    validated = [_validate_item(item, label=f"screenshot {index}") for index, item in enumerate(screenshots, 1)]
    seen = {hero["url"]}
    validated = [item for item in validated if not (item["url"] in seen or seen.add(item["url"]))]
    return {
        "credit_label": credit.strip(),
        "source_page_url": source_page_url,
        "official_source": record.get("official_source") is True,
        "hero": hero,
        "screenshots": validated,
    }


def load_source_media(path: Path) -> dict[str, Any]:
    if not path.exists():
        raise SourceMediaError(f"source media catalog is missing: {path}")
    catalog = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(catalog, dict) or catalog.get("schema_version") != 1:
        raise SourceMediaError("source media catalog uses an unsupported schema")
    packages = catalog.get("packages")
    if not isinstance(packages, dict):
        raise SourceMediaError("source media catalog packages must be an object")
    return packages


def _download_page(url: str) -> str:
    request = Request(
        url,
        headers={
            "User-Agent": "NextSolutionSourceMedia/1.0 (+https://nextjailbreak.com)",
            "Accept": "text/html,application/xhtml+xml",
        },
    )
    try:
        with urlopen(request, timeout=15) as response:
            content_type = response.headers.get_content_type()
            if content_type not in {"text/html", "application/xhtml+xml"}:
                raise SourceMediaError("official source did not return HTML")
            return response.read(2_000_000).decode(
                response.headers.get_content_charset() or "utf-8", "replace"
            )
    except (OSError, URLError) as exc:
        raise SourceMediaError("official source media lookup failed") from exc


def _discover_official_media(source_page_url: str, source_name: str) -> dict[str, Any]:
    parsed = urlparse(source_page_url)
    if parsed.scheme != "https" or parsed.username or parsed.password:
        raise SourceMediaError("official package page must use public HTTPS")
    if parsed.hostname == "havoc.app":
        pattern = HAVOC_MEDIA
        media_host = "media.havoc.app"
    elif parsed.hostname in {"chariz.com", "www.chariz.com"}:
        pattern = CHARIZ_MEDIA
        media_host = "cdn.chariz.cloud"
    else:
        raise SourceMediaError(
            "no curated screenshot record exists and this official source has no safe automatic media adapter"
        )
    page = html.unescape(_download_page(source_page_url)).replace("\\/", "/")
    matches = pattern.findall(page)
    urls = list(dict.fromkeys(url.rstrip("\"')]>.,") for url in matches))
    urls = [url for url in urls if urlparse(url).hostname == media_host and is_safe_media_reference(url)]
    if not urls:
        raise SourceMediaError("the official package page did not expose an authentic screenshot")
    label = f"{source_name} official package listing"
    return _validate_record(
        {
            "credit_label": label,
            "source_page_url": source_page_url,
            "official_source": True,
            "hero": {"url": urls[0], "alt": f"{source_name} official package screenshot"},
            "screenshots": [
                {"url": url, "alt": f"{source_name} official package screenshot {index}"}
                for index, url in enumerate(urls[1:5], 2)
            ],
        }
    )


def resolve_source_media(
    candidate: dict[str, Any],
    *,
    catalog_path: Path,
    source_page_url: str,
) -> dict[str, Any]:
    packages = load_source_media(catalog_path)
    package = str(candidate.get("package", ""))
    if package in packages:
        return _validate_record(packages[package])
    source_name = str(candidate.get("name") or candidate.get("source_name") or "Tweak")
    return _discover_official_media(source_page_url, source_name)
