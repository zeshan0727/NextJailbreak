#!/usr/bin/env python3
"""Publish one independently verified tweak article with deterministic guards."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
from email.utils import format_datetime
import hashlib
import html
import json
from pathlib import Path
import re
import sys
from typing import Any
from urllib.parse import urlparse
from xml.etree import ElementTree
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from automation.draft_pipeline import article_source_url, render_article, validate_article
from automation.editorial import mark_candidate_drafted
from automation.seo_utils import seo_description
from automation.source_media import (
    SourceMediaError,
    is_safe_media_reference,
    resolve_source_media,
)


AUDIT_SCHEMA_VERSION = 1
HOME_START = "<!-- AUTO_ARTICLES_HOME_START -->"
HOME_END = "<!-- AUTO_ARTICLES_HOME_END -->"
TUTORIALS_START = "<!-- AUTO_ARTICLES_TUTORIALS_START -->"
TUTORIALS_END = "<!-- AUTO_ARTICLES_TUTORIALS_END -->"
SITEMAP_NAMESPACE = "http://www.sitemaps.org/schemas/sitemap/0.9"
SAFE_TARGET = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,118}[a-z0-9])?\.html$")


class PublishingError(RuntimeError):
    """Raised when a live publication guard is not satisfied."""


@dataclass(frozen=True)
class PreflightResult:
    allowed: bool
    reason: str
    local_day: str
    published_today: int
    max_today: int
    boost_active: bool


def load_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        raise PublishingError(f"required JSON file is missing: {path}")
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise PublishingError(f"JSON root must be an object: {path}")
    return value


def load_audit(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {
            "schema_version": AUDIT_SCHEMA_VERSION,
            "updated_at": None,
            "entries": [],
            "events": [],
        }
    audit = load_json(path)
    if audit.get("schema_version") != AUDIT_SCHEMA_VERSION:
        raise PublishingError("publication audit uses an unsupported schema version")
    if not isinstance(audit.get("entries"), list) or not isinstance(
        audit.get("events"), list
    ):
        raise PublishingError("publication audit entries and events must be arrays")
    return audit


def _parse_now(value: str | None) -> datetime:
    if not value:
        return datetime.now(timezone.utc)
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise PublishingError("--now must contain a timezone offset")
    return parsed.astimezone(timezone.utc)


def _policy(site: dict[str, Any]) -> tuple[dict[str, Any], ZoneInfo]:
    publishing = site.get("publishing")
    if not isinstance(publishing, dict):
        raise PublishingError("site publishing policy is missing")
    if publishing.get("max_per_day") != 4:
        raise PublishingError("publishing.max_per_day must remain exactly 4 for the regular six-hour schedule")
    windows = publishing.get("windows_local_hours")
    if (
        not isinstance(windows, list)
        or len(windows) != publishing["max_per_day"]
        or any(not isinstance(hour, int) or not 0 <= hour <= 23 for hour in windows)
        or windows != sorted(set(windows))
    ):
        raise PublishingError(
            "publishing.windows_local_hours must contain four unique sorted local hours"
        )
    if not isinstance(publishing.get("boost_max_per_day"), int) or not 1 <= publishing["boost_max_per_day"] <= 8:
        raise PublishingError("publishing.boost_max_per_day must be between 1 and 8")
    if publishing.get("boost_interval_hours") != 3:
        raise PublishingError("publishing.boost_interval_hours must remain exactly 3")
    boost_until = publishing.get("boost_until")
    if not isinstance(boost_until, str):
        raise PublishingError("publishing.boost_until must be configured")
    try:
        parsed_boost_until = datetime.fromisoformat(boost_until.replace("Z", "+00:00"))
    except ValueError as exc:
        raise PublishingError("publishing.boost_until is invalid") from exc
    if parsed_boost_until.tzinfo is None:
        raise PublishingError("publishing.boost_until must contain a timezone")
    timezone_name = publishing.get("timezone")
    if not isinstance(timezone_name, str) or not timezone_name:
        raise PublishingError("publishing.timezone must be configured")
    try:
        local_timezone = ZoneInfo(timezone_name)
    except ZoneInfoNotFoundError as exc:
        raise PublishingError(f"unknown publishing timezone: {timezone_name}") from exc
    return publishing, local_timezone


def preflight(
    site: dict[str, Any],
    audit: dict[str, Any],
    *,
    now: datetime,
    trigger_schedule: str | None = None,
) -> PreflightResult:
    publishing, local_timezone = _policy(site)
    local_day = now.astimezone(local_timezone).date().isoformat()
    events_today = 0
    event_times: list[datetime] = []
    for event in audit["events"]:
        if not isinstance(event, dict) or not isinstance(event.get("published_at"), str):
            raise PublishingError("publication audit contains an invalid event")
        try:
            published_at = datetime.fromisoformat(
                event["published_at"].replace("Z", "+00:00")
            )
        except ValueError as exc:
            raise PublishingError("publication audit contains an invalid timestamp") from exc
        if published_at.tzinfo is None:
            raise PublishingError("publication timestamps must contain a timezone")
        published_at = published_at.astimezone(timezone.utc)
        event_times.append(published_at)
        if (
            published_at.astimezone(local_timezone).date().isoformat() == local_day
            and event.get("action", "create") == "create"
        ):
            events_today += 1
    boost_until = datetime.fromisoformat(
        str(publishing["boost_until"]).replace("Z", "+00:00")
    ).astimezone(timezone.utc)
    boost_active = now.astimezone(timezone.utc) < boost_until
    max_today = int(publishing["boost_max_per_day"] if boost_active else publishing["max_per_day"])
    if publishing.get("enabled") is not True:
        return PreflightResult(False, "kill-switch-disabled", local_day, events_today, max_today, boost_active)
    if trigger_schedule and trigger_schedule == publishing.get("boost_cron") and not boost_active:
        return PreflightResult(False, "launch-boost-ended", local_day, events_today, max_today, boost_active)
    if events_today >= max_today:
        return PreflightResult(False, "publication-limit-reached", local_day, events_today, max_today, boost_active)
    if trigger_schedule and trigger_schedule == publishing.get("normal_cron"):
        local_now = now.astimezone(local_timezone)
        due_windows = sum(
            1 for hour in publishing["windows_local_hours"] if local_now.hour >= hour
        )
        if due_windows == 0:
            return PreflightResult(False, "no-publishing-window-due", local_day, events_today, max_today, boost_active)
        if events_today >= due_windows:
            return PreflightResult(False, "scheduled-window-already-satisfied", local_day, events_today, max_today, boost_active)
    elif trigger_schedule and trigger_schedule != publishing.get("boost_cron"):
        return PreflightResult(False, "unrecognized-scheduled-trigger", local_day, events_today, max_today, boost_active)
    if boost_active and event_times:
        latest = max(event_times)
        interval_seconds = int(publishing["boost_interval_hours"]) * 3600
        if (now.astimezone(timezone.utc) - latest).total_seconds() < interval_seconds:
            return PreflightResult(False, "three-hour-interval-not-reached", local_day, events_today, max_today, boost_active)
    if site.get("shortener", {}).get("enabled") is not False:
        return PreflightResult(False, "shortener-must-remain-disabled", local_day, events_today, max_today, boost_active)
    return PreflightResult(True, "ready", local_day, events_today, max_today, boost_active)


def _safe_external_url(value: Any) -> str:
    if not isinstance(value, str):
        raise PublishingError("source URL is missing")
    parsed = urlparse(value)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise PublishingError("source URL must be public HTTP(S)")
    if parsed.username or parsed.password:
        raise PublishingError("credentials are not allowed in source URLs")
    return value


def _validate_manifest(
    manifest: dict[str, Any], site: dict[str, Any]
) -> tuple[dict[str, Any], dict[str, Any]]:
    if manifest.get("schema_version") != 1:
        raise PublishingError("draft manifest uses an unsupported schema version")
    if manifest.get("publication_authorized") is not False:
        raise PublishingError("the writer must never authorize its own publication")
    if manifest.get("shortener_enabled") is not False:
        raise PublishingError("draft contains an enabled URL shortener")
    quality = manifest.get("deterministic_quality")
    verifier = manifest.get("verifier")
    if not isinstance(quality, dict) or quality.get("approved") is not True:
        raise PublishingError("deterministic quality gates did not approve the draft")
    if quality.get("issues"):
        raise PublishingError("deterministic quality report still contains issues")
    if not isinstance(verifier, dict) or verifier.get("approved") is not True:
        raise PublishingError("independent verifier did not approve the draft")
    if verifier.get("issues") or verifier.get("unsupported_claims"):
        raise PublishingError("independent verifier report still contains issues")
    candidate = manifest.get("candidate")
    article = manifest.get("article")
    if not isinstance(candidate, dict) or not isinstance(article, dict):
        raise PublishingError("manifest candidate and article must be objects")
    if candidate.get("selection_pool") not in {"pending", "evergreen"}:
        raise PublishingError("candidate did not come from an approved editorial pool")
    if candidate.get("source_tier") != "verified":
        raise PublishingError("only verified source metadata can be published")
    if candidate.get("blockers"):
        raise PublishingError("blocked candidate cannot be published")
    if candidate.get("publish_eligible") is not True:
        raise PublishingError("candidate is not publication eligible")
    for key in (
        "package",
        "name",
        "version",
        "author",
        "source_name",
        "source_url",
        "slug",
        "category",
    ):
        value = candidate.get(key)
        if value is None or value == "":
            raise PublishingError(f"candidate field is missing: {key}")
    _safe_external_url(candidate["source_url"])
    target_path = manifest.get("target_path")
    expected_target = f"{candidate['slug']}.html"
    if target_path != expected_target or not SAFE_TARGET.fullmatch(str(target_path)):
        raise PublishingError("draft target is not a safe canonical HTML path")
    result = validate_article(article, candidate)
    if not result.approved:
        raise PublishingError("draft failed publication-time validation: " + "; ".join(result.issues))
    configured_base = str(site.get("base_url", "")).rstrip("/")
    if configured_base != "https://nextjailbreak.com":
        raise PublishingError("publishing base URL is not the production domain")
    return article, candidate


def _replace_marker_block(text: str, start: str, end: str, body: str) -> str:
    if text.count(start) != 1 or text.count(end) != 1:
        raise PublishingError(f"expected exactly one marker pair: {start} / {end}")
    before, remainder = text.split(start, 1)
    _, after = remainder.split(end, 1)
    marker_indent = before.rsplit("\n", 1)[-1]
    rendered_body = (
        f"\n{body.rstrip()}\n{marker_indent}" if body.strip() else f"\n{marker_indent}"
    )
    return before + start + rendered_body + end + after


def _card_icon(name: str) -> str:
    parts = re.findall(r"[A-Za-z0-9]+", name)
    if not parts:
        return "TW"
    if len(parts) == 1:
        return parts[0][:2].upper()
    return (parts[0][0] + parts[1][0]).upper()


def _render_card(entry: dict[str, Any], *, indent: str) -> str:
    esc = lambda value: html.escape(str(value), quote=True)
    category = entry.get("category", {})
    label = category.get("label", "Tweak information") if isinstance(category, dict) else "Tweak information"
    image = entry.get("image")
    if is_safe_media_reference(image):
        visual = f'{indent}  <a class="card-media" href="{esc(entry["href"])}" aria-label="Open {esc(entry["title"])}"><img src="{esc(image)}" alt="" width="1600" height="900" loading="lazy"></a>'
        card_class = "content-card has-visual"
    else:
        visual = f'{indent}  <div class="card-icon" aria-hidden="true">{esc(_card_icon(str(entry["name"])))}</div>'
        card_class = "content-card"
    return "\n".join(
        (
            f'{indent}<article class="{card_class}">',
            f'{indent}  <div class="card-meta"><span class="tag">{esc(label)}</span><span class="tag">{esc(entry["source_name"])}</span></div>',
            visual,
            f'{indent}  <h3>{esc(entry["title"])}</h3>',
            f'{indent}  <p>{esc(entry["description"])}</p>',
            f'{indent}  <a class="card-link" href="{esc(entry["href"])}">Read guide →</a>',
            f"{indent}</article>",
        )
    )


def _render_cards(entries: list[dict[str, Any]], *, limit: int, indent: str) -> str:
    current = sorted(
        (entry for entry in entries if entry.get("entry_type") != "editorial"),
        key=lambda item: str(item.get("modified_at") or item.get("published_at") or ""),
        reverse=True,
    )[:limit]
    return "\n".join(_render_card(entry, indent=indent) for entry in current)


def _render_feed(entries: list[dict[str, Any]], site: dict[str, Any]) -> str:
    channel = ElementTree.Element("channel")
    ElementTree.SubElement(channel, "title").text = str(site["site_name"])
    ElementTree.SubElement(channel, "link").text = str(site["base_url"])
    ElementTree.SubElement(channel, "description").text = (
        "Verified-source jailbreak tweak information and Next Jailbreak guides."
    )
    ElementTree.SubElement(channel, "language").text = "en"
    sorted_entries = sorted(
        entries,
        key=lambda item: str(item.get("modified_at") or item.get("published_at") or ""),
        reverse=True,
    )[:30]
    for entry in sorted_entries:
        item = ElementTree.SubElement(channel, "item")
        canonical = f"{str(site['base_url']).rstrip('/')}/{entry['href']}"
        ElementTree.SubElement(item, "title").text = str(entry["title"])
        ElementTree.SubElement(item, "link").text = canonical
        guid = ElementTree.SubElement(item, "guid", {"isPermaLink": "true"})
        guid.text = canonical
        published = datetime.fromisoformat(
            str(entry.get("modified_at") or entry["published_at"]).replace("Z", "+00:00")
        )
        ElementTree.SubElement(item, "pubDate").text = format_datetime(
            published.astimezone(timezone.utc), usegmt=True
        )
        ElementTree.SubElement(item, "description").text = str(entry["description"])
        category = entry.get("category", {})
        ElementTree.SubElement(item, "category").text = str(
            category.get("label", "Tweak information")
        )
    rss = ElementTree.Element("rss", {"version": "2.0"})
    rss.append(channel)
    ElementTree.indent(rss, space="  ")
    return '<?xml version="1.0" encoding="UTF-8"?>\n' + ElementTree.tostring(
        rss, encoding="unicode"
    ) + "\n"


def _update_sitemap(
    sitemap_text: str, entries: list[dict[str, Any]], site: dict[str, Any]
) -> str:
    ElementTree.register_namespace("", SITEMAP_NAMESPACE)
    root = ElementTree.fromstring(sitemap_text)
    if root.tag != f"{{{SITEMAP_NAMESPACE}}}urlset":
        raise PublishingError("sitemap root is not a standard urlset")
    existing: dict[str, ElementTree.Element] = {}
    # Clean historical duplicate sitemap rows before adding or updating articles.
    for node in list(root.findall(f"{{{SITEMAP_NAMESPACE}}}url")):
        location = node.find(f"{{{SITEMAP_NAMESPACE}}}loc")
        if location is not None and location.text:
            canonical_location = location.text.strip()
            if canonical_location in existing:
                root.remove(node)
                continue
            existing[canonical_location] = node
    base_url = str(site["base_url"]).rstrip("/")
    for entry in entries:
        canonical = f"{base_url}/{entry['href']}"
        node = existing.get(canonical)
        if node is None:
            node = ElementTree.SubElement(root, f"{{{SITEMAP_NAMESPACE}}}url")
            ElementTree.SubElement(node, f"{{{SITEMAP_NAMESPACE}}}loc").text = canonical
        lastmod = node.find(f"{{{SITEMAP_NAMESPACE}}}lastmod")
        if lastmod is None:
            lastmod = ElementTree.SubElement(node, f"{{{SITEMAP_NAMESPACE}}}lastmod")
        lastmod.text = str(entry.get("modified_at") or entry["published_at"])[:10]
        changefreq = node.find(f"{{{SITEMAP_NAMESPACE}}}changefreq")
        if changefreq is None:
            changefreq = ElementTree.SubElement(node, f"{{{SITEMAP_NAMESPACE}}}changefreq")
        changefreq.text = "monthly"
        priority = node.find(f"{{{SITEMAP_NAMESPACE}}}priority")
        if priority is None:
            priority = ElementTree.SubElement(node, f"{{{SITEMAP_NAMESPACE}}}priority")
        priority.text = "0.8"
    ElementTree.indent(root, space="  ")
    return '<?xml version="1.0" encoding="UTF-8"?>\n' + ElementTree.tostring(
        root, encoding="unicode"
    ) + "\n"


def _write_github_output(path: Path | None, values: dict[str, Any]) -> None:
    if path is None:
        return
    with path.open("a", encoding="utf-8") as output:
        for key, value in values.items():
            text_value = str(value).lower() if isinstance(value, bool) else str(value)
            if "\n" in text_value:
                raise PublishingError(f"GitHub output cannot contain a newline: {key}")
            output.write(f"{key}={text_value}\n")


def publish(
    *,
    repository_root: Path,
    manifest: dict[str, Any],
    site: dict[str, Any],
    audit: dict[str, Any],
    audit_path: Path,
    now: datetime,
    run_id: str,
    confirm_live: bool,
    editorial_state_path: Path | None = None,
) -> dict[str, Any]:
    if not confirm_live:
        raise PublishingError("live publication requires --confirm-live")
    status = preflight(site, audit, now=now)
    if not status.allowed:
        raise PublishingError(f"publication preflight stopped: {status.reason}")
    article, candidate = _validate_manifest(manifest, site)
    fingerprint = manifest.get("candidate_fingerprint")
    if not isinstance(fingerprint, str) or not re.fullmatch(r"[0-9a-f]{64}", fingerprint):
        raise PublishingError("candidate fingerprint is missing or invalid")
    for entry in audit["entries"]:
        if isinstance(entry, dict) and entry.get("candidate_fingerprint") == fingerprint:
            if editorial_state_path is not None:
                state = load_json(editorial_state_path)
                mark_candidate_drafted(
                    state,
                    candidate,
                    drafted_at=now.replace(microsecond=0).isoformat(),
                    draft_target=str(entry["href"]),
                    candidate_fingerprint=fingerprint,
                )
                editorial_state_path.write_text(
                    json.dumps(state, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
                    encoding="utf-8",
                )
            return {
                "published": False,
                "duplicate": True,
                "target_path": entry["href"],
                "title": entry["title"],
                "reason": "candidate-already-published",
            }

    target_path = str(manifest["target_path"])
    target = repository_root / target_path
    matching_entry = next(
        (
            entry
            for entry in audit["entries"]
            if isinstance(entry, dict) and entry.get("package") == candidate["package"]
        ),
        None,
    )
    existing_href = next(
        (
            entry
            for entry in audit["entries"]
            if isinstance(entry, dict) and entry.get("href") == target_path
        ),
        None,
    )
    if existing_href and existing_href.get("package") != candidate["package"]:
        raise PublishingError("target path belongs to another package")
    if target.exists() and matching_entry is None:
        raise PublishingError("publisher will not overwrite an unmanaged article")
    if matching_entry and matching_entry.get("href") != target_path:
        raise PublishingError("package URL changed; version updates must keep the existing URL")
    if matching_entry and matching_entry.get("version") == candidate["version"]:
        raise PublishingError("same package version has a different candidate fingerprint")

    source_page_url = article_source_url(candidate)
    try:
        media = resolve_source_media(
            candidate,
            catalog_path=repository_root / "automation/source-media.json",
            source_page_url=source_page_url,
        )
    except SourceMediaError as exc:
        raise PublishingError(f"authentic source media is required: {exc}") from exc

    published_at = now.replace(microsecond=0).isoformat()
    rendered_article = render_article(article, candidate, site, media)
    article_hash = hashlib.sha256(rendered_article.encode("utf-8")).hexdigest()
    category = candidate["category"]
    entry = {
        "package": candidate["package"],
        "name": candidate["name"],
        "version": candidate["version"],
        "title": article["title"],
        "description": seo_description(candidate["name"], candidate["version"]),
        "href": target_path,
        "category": category,
        "source_name": candidate["source_name"],
        "source_url": candidate["source_url"],
        "source_page_url": source_page_url,
        "selection_pool": candidate["selection_pool"],
        "candidate_fingerprint": fingerprint,
        "article_sha256": article_hash,
        "image": media["hero"]["url"],
        "media_credit": media["credit_label"],
        "media_source_url": media["source_page_url"],
        "published_at": (
            matching_entry.get("published_at") if matching_entry else published_at
        ),
        "modified_at": published_at,
    }
    entries = [
        current
        for current in audit["entries"]
        if not isinstance(current, dict) or current.get("package") != candidate["package"]
    ]
    entries.append(entry)
    entries.sort(
        key=lambda item: str(item.get("modified_at") or item.get("published_at") or ""),
        reverse=True,
    )
    action = "update" if matching_entry else "create"
    event = {
        "published_at": published_at,
        "action": action,
        "package": candidate["package"],
        "version": candidate["version"],
        "href": target_path,
        "candidate_fingerprint": fingerprint,
        "run_id": str(run_id),
    }
    next_audit = {
        "schema_version": AUDIT_SCHEMA_VERSION,
        "updated_at": published_at,
        "entries": entries,
        "events": audit["events"] + [event],
    }

    index_path = repository_root / "index.html"
    tutorials_path = repository_root / "tutorials.html"
    sitemap_path = repository_root / "sitemap.xml"
    for required_path in (index_path, tutorials_path, sitemap_path):
        if not required_path.exists():
            raise PublishingError(f"required website file is missing: {required_path.name}")
    next_index = _replace_marker_block(
        index_path.read_text(encoding="utf-8"),
        HOME_START,
        HOME_END,
        _render_cards(entries, limit=4, indent="          "),
    )
    next_tutorials = _replace_marker_block(
        tutorials_path.read_text(encoding="utf-8"),
        TUTORIALS_START,
        TUTORIALS_END,
        _render_cards(entries, limit=30, indent="          "),
    )
    next_feed = _render_feed(entries, site)
    next_sitemap = _update_sitemap(
        sitemap_path.read_text(encoding="utf-8"), entries, site
    )

    target.write_text(rendered_article, encoding="utf-8")
    index_path.write_text(next_index, encoding="utf-8")
    tutorials_path.write_text(next_tutorials, encoding="utf-8")
    (repository_root / "feed.xml").write_text(next_feed, encoding="utf-8")
    sitemap_path.write_text(next_sitemap, encoding="utf-8")
    audit_path.parent.mkdir(parents=True, exist_ok=True)
    audit_path.write_text(
        json.dumps(next_audit, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    if editorial_state_path is not None:
        state = load_json(editorial_state_path)
        mark_candidate_drafted(
            state,
            candidate,
            drafted_at=published_at,
            draft_target=target_path,
            candidate_fingerprint=fingerprint,
        )
        editorial_state_path.write_text(
            json.dumps(state, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
    return {
        "published": True,
        "duplicate": False,
        "target_path": target_path,
        "title": article["title"],
        "action": action,
        "article_sha256": article_hash,
        "local_day": status.local_day,
        "publication_number": status.published_today + 1,
        "max_today": status.max_today,
        "boost_active": status.boost_active,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("preflight", "publish"))
    parser.add_argument("--repository-root", type=Path, default=Path("."))
    parser.add_argument("--site", type=Path, default=Path("automation/site.json"))
    parser.add_argument(
        "--audit", type=Path, default=Path("automation/published-articles.json")
    )
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--editorial-state", type=Path)
    parser.add_argument("--now")
    parser.add_argument("--run-id", default="local")
    parser.add_argument("--github-output", type=Path)
    parser.add_argument("--trigger-schedule")
    parser.add_argument("--confirm-live", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        root = args.repository_root.resolve()
        site_path = args.site if args.site.is_absolute() else root / args.site
        audit_path = args.audit if args.audit.is_absolute() else root / args.audit
        site = load_json(site_path)
        audit = load_audit(audit_path)
        now = _parse_now(args.now)
        if args.command == "preflight":
            result = preflight(
                site,
                audit,
                now=now,
                trigger_schedule=args.trigger_schedule,
            )
            payload = {
                "allowed": result.allowed,
                "reason": result.reason,
                "local_day": result.local_day,
                "published_today": result.published_today,
                "max_today": result.max_today,
                "boost_active": result.boost_active,
            }
            _write_github_output(args.github_output, payload)
        else:
            if args.manifest is None:
                raise PublishingError("publish requires --manifest")
            manifest_path = (
                args.manifest if args.manifest.is_absolute() else root / args.manifest
            )
            manifest = load_json(manifest_path)
            payload = publish(
                repository_root=root,
                manifest=manifest,
                site=site,
                audit=audit,
                audit_path=audit_path,
                now=now,
                run_id=args.run_id,
                confirm_live=args.confirm_live,
                editorial_state_path=(
                    args.editorial_state
                    if args.editorial_state is None or args.editorial_state.is_absolute()
                    else root / args.editorial_state
                ),
            )
            _write_github_output(args.github_output, payload)
        print(json.dumps(payload, sort_keys=True, ensure_ascii=False))
        return 0
    except (PublishingError, ValueError, json.JSONDecodeError) as exc:
        print(f"publisher error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
