#!/usr/bin/env python3
"""Repair existing article SEO and harden every future article generator."""

from __future__ import annotations

from datetime import date
import html
import json
from pathlib import Path
import re
from xml.etree import ElementTree

from automation.seo_utils import seo_description, seo_title, semantic_jsonld

ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / "automation" / "published-articles.json"
SITE = ROOT / "automation" / "site.json"
SITEMAP = ROOT / "sitemap.xml"
SITEMAP_NS = "http://www.sitemaps.org/schemas/sitemap/0.9"
SEO_MARKER_START = "<!-- NEXTJAILBREAK_SEMANTIC_SEO_START -->"
SEO_MARKER_END = "<!-- NEXTJAILBREAK_SEMANTIC_SEO_END -->"


def replace_once(path: Path, old: str, new: str, label: str) -> bool:
    text = path.read_text(encoding="utf-8")
    if new in text:
        return False
    if old not in text:
        raise RuntimeError(f"{label}: expected source block not found in {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    return True


def patch_future_generators() -> list[str]:
    changed: list[str] = []

    publisher = ROOT / "automation" / "publisher.py"
    if replace_once(
        publisher,
        "from automation.source_media import (\n",
        "from automation.seo_utils import seo_description\nfrom automation.source_media import (\n",
        "publisher SEO import",
    ):
        changed.append(str(publisher.relative_to(ROOT)))
    replace_once(
        publisher,
        '        "description": article["meta_description"],\n        "href": target_path,',
        '        "description": seo_description(candidate["name"], candidate["version"]),\n        "href": target_path,',
        "publisher deterministic description",
    )
    old_sitemap = '''    existing: dict[str, ElementTree.Element] = {}\n    for node in root.findall(f"{{{SITEMAP_NAMESPACE}}}url"):\n        location = node.find(f"{{{SITEMAP_NAMESPACE}}}loc")\n        if location is not None and location.text:\n            existing[location.text] = node\n'''
    new_sitemap = '''    existing: dict[str, ElementTree.Element] = {}\n    # Clean historical duplicate sitemap rows before adding or updating articles.\n    for node in list(root.findall(f"{{{SITEMAP_NAMESPACE}}}url")):\n        location = node.find(f"{{{SITEMAP_NAMESPACE}}}loc")\n        if location is not None and location.text:\n            canonical_location = location.text.strip()\n            if canonical_location in existing:\n                root.remove(node)\n                continue\n            existing[canonical_location] = node\n'''
    replace_once(publisher, old_sitemap, new_sitemap, "publisher sitemap dedupe")

    draft = ROOT / "automation" / "draft_pipeline.py"
    replace_once(
        draft,
        "from automation.schemas import ARTICLE_SCHEMA, VERDICT_SCHEMA\n",
        "from automation.schemas import ARTICLE_SCHEMA, VERDICT_SCHEMA\nfrom automation.seo_utils import seo_description, seo_title, semantic_jsonld, suspicious_generated_metadata\n",
        "draft SEO import",
    )
    replace_once(
        draft,
        '''    meta_description = str(article.get("meta_description", ""))\n    if not 110 <= len(meta_description) <= 165:\n        issues.append("meta_description must contain 110-165 characters")\n''',
        '''    meta_description = str(article.get("meta_description", ""))\n    if not 110 <= len(meta_description) <= 165:\n        issues.append("meta_description must contain 110-165 characters")\n    if suspicious_generated_metadata(meta_description):\n        issues.append("meta_description contains malformed or suspicious generated text")\n''',
        "draft malformed metadata guard",
    )
    replace_once(
        draft,
        '''    category = candidate["category"]\n    if media:\n''',
        '''    category = candidate["category"]\n    seo_title_text = seo_title(candidate["name"], candidate["version"], site["site_name"])\n    seo_description_text = seo_description(candidate["name"], candidate["version"])\n    seo_semantic_jsonld = semantic_jsonld(\n        canonical=canonical, name=candidate["name"], version=candidate["version"],\n        site_url=base_url, section_url=f"{base_url}/tutorials/", section_name="Tweaks",\n    )\n    if media:\n''',
        "draft SEO variables",
    )
    replace_once(draft, '        "description": article["meta_description"],\n        "datePublished": published,', '        "description": seo_description_text,\n        "alternativeHeadline": seo_title_text.split(" | ", 1)[0],\n        "datePublished": published,', "draft structured SEO")
    replacements = {
        "  <title>{esc(article['title'])} | {esc(site['site_name'])}</title>": "  <title>{esc(seo_title_text)}</title>",
        "  <meta name=\"description\" content=\"{esc(article['meta_description'])}\">": "  <meta name=\"description\" content=\"{esc(seo_description_text)}\">",
        "  <meta property=\"og:title\" content=\"{esc(article['title'])}\">": "  <meta property=\"og:title\" content=\"{esc(seo_title_text)}\">",
        "  <meta property=\"og:description\" content=\"{esc(article['meta_description'])}\">": "  <meta property=\"og:description\" content=\"{esc(seo_description_text)}\">",
        "  <meta name=\"twitter:title\" content=\"{esc(article['title'])}\">": "  <meta name=\"twitter:title\" content=\"{esc(seo_title_text)}\">",
        "  <meta name=\"twitter:description\" content=\"{esc(article['meta_description'])}\">": "  <meta name=\"twitter:description\" content=\"{esc(seo_description_text)}\">",
        "  <script type=\"application/ld+json\">{json_ld_text}</script>": "  <script type=\"application/ld+json\">{json_ld_text}</script>\n  <script type=\"application/ld+json\">{seo_semantic_jsonld}</script>",
    }
    for old, new in replacements.items():
        replace_once(draft, old, new, f"draft renderer {old[:28]}")
    changed.append(str(draft.relative_to(ROOT)))

    ios = ROOT / "automation" / "ios_repo_news.py"
    replace_once(
        ios,
        "from automation.schemas import VERDICT_SCHEMA\n",
        "from automation.schemas import VERDICT_SCHEMA\nfrom automation.seo_utils import seo_description, seo_title, semantic_jsonld, suspicious_generated_metadata\n",
        "source-news SEO import",
    )
    replace_once(
        ios,
        '''    meta = str(article.get("meta_description", ""))\n    if not 110 <= len(meta) <= 165:\n        issues.append("meta description must be 110-165 characters")\n''',
        '''    meta = str(article.get("meta_description", ""))\n    if not 110 <= len(meta) <= 165:\n        issues.append("meta description must be 110-165 characters")\n    if suspicious_generated_metadata(meta):\n        issues.append("meta description contains malformed or suspicious generated text")\n''',
        "source-news malformed metadata guard",
    )
    replace_once(
        ios,
        '''    date = now.date().isoformat()\n    takeaways = "".join(f"<li>{esc(v)}</li>" for v in article["key_takeaways"])\n''',
        '''    date = now.date().isoformat()\n    seo_title_text = seo_title(source["name"], source.get("version", ""), site.get("site_name", "Next Jailbreak"))\n    seo_description_text = seo_description(source["name"], source.get("version", ""))\n    seo_semantic_jsonld = semantic_jsonld(\n        canonical=canonical, name=source["name"], version=source.get("version", ""),\n        site_url=base, section_url=f"{base}/tutorials/", section_name="Tweaks",\n    )\n    takeaways = "".join(f"<li>{esc(v)}</li>" for v in article["key_takeaways"])\n''',
        "source-news SEO variables",
    )
    replace_once(ios, '        "headline": article["title"], "description": article["meta_description"],', '        "headline": article["title"], "alternativeHeadline": seo_title_text.split(" | ", 1)[0], "description": seo_description_text,', "source-news structured SEO")
    ios_replacements = {
        "  <title>{esc(article['title'])} | Next Jailbreak</title>": "  <title>{esc(seo_title_text)}</title>",
        "  <meta name=\"description\" content=\"{esc(article['meta_description'])}\">": "  <meta name=\"description\" content=\"{esc(seo_description_text)}\">",
        "  <meta property=\"og:title\" content=\"{esc(article['title'])}\">": "  <meta property=\"og:title\" content=\"{esc(seo_title_text)}\">",
        "  <meta property=\"og:description\" content=\"{esc(article['meta_description'])}\">": "  <meta property=\"og:description\" content=\"{esc(seo_description_text)}\">",
        "  <meta name=\"twitter:title\" content=\"{esc(article['title'])}\">": "  <meta name=\"twitter:title\" content=\"{esc(seo_title_text)}\">",
        "  <meta name=\"twitter:description\" content=\"{esc(article['meta_description'])}\">": "  <meta name=\"twitter:description\" content=\"{esc(seo_description_text)}\">",
        "  <script type=\"application/ld+json\">{json.dumps(structured, ensure_ascii=False)}</script>": "  <script type=\"application/ld+json\">{json.dumps(structured, ensure_ascii=False)}</script>\n  <script type=\"application/ld+json\">{seo_semantic_jsonld}</script>",
    }
    for old, new in ios_replacements.items():
        replace_once(ios, old, new, f"source-news renderer {old[:28]}")
    replace_once(
        ios,
        '        "description": article["meta_description"],\n        "href": target_path,',
        '        "description": seo_description(selected_source["name"], version),\n        "href": target_path,',
        "source-news audit description",
    )
    changed.append(str(ios.relative_to(ROOT)))

    dopamine = ROOT / "automation" / "dopamine_cluster.py"
    replace_once(
        dopamine,
        "from automation.schemas import VERDICT_SCHEMA\n",
        "from automation.schemas import VERDICT_SCHEMA\nfrom automation.seo_utils import seo_description, seo_title, semantic_jsonld, suspicious_generated_metadata\n",
        "dopamine SEO import",
    )
    replace_once(
        dopamine,
        '''    meta = str(article.get("meta_description", ""))\n    if not 110 <= len(meta) <= 165:\n        issues.append("meta description must contain 110-165 characters")\n''',
        '''    meta = str(article.get("meta_description", ""))\n    if not 110 <= len(meta) <= 165:\n        issues.append("meta description must contain 110-165 characters")\n    if suspicious_generated_metadata(meta):\n        issues.append("meta description contains malformed or suspicious generated text")\n''',
        "dopamine malformed metadata guard",
    )
    replace_once(
        dopamine,
        '''    date = now.date().isoformat()\n    faq_entities = [\n''',
        '''    date = now.date().isoformat()\n    seo_title_text = seo_title("Dopamine 3", "", site.get("site_name", "Next Jailbreak"), kind="iOS Jailbreak Guide")\n    seo_description_text = seo_description("Dopamine 3", "", kind="iOS jailbreak guide")\n    seo_semantic_jsonld = semantic_jsonld(\n        canonical=canonical, name="Dopamine 3", version="", site_url=base,\n        section_url=f"{base}/tutorials/#jailbreak-guides", section_name="Jailbreak guides",\n    )\n    faq_entities = [\n''',
        "dopamine SEO variables",
    )
    replace_once(dopamine, '                "description": article["meta_description"],', '                "description": seo_description_text,\n                "alternativeHeadline": seo_title_text.split(" | ", 1)[0],', "dopamine structured SEO")
    dop_replacements = {
        "  <title>{esc(article['title'])} | Next Jailbreak</title>": "  <title>{esc(seo_title_text)}</title>",
        "  <meta name=\"description\" content=\"{esc(article['meta_description'])}\">": "  <meta name=\"description\" content=\"{esc(seo_description_text)}\">",
        "  <meta property=\"og:title\" content=\"{esc(article['title'])}\">": "  <meta property=\"og:title\" content=\"{esc(seo_title_text)}\">",
        "  <meta property=\"og:description\" content=\"{esc(article['meta_description'])}\">": "  <meta property=\"og:description\" content=\"{esc(seo_description_text)}\">",
        "  <meta name=\"twitter:title\" content=\"{esc(article['title'])}\">": "  <meta name=\"twitter:title\" content=\"{esc(seo_title_text)}\">",
        "  <meta name=\"twitter:description\" content=\"{esc(article['meta_description'])}\">": "  <meta name=\"twitter:description\" content=\"{esc(seo_description_text)}\">",
        "  <script type=\"application/ld+json\">{html.escape(json.dumps(structured, ensure_ascii=False), quote=False)}</script>": "  <script type=\"application/ld+json\">{html.escape(json.dumps(structured, ensure_ascii=False), quote=False)}</script>\n  <script type=\"application/ld+json\">{seo_semantic_jsonld}</script>",
    }
    for old, new in dop_replacements.items():
        replace_once(dopamine, old, new, f"dopamine renderer {old[:28]}")
    replace_once(
        dopamine,
        '        "description": article["meta_description"],\n        "href": target_path,',
        '        "description": seo_description("Dopamine 3", "", kind="iOS jailbreak guide"),\n        "href": target_path,',
        "dopamine audit description",
    )
    changed.append(str(dopamine.relative_to(ROOT)))
    return sorted(set(changed))


def set_meta(text: str, *, attr: str, key: str, value: str) -> str:
    pattern = re.compile(rf'<meta\s+{attr}=["\']{re.escape(key)}["\']\s+content=["\'][^"\']*["\']\s*/?>', re.I)
    tag = f'<meta {attr}="{key}" content="{html.escape(value, quote=True)}">'
    if pattern.search(text):
        return pattern.sub(tag, text, count=1)
    return text.replace("</head>", f"  {tag}\n</head>", 1)


def repair_article_page(path: Path, *, canonical: str, name: str, version: str, site_name: str, is_jailbreak: bool) -> bool:
    text = path.read_text(encoding="utf-8")
    original = text
    kind_title = "iOS Jailbreak Guide" if is_jailbreak else "iOS Jailbreak Tweak"
    kind_desc = "iOS jailbreak guide" if is_jailbreak else "iOS jailbreak tweak"
    title = seo_title(name, version if not is_jailbreak else "", site_name, kind=kind_title)
    description = seo_description(name, version if not is_jailbreak else "", kind=kind_desc)

    if re.search(r"<title>.*?</title>", text, re.I | re.S):
        text = re.sub(r"<title>.*?</title>", f"<title>{html.escape(title)}</title>", text, count=1, flags=re.I | re.S)
    text = set_meta(text, attr="name", key="description", value=description)
    text = set_meta(text, attr="property", key="og:title", value=title)
    text = set_meta(text, attr="property", key="og:description", value=description)
    text = set_meta(text, attr="name", key="twitter:title", value=title)
    text = set_meta(text, attr="name", key="twitter:description", value=description)
    text = set_meta(text, attr="name", key="robots", value="index,follow,max-image-preview:large")

    canonical_tag = f'<link rel="canonical" href="{html.escape(canonical, quote=True)}">'
    canonical_re = re.compile(r'<link\s+rel=["\']canonical["\']\s+href=["\'][^"\']+["\']\s*/?>', re.I)
    if canonical_re.search(text):
        text = canonical_re.sub(canonical_tag, text, count=1)
    else:
        text = text.replace("</head>", f"  {canonical_tag}\n</head>", 1)

    section_url = "https://nextjailbreak.com/tutorials/#jailbreak-guides" if is_jailbreak else "https://nextjailbreak.com/tutorials/"
    section_name = "Jailbreak guides" if is_jailbreak else "Tweaks"
    semantic = semantic_jsonld(
        canonical=canonical,
        name=name,
        version=version if not is_jailbreak else "",
        site_url="https://nextjailbreak.com",
        section_url=section_url,
        section_name=section_name,
    )
    block = f'{SEO_MARKER_START}\n  <script type="application/ld+json">{semantic}</script>\n  {SEO_MARKER_END}'
    block_re = re.compile(re.escape(SEO_MARKER_START) + r".*?" + re.escape(SEO_MARKER_END), re.S)
    if block_re.search(text):
        text = block_re.sub(block, text, count=1)
    else:
        text = text.replace("</head>", f"  {block}\n</head>", 1)

    if text != original:
        path.write_text(text, encoding="utf-8")
        return True
    return False


def rebuild_sitemap(audit: dict, site: dict, touched: set[str]) -> None:
    ElementTree.register_namespace("", SITEMAP_NS)
    root = ElementTree.fromstring(SITEMAP.read_text(encoding="utf-8"))
    seen: dict[str, ElementTree.Element] = {}
    for node in list(root.findall(f"{{{SITEMAP_NS}}}url")):
        loc = node.find(f"{{{SITEMAP_NS}}}loc")
        if loc is None or not loc.text:
            root.remove(node)
            continue
        key = loc.text.strip()
        if key in seen:
            root.remove(node)
            continue
        seen[key] = node

    base = str(site.get("base_url", "https://nextjailbreak.com")).rstrip("/")
    today = date.today().isoformat()
    for entry in audit.get("entries", []):
        if not isinstance(entry, dict) or not entry.get("href"):
            continue
        canonical = f"{base}/{str(entry['href']).lstrip('/')}"
        node = seen.get(canonical)
        if node is None:
            node = ElementTree.SubElement(root, f"{{{SITEMAP_NS}}}url")
            ElementTree.SubElement(node, f"{{{SITEMAP_NS}}}loc").text = canonical
            seen[canonical] = node
        lastmod = node.find(f"{{{SITEMAP_NS}}}lastmod")
        if lastmod is None:
            lastmod = ElementTree.SubElement(node, f"{{{SITEMAP_NS}}}lastmod")
        lastmod.text = today if canonical in touched else str(entry.get("modified_at") or entry.get("published_at") or today)[:10]
        changefreq = node.find(f"{{{SITEMAP_NS}}}changefreq")
        if changefreq is None:
            changefreq = ElementTree.SubElement(node, f"{{{SITEMAP_NS}}}changefreq")
        changefreq.text = "monthly"
        priority = node.find(f"{{{SITEMAP_NS}}}priority")
        if priority is None:
            priority = ElementTree.SubElement(node, f"{{{SITEMAP_NS}}}priority")
        priority.text = "0.8"

    ElementTree.indent(root, space="  ")
    SITEMAP.write_text('<?xml version="1.0" encoding="UTF-8"?>\n' + ElementTree.tostring(root, encoding="unicode") + "\n", encoding="utf-8")


def repair_existing_articles() -> tuple[int, int]:
    audit = json.loads(AUDIT.read_text(encoding="utf-8"))
    site = json.loads(SITE.read_text(encoding="utf-8"))
    base = str(site.get("base_url", "https://nextjailbreak.com")).rstrip("/")
    site_name = str(site.get("site_name", "Next Jailbreak"))
    repaired = 0
    missing = 0
    touched: set[str] = set()

    for entry in audit.get("entries", []):
        if not isinstance(entry, dict) or not entry.get("href"):
            continue
        href = str(entry["href"]).lstrip("/")
        page = ROOT / href
        if href.endswith("/"):
            page = page / "index.html"
        name = str(entry.get("name") or entry.get("title") or "Next Jailbreak").strip()
        version = str(entry.get("version") or "").strip()
        category = entry.get("category") if isinstance(entry.get("category"), dict) else {}
        is_jailbreak = str(category.get("id", "")).lower() == "jailbreak" or str(entry.get("entry_type", "")) == "cluster"
        description = seo_description(name, "" if is_jailbreak else version, kind="iOS jailbreak guide" if is_jailbreak else "iOS jailbreak tweak")
        entry["description"] = description
        if not page.exists():
            missing += 1
            continue
        canonical = f"{base}/{href}"
        if repair_article_page(page, canonical=canonical, name=name, version=version, site_name=site_name, is_jailbreak=is_jailbreak):
            repaired += 1
            touched.add(canonical)

    audit["updated_at"] = date.today().isoformat() + "T00:00:00+00:00"
    AUDIT.write_text(json.dumps(audit, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")
    rebuild_sitemap(audit, site, touched)
    return repaired, missing


def main() -> None:
    future = patch_future_generators()
    repaired, missing = repair_existing_articles()
    print(json.dumps({"future_generators_hardened": future, "existing_articles_repaired": repaired, "missing_article_files": missing}, indent=2))


if __name__ == "__main__":
    main()
