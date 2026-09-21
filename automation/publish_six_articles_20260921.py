#!/usr/bin/env python3
"""User-authorized six-article batch, using the existing verified publisher.

Scheduling is intentionally not used for this explicit batch. All source,
duplicate, writer/verifier, media and publication gates remain in force.
"""
from __future__ import annotations
import hashlib
import html
import json
import re
from pathlib import Path
from xml.etree import ElementTree as ET
from automation import publish_verified_batch_20260916 as batch
from automation import sync_editorial_indexes
from automation.ios_repo_news import validate_article
from automation.source_visuals import acquire_unique_source_visual

ROOT = Path(__file__).resolve().parents[1]
TARGETS = json.loads((ROOT / "automation/article_batch_20260921.json").read_text())
BY_NAME = {t["name"]: t for t in TARGETS}
REPORT = ROOT / "automation/batch-20260921-result.json"
REVIEW = ROOT / "automation/out/batch-20260921"
batch.TARGETS = TARGETS
batch.CONFIG = {**batch.CONFIG, "minimum_article_words": 1000, "minimum_sections": 5}
original_build = batch.build_source
original_render = batch._render_article
original_slug = batch._slug
original_generate = batch.generate_strict


def slug(value):
    for target in TARGETS:
        if value == f"{target['name']} {target['version']} update":
            return target["slug"]
    return original_slug(value)


def build_source(target):
    cached = REVIEW / f"{target['slug']}-source.json"
    if cached.exists():
        source = json.loads(cached.read_text())
        assert source['name'] == target['name'] and source['version'] == target['version']
        assert source['source_urls'] == target['urls'] and target['scope_note'] in source['source_text']
        if target.get('required_source_text'):
            assert target['required_source_text'] in source['source_text']
        return source
    # Fetch original pages before considering editorial instructions as context.
    actual = {k: v for k, v in target.items() if k != "scope_note"}
    source = original_build(actual)
    required = target.get("required_source_text")
    if required and required not in source["source_text"]:
        raise ValueError(f"Dated source snapshot changed or is unavailable: {required}")
    source["source_text"] = (
        "EDITORIAL BRIEF (scope instructions, not independent evidence):\n"
        + target["scope_note"]
        + "\nUse this exact article title: " + target["title"]
        + "\nWrite at least 1,000 useful words and five substantive sections, without filler. "
        + "Distinguish release dates, build dates and this article's publication date.\n\n"
        + source["source_text"]
    )
    REVIEW.mkdir(parents=True, exist_ok=True)
    (REVIEW / f"{target['slug']}-source.json").write_text(json.dumps(source, indent=2))
    return source


def generate(source):
    print(f"GENERATING {source['name']} {source['version']}", flush=True)
    cached = REVIEW / f"{BY_NAME[source['name']]['slug']}-draft.json"
    if cached.exists():
        data = json.loads(cached.read_text())
        assert data.get('verification', {}).get('verifier'), 'Missing successful verifier metadata'
        assert not validate_article(data['article'], source, batch.CONFIG)
        print(f"REUSING VERIFIED DRAFT {source['name']}", flush=True)
        return data['article'], data['verification']
    article, meta = original_generate(source)
    assert not validate_article(article, source, batch.CONFIG)
    (REVIEW / f"{BY_NAME[source['name']]['slug']}-draft.json").write_text(
        json.dumps({"article": article, "verification": meta}, indent=2))
    return article, meta


