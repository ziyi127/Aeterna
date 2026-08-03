#!/usr/bin/env python3
"""Dependency-free consistency checks for the Aeterna static site."""
from __future__ import annotations

import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HTML_FILES = [ROOT / "index.html", ROOT / "privacy.html", ROOT / "en/index.html", ROOT / "en/privacy.html"]
RELEASE_DATA = ROOT / "assets/data/release.json"

class SiteParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids: set[str] = set()
        self.hrefs: list[str] = []
    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if values.get("id"):
            self.ids.add(values["id"])
        if tag in {"a", "link"} and values.get("href"):
            self.hrefs.append(values["href"])

def fail(message: str) -> None:
    print(f"FAIL: {message}")
    raise SystemExit(1)

for page in HTML_FILES:
    if not page.is_file():
        fail(f"missing required page: {page.relative_to(ROOT)}")
    text = page.read_text(encoding="utf-8")
    if "<main" not in text or "id=\"main-content\"" not in text:
        fail(f"{page.relative_to(ROOT)} lacks main landmark")
    if "<meta name=\"description\"" not in text or "rel=\"canonical\"" not in text:
        fail(f"{page.relative_to(ROOT)} lacks SEO metadata")
    parser = SiteParser()
    parser.feed(text)
    for href in parser.hrefs:
        if href.startswith("#") and href[1:] not in parser.ids:
            fail(f"{page.relative_to(ROOT)} links to missing anchor {href}")
        if href.startswith(("http://", "https://", "mailto:", "data:")) or href.startswith("#"):
            continue
        target = (page.parent / href.split("#", 1)[0]).resolve()
        if not target.is_file() and not target.is_dir():
            fail(f"{page.relative_to(ROOT)} references missing local target {href}")

home = (ROOT / "index.html").read_text(encoding="utf-8")
english = (ROOT / "en/index.html").read_text(encoding="utf-8")
if not RELEASE_DATA.is_file():
    fail("release metadata is missing")
release = json.loads(RELEASE_DATA.read_text(encoding="utf-8"))
for page_name, text in (("Chinese home", home), ("English home", english)):
    if release["url"] not in text and "releases" not in text:
        fail(f"{page_name} does not contain a release link")
for asset_url in release["assets"].values():
    if not asset_url.startswith("https://github.com/ziyi127/Aeterna/releases/download/"):
        fail(f"release asset URL is not an official GitHub download: {asset_url}")

css = (ROOT / "assets/css/styles.css").read_text(encoding="utf-8")
for forbidden in ("_entry", "separates", "top: / 5px"):
    if forbidden in css:
        fail(f"stylesheet contains known invalid token: {forbidden}")
if not (ROOT / "robots.txt").is_file() or not (ROOT / "sitemap.xml").is_file():
    fail("robots.txt or sitemap.xml is missing")

sitemap = (ROOT / "sitemap.xml").read_text(encoding="utf-8")
for url in ("https://aeterna.dpdns.org/", "https://aeterna.dpdns.org/en/", "https://aeterna.dpdns.org/privacy.html", "https://aeterna.dpdns.org/en/privacy.html"):
    if url not in sitemap:
        fail(f"sitemap is missing {url}")

print("Static site consistency checks passed.")
