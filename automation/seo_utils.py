#!/usr/bin/env python3
"""Deterministic SEO helpers for Next Jailbreak article pages."""

from __future__ import annotations

import json
import re
from typing import Any


def _compact(value: Any) -> str:
    return " ".join(str(value or "").split()).strip()


def _trim_words(value: str, limit: int) -> str:
    text = _compact(value)
    if len(text) <= limit:
        return text
    cut = text[: limit + 1].rsplit(" ", 1)[0].rstrip(" ,;:-–—")
    if cut and cut[-1] not in ".!?":
        cut += "."
    return cut or text[:limit].rstrip()


def seo_title(name: Any, version: Any = "", site_name: str = "Next Jailbreak", *, kind: str = "iOS Jailbreak Tweak") -> str:
    product = _compact(f"{_compact(name)} {_compact(version)}")
    core = _compact(f"{product} {kind}")
    if _compact(version) and "update" not in kind.lower():
        core = f"{core} Update"
    suffix = f" | {_compact(site_name) or 'Next Jailbreak'}"
    if len(core + suffix) > 68:
        core = _compact(f"{product} Jailbreak Tweak") if "tweak" in kind.lower() else product
    return _trim_words(core + suffix, 72).rstrip(".")


def seo_description(name: Any, version: Any = "", *, kind: str = "iOS jailbreak tweak") -> str:
    product = _compact(f"{_compact(name)} {_compact(version)}")
    if "tweak" in kind.lower():
        text = (
            f"{product} iOS jailbreak tweak: verified features, compatibility, requirements "
            "and release details from the original developer source."
        )
    else:
        text = (
            f"{product}: verified compatibility, requirements, release details and practical "
            "guidance based on official project sources."
        )
    return _trim_words(text, 158)


def semantic_jsonld(*, canonical: str, name: Any, version: Any = "", site_url: str = "https://nextjailbreak.com", section_url: str = "https://nextjailbreak.com/tutorials/", section_name: str = "Tweaks") -> str:
    product = _compact(name)
    ver = _compact(version)
    application: dict[str, Any] = {
        "@type": "SoftwareApplication",
        "name": product,
        "applicationCategory": "UtilitiesApplication",
        "operatingSystem": "iOS",
        "url": canonical,
    }
    if ver:
        application["softwareVersion"] = ver
    payload = {
        "@context": "https://schema.org",
        "@graph": [
            application,
            {
                "@type": "BreadcrumbList",
                "itemListElement": [
                    {"@type": "ListItem", "position": 1, "name": "Next Jailbreak", "item": site_url.rstrip("/") + "/"},
                    {"@type": "ListItem", "position": 2, "name": section_name, "item": section_url},
                    {"@type": "ListItem", "position": 3, "name": product, "item": canonical},
                ],
            },
        ],
    }
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


def suspicious_generated_metadata(value: Any) -> bool:
    text = _compact(value)
    if not text:
        return True
    if "�" in text or "\x00" in text:
        return True
    if re.search(r"[-–—,:;]\s*$", text):
        return True
    if re.search(r"\b[A-Za-z][A-Za-z0-9]{2,}-[A-Za-z]{1,4}$", text):
        return True
    non_ascii_letters = [ch for ch in text if ord(ch) > 127 and ch.isalpha()]
    return len(non_ascii_letters) > 3