def render(article, source, media, site, now, target_path):
    target = BY_NAME[source["name"]]
    # Two distinct authentic source images; normal visual registry rules apply.
    detail = acquire_unique_source_visual(
        source_urls=source["source_urls"], slug=target["slug"] + "-detail",
        repository_root=ROOT)
    digest = lambda p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest()
    if digest(media["image"]) == digest(detail["image"]):
        raise ValueError(f"Duplicate visual content for {source['name']}")
    rendered = original_render(article, source, media, site, now, target_path)
    title = article["title"] + " | " + site.get("site_name", "Next Jailbreak")
    description = article["meta_description"]
    rendered = re.sub(r"<title>.*?</title>", "<title>" + html.escape(title) + "</title>", rendered, count=1)
    for attr, key, value in [("name", "description", description), ("property", "og:title", title),
                             ("property", "og:description", description), ("name", "twitter:title", title),
                             ("name", "twitter:description", description)]:
        rendered = re.sub(r'<meta ' + attr + '="' + re.escape(key) + r'" content="[^"]*">',
                          f'<meta {attr}="{key}" content="{html.escape(value, quote=True)}">', rendered)
    section = target["category"]["label"]
    section_link = "/tutorials/#jailbreak-guides" if section == "Jailbreak" else "/tutorials/#verified-articles"
    rendered = rendered.replace('<a href="/tutorials/#verified-articles">Latest updates</a>',
                                f'<a href="{section_link}">{html.escape(section)}</a>')
    rendered = rendered.replace("Latest update · Original-source editorial", html.escape(section) + " · Release explainer")
    def schema(match):
        value = json.loads(match.group(1))
        def walk(obj):
            if isinstance(obj, list):
                for v in obj: walk(v)
            elif isinstance(obj, dict):
                if obj.get("@type") == "TechArticle":
                    obj.update(description=description, headline=article["title"], articleSection=section)
                    obj.pop("alternativeHeadline", None)
                if obj.get("@type") == "SoftwareApplication":
                    obj['softwareVersion'] = {'palera1n': '3.0.0-beta.2', 'SideStore Nightly': '0.7.0-20260920.1479+0dd743f7'}.get(source['name'], source['version'])
                    obj['description'] = description
                if obj.get("@type") == "ListItem" and obj.get("position") == 2:
                    obj.update(name=section, item=site["base_url"].rstrip("/") + section_link)
                for v in obj.values(): walk(v)
        walk(value)
        return '<script type="application/ld+json">' + json.dumps(value, ensure_ascii=False) + '</script>'
    rendered = re.sub(r'<script type="application/ld\+json">(.*?)</script>', schema, rendered, flags=re.S)
    figure = ('<figure class="article-visual"><img loading="lazy" src="/' + html.escape(detail["image"])
              + '" alt="Additional original-source visual for ' + html.escape(source["name"])
              + '"><figcaption>Original project/source-page visual. <a href="'
              + html.escape(detail["source_url"], quote=True)
              + '" rel="noopener noreferrer">View image source and attribution</a>.</figcaption></figure>')
    rendered = rendered.replace('<h2>Frequently asked questions</h2>', figure + '<h2>Frequently asked questions</h2>', 1)
    related = ''.join('<li><a href="/' + t["slug"] + '/">' + html.escape(t["title"]) + '</a></li>'
                      for t in TARGETS if t["name"] != target["name"])
    rendered = rendered.replace('<div class="article-disclaimer">', '<h2>Related reading</h2><ul>' + related + '</ul><div class="article-disclaimer">', 1)
    target["detail_media"] = detail
    target["article_description"] = description
    return rendered


def check():
    result = json.loads(REPORT.read_text())
    assert len(result["results"]) == 6
    audit = json.loads(batch.AUDIT_PATH.read_text())
    sitemap = ET.fromstring((ROOT / "sitemap.xml").read_text())
    locations = [v.text for v in sitemap.iter() if v.tag.endswith("}loc")]
    assert len(locations) == len(set(locations)), "Duplicate sitemap URLs"
    feed = (ROOT / "feed.xml").read_text()
    ET.fromstring(feed)
    indexes = (ROOT / "tutorials/index.html").read_text()
    for target in TARGETS:
        href = target["slug"] + "/"
        page = (ROOT / href / "index.html").read_text()
        entry = next(e for e in audit["entries"] if e.get("href") == href)
        canonical = batch.SITE["base_url"].rstrip("/") + "/" + href
        assert page.count('<link rel="canonical"') == 1
        assert f'href="{canonical}"' in page and canonical in locations and canonical in feed
        assert href in indexes and entry["category"] == target["category"]
        for needle in ["TechArticle", "SoftwareApplication", "BreadcrumbList", "og:image", "twitter:image", "data-nj-comments"]:
            assert needle in page, (href, needle)
        assert "noindex" not in page
        assert len(re.findall(r'<figure class="article-visual">', page)) >= 2
        for script in re.findall(r'<script type="application/ld\+json">(.*?)</script>', page, re.S): json.loads(script)
        print("PAGE PASS", href, flush=True)


def main():
    batch.build_source = build_source
    batch._slug = slug
    batch.generate_strict = generate
    batch._render_article = render
    # Detect identity duplicates even when an older URL used another spelling.
    audit = json.loads(batch.AUDIT_PATH.read_text())
    for target in TARGETS:
        for entry in audit.get("entries", []):
            if entry.get("package") == target["package_id"] and entry.get("version") == target["version"]:
                if entry.get("href") != target["slug"] + "/":
                    raise ValueError("Existing article identity at another URL: " + entry["href"])
    code = batch.main()
    result = json.loads((ROOT / "automation/batch-20260916-result.json").read_text())
    audit = json.loads(batch.AUDIT_PATH.read_text())
    for target in TARGETS:
        entry = next(e for e in audit["entries"] if e.get("href") == target["slug"] + "/")
        entry["category"] = target["category"]
        entry["selection_pool"] = "user-authorized-six-article-batch-20260921"
        if target.get("article_description"): entry["description"] = target["article_description"]
        if target.get("detail_media"): entry["additional_media"] = [target["detail_media"]]
    batch.AUDIT_PATH.write_text(json.dumps(audit, indent=2, ensure_ascii=False) + "\n")
    sync_editorial_indexes.main()
    # Render feeds again with corrected categories and descriptions.
    (ROOT / "feed.xml").write_text(batch._render_feed(audit["entries"], batch.SITE))
    REPORT.write_text(json.dumps(result, indent=2) + "\n")
    check()
    return code


if __name__ == "__main__":
    raise SystemExit(main())
