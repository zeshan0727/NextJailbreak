#!/usr/bin/env python3
"""Fresh-release safety wrapper for original-source publishing.

The discovery site is used only to choose a current package/version. Article evidence
still comes exclusively from the original developer/repository source.
"""

from __future__ import annotations

from html.parser import HTMLParser
import re
from typing import Any

from automation import ios_repo_news as base
from automation import ios_repo_news_hardened as hardened

_original_discover = base.discover
_hardened_resolve = base.resolve_original_source
_expected_versions: dict[str, str] = {}


class _PlainText(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []

    def handle_data(self, data: str) -> None:
        value = " ".join(data.split())
        if value:
            self.parts.append(value)


def _plain(html_text: str) -> str:
    parser = _PlainText()
    parser.feed(html_text)
    return " ".join(parser.parts)


def _discovery_version(candidate: base.Candidate) -> str:
    cached = _expected_versions.get(candidate.discovery_url)
    if cached is not None:
        return cached
    try:
        text = _plain(base._fetch_text(candidate.discovery_url))
    except Exception:
        text = ""
    patterns = (
        r"\bVersion\s*[:\-]?\s*([0-9][0-9A-Za-z.+~:_-]*)",
        r"\bLatest\s+Version\s*[:\-]?\s*([0-9][0-9A-Za-z.+~:_-]*)",
    )
    version = ""
    for pattern in patterns:
        match = re.search(pattern, text, re.I)
        if match:
            version = match.group(1).strip().rstrip(".,;)")
            break
    _expected_versions[candidate.discovery_url] = version
    return version


def _discovery_positions(config: dict[str, Any]) -> dict[str, int]:
    try:
        url = str(config["discovery_url"])
        parser = base._DiscoveryParser(url)
        parser.feed(base._fetch_text(url))
        positions: dict[str, int] = {}
        for index, (href, _label) in enumerate(parser.links):
            if base._candidate_parts(href) and href not in positions:
                positions[href] = index
        return positions
    except Exception:
        return {}


def discover(config: dict[str, Any]) -> list[base.Candidate]:
    candidates = list(_original_discover(config))
    if config.get("prefer_freshest"):
        positions = _discovery_positions(config)
        candidates.sort(key=lambda item: (positions.get(item.discovery_url, 10**9), -item.rank, item.discovery_url))
    return candidates


def resolve_original_source(candidate: base.Candidate, config: dict[str, Any]) -> dict[str, Any]:
    source = _hardened_resolve(candidate, config)
    expected = _discovery_version(candidate)
    actual = str(source.get("version", "") or "").strip()
    if config.get("require_discovery_version_match", False):
        if not expected:
            raise ValueError("fresh discovery candidate has no readable discovery version")
        if not actual:
            raise ValueError(f"original source does not provide a version for discovery release {expected}")
        if actual.casefold() != expected.casefold():
            raise ValueError(
                f"discovery/source version mismatch rejected: discovery={expected}, original-source={actual}"
            )
    source["discovery_version"] = expected
    return source


base.discover = discover
base.resolve_original_source = resolve_original_source


def main() -> int:
    return hardened.main()


if __name__ == "__main__":
    raise SystemExit(main())
