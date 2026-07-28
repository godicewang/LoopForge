#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_DIR="$PROJECT_DIR/dist/LoopForge.app"

test -x "$APP_DIR/Contents/MacOS/LoopForge"
test -x "$APP_DIR/Contents/Resources/codex"
test -x "$APP_DIR/Contents/Resources/ollama-runtime/ollama"
if /usr/bin/find "$APP_DIR/Contents/Resources" -type f \( -iname "*.gguf" -o -iname "*.safetensors" -o -iname "*.bin" \) -print -quit | /usr/bin/grep -q .; then
  print -u2 "Packaged app unexpectedly contains local model weights."
  exit 1
fi
if /usr/bin/find "$APP_DIR/Contents/Resources" -type d \( -name "Models" -o -name "blobs" -o -name "manifests" \) -print -quit | /usr/bin/grep -q .; then
  print -u2 "Packaged app unexpectedly contains Ollama model storage."
  exit 1
fi
/usr/bin/codesign --verify --deep --strict "$APP_DIR"
/usr/bin/plutil -lint "$APP_DIR/Contents/Info.plist"
"$APP_DIR/Contents/Resources/codex" --version
"$APP_DIR/Contents/Resources/ollama-runtime/ollama" --version || true

print "Bundle smoke test passed."
