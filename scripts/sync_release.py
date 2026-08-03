#!/usr/bin/env python3
"""Generate release metadata consumed by the static site."""
from __future__ import annotations

import json
import os
import urllib.request
from pathlib import Path

root = Path(__file__).resolve().parents[1]
api_url = os.environ.get("AETERNA_RELEASE_API", "https://api.github.com/repos/ziyi127/Aeterna/releases/latest")
request = urllib.request.Request(api_url, headers={"Accept": "application/vnd.github+json", "User-Agent": "aeterna-site-release-sync"})
with urllib.request.urlopen(request, timeout=20) as response:
    release = json.load(response)

assets = {asset["name"]: asset["browser_download_url"] for asset in release.get("assets", [])}
required = {"aeterna.exe", "aeterna-arm64-macos", "aeterna-x86_64-linux"}
missing = required - assets.keys()
if missing:
    raise SystemExit(f"Missing release assets: {', '.join(sorted(missing))}")

metadata = {
    "version": release["tag_name"].removeprefix("v"),
    "tag": release["tag_name"],
    "url": release["html_url"],
    "assets": {name: assets[name] for name in sorted(required)},
}
(root / "assets/data").mkdir(parents=True, exist_ok=True)
(root / "assets/data/release.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"Wrote {root / 'assets/data/release.json'} for {release['tag_name']}")
