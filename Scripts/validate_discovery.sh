#!/bin/zsh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITE_DIR="$REPO_ROOT/docs"

python3 - "$REPO_ROOT" <<'PY'
import json
import pathlib
import re
import sys
import urllib.parse
import xml.etree.ElementTree as ET

root = pathlib.Path(sys.argv[1])
site = root / "docs"
html_path = site / "index.html"
html = html_path.read_text(encoding="utf-8")

required_fragments = [
    "<title>LoopForge — Autonomous Coding Agent Loops for macOS</title>",
    'rel="canonical" href="https://godicewang.github.io/LoopForge/"',
    'property="og:image"',
    'name="twitter:card" content="summary_large_image"',
    'type="application/ld+json"',
    'name="description"',
]
missing = [fragment for fragment in required_fragments if fragment not in html]
if missing:
    raise SystemExit(f"Missing discovery metadata: {missing}")

json_ld_match = re.search(
    r'<script type="application/ld\+json">\s*(.*?)\s*</script>',
    html,
    flags=re.DOTALL,
)
if not json_ld_match:
    raise SystemExit("JSON-LD block is missing")
json.loads(json_ld_match.group(1))

with (root / "codemeta.json").open(encoding="utf-8") as handle:
    codemeta = json.load(handle)
if codemeta.get("@type") != "SoftwareSourceCode":
    raise SystemExit("codemeta.json must describe SoftwareSourceCode")
if codemeta.get("codeRepository") != "https://github.com/godicewang/LoopForge.git":
    raise SystemExit("CodeMeta repository URL drifted")

ET.parse(site / "sitemap.xml")

local_refs = set()
for attribute, target in re.findall(r'\b(src|href)="([^"]+)"', html):
    if target.startswith(("#", "http://", "https://", "mailto:")):
        continue
    path = urllib.parse.urlparse(target).path
    if not path:
        continue
    local_refs.add(path)

missing_refs = []
for relative in sorted(local_refs):
    candidate = site / relative
    if relative.endswith("/"):
        candidate = candidate / "index.html"
    if not candidate.exists():
        missing_refs.append(relative)
if missing_refs:
    raise SystemExit(f"Broken local landing-page references: {missing_refs}")

robots = (site / "robots.txt").read_text(encoding="utf-8")
if "OAI-SearchBot" not in robots or "/LoopForge/sitemap.xml" not in robots:
    raise SystemExit("robots.txt is missing its AI search or sitemap declaration")

llms = (site / "llms.txt").read_text(encoding="utf-8")
if "https://github.com/godicewang/LoopForge" not in llms:
    raise SystemExit("llms.txt is missing the canonical repository")

print(f"Discovery metadata valid; {len(local_refs)} local references resolved")
PY

SOCIAL_WIDTH="$(sips -g pixelWidth "$SITE_DIR/assets/social-preview.png" 2>/dev/null | awk '/pixelWidth/{print $2}')"
SOCIAL_HEIGHT="$(sips -g pixelHeight "$SITE_DIR/assets/social-preview.png" 2>/dev/null | awk '/pixelHeight/{print $2}')"
SOCIAL_BYTES="$(stat -f '%z' "$SITE_DIR/assets/social-preview.png")"

if [[ "$SOCIAL_WIDTH" != "1280" || "$SOCIAL_HEIGHT" != "640" ]]; then
  print -u2 "Social preview must remain 1280 × 640; found ${SOCIAL_WIDTH} × ${SOCIAL_HEIGHT}"
  exit 1
fi

if (( SOCIAL_BYTES >= 1000000 )); then
  print -u2 "Social preview must remain under GitHub's 1 MB limit"
  exit 1
fi

print "Social preview valid: ${SOCIAL_WIDTH} × ${SOCIAL_HEIGHT}, ${SOCIAL_BYTES} bytes"
