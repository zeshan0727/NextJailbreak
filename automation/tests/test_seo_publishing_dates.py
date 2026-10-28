"""Regression checks for sitemap/RSS publication dates and legacy article metadata."""

import json
import unittest
from pathlib import Path
from xml.etree import ElementTree

from automation.publisher import _render_feed, _update_sitemap


BASE = "https://nextjailbreak.com"
SITEMAP_NS = "{http://www.sitemaps.org/schemas/sitemap/0.9}"


class SeoPublishingDateTests(unittest.TestCase):
    def setUp(self):
        self.site = {"site_name": "Next Jailbreak", "base_url": BASE}
        self.empty_sitemap = (
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"/>'
        )

    def test_legacy_published_timestamp_populates_sitemap_and_rss(self):
        old = {
            "href": "legacy-guide/",
            "title": "Legacy guide",
            "description": "A verified legacy guide.",
            "published": "2026-10-21T16:55:57Z",
            "category": {"label": "Guides"},
        }
        sitemap = ElementTree.fromstring(_update_sitemap(self.empty_sitemap, [old], self.site))
        page = sitemap.find(f"{SITEMAP_NS}url")
        self.assertEqual(page.find(f"{SITEMAP_NS}loc").text, BASE + "/legacy-guide/")
        self.assertEqual(page.find(f"{SITEMAP_NS}lastmod").text, "2026-10-21")
        feed = ElementTree.fromstring(_render_feed([old], self.site))
        self.assertEqual(feed.find("channel/item/pubDate").text, "Wed, 21 Oct 2026 16:55:57 GMT")

    def test_missing_timestamp_does_not_break_publication(self):
        undated = {"href": "undated/", "title": "Undated", "description": "Useful guide."}
        sitemap = ElementTree.fromstring(_update_sitemap(self.empty_sitemap, [undated], self.site))
        page = sitemap.find(f"{SITEMAP_NS}url")
        self.assertIsNone(page.find(f"{SITEMAP_NS}lastmod"))
        feed = ElementTree.fromstring(_render_feed([undated], self.site))
        self.assertIsNone(feed.find("channel/item/pubDate"))

    def test_every_audited_article_is_present_in_sitemap(self):
        root = Path(__file__).resolve().parents[2]
        articles = json.loads((root / "automation/published-articles.json").read_text(encoding="utf-8"))["entries"]
        original = (root / "sitemap.xml").read_text(encoding="utf-8")
        sitemap = ElementTree.fromstring(_update_sitemap(original, articles, self.site))
        urls = [node.text for node in sitemap.findall(f"{SITEMAP_NS}url/{SITEMAP_NS}loc")]
        self.assertEqual(len(urls), len(set(urls)), "Sitemap must not contain duplicates")
        for entry in articles:
            route = entry["href"]
            if route.endswith(".html"):
                route = route[:-5].rstrip("/") + "/"
            self.assertIn(BASE + "/" + route, urls, entry["href"])


if __name__ == "__main__":
    unittest.main()
