#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/.vendor"

CODEX_VERSION="0.145.0-alpha.30"
CODEX_ARCHIVE="codex-aarch64-apple-darwin.tar.gz"
CODEX_URL="https://github.com/openai/codex/releases/download/rust-v${CODEX_VERSION}/${CODEX_ARCHIVE}"
CODEX_SHA256="0f6ae53408db3166e511a925de9b714895eab86abb76c6d4a843095bda705c50"
CODEX_LICENSE_URL="https://raw.githubusercontent.com/openai/codex/rust-v${CODEX_VERSION}/LICENSE"
CODEX_LICENSE_SHA256="d17f227e4df5da1600391338865ce0f3055211760a36688f816941d58232d8dc"

OLLAMA_VERSION="0.32.0"
OLLAMA_ARCHIVE="ollama-darwin.tgz"
OLLAMA_URL="https://github.com/ollama/ollama/releases/download/v${OLLAMA_VERSION}/${OLLAMA_ARCHIVE}"
OLLAMA_SHA256="3b12a49c6c4cbafd7ffba5ccba60cbf80274cdc22eea3ead79c646aba888174c"
OLLAMA_LICENSE_URL="https://raw.githubusercontent.com/ollama/ollama/v${OLLAMA_VERSION}/LICENSE"
OLLAMA_LICENSE_SHA256="5934ed2ce0d15154bcdb9c85203210abac0da4314af34081e36df4599f90b226"

TEMP_DIR="$(mktemp -d /tmp/loopforge-vendor.XXXXXX)"
trap '/bin/rm -rf "$TEMP_DIR"' EXIT

download_and_verify() {
  local url="$1"
  local destination="$2"
  local expected_sha="$3"

  /usr/bin/curl --fail --location --retry 3 --retry-delay 2 \
    --output "$destination" "$url"
  local actual_sha
  actual_sha="$(/usr/bin/shasum -a 256 "$destination" | /usr/bin/awk '{print $1}')"
  if [[ "$actual_sha" != "$expected_sha" ]]; then
    print -u2 "Checksum mismatch for $url"
    print -u2 "Expected: $expected_sha"
    print -u2 "Actual:   $actual_sha"
    return 1
  fi
}

print "Downloading verified Codex ${CODEX_VERSION}…"
download_and_verify "$CODEX_URL" "$TEMP_DIR/$CODEX_ARCHIVE" "$CODEX_SHA256"
download_and_verify "$CODEX_LICENSE_URL" "$TEMP_DIR/CODEX-LICENSE" "$CODEX_LICENSE_SHA256"
/usr/bin/tar -xzf "$TEMP_DIR/$CODEX_ARCHIVE" -C "$TEMP_DIR"

print "Downloading verified Ollama ${OLLAMA_VERSION}…"
download_and_verify "$OLLAMA_URL" "$TEMP_DIR/$OLLAMA_ARCHIVE" "$OLLAMA_SHA256"
download_and_verify "$OLLAMA_LICENSE_URL" "$TEMP_DIR/OLLAMA-LICENSE" "$OLLAMA_LICENSE_SHA256"
/bin/mkdir -p "$TEMP_DIR/ollama"
/usr/bin/tar -xzf "$TEMP_DIR/$OLLAMA_ARCHIVE" -C "$TEMP_DIR/ollama"

/bin/rm -rf "$VENDOR_DIR/codex" "$VENDOR_DIR/ollama"
/bin/mkdir -p "$VENDOR_DIR/codex" "$VENDOR_DIR/ollama"
/bin/cp "$TEMP_DIR/codex-aarch64-apple-darwin" "$VENDOR_DIR/codex/codex"
/bin/cp "$TEMP_DIR/CODEX-LICENSE" "$VENDOR_DIR/codex/LICENSE"
/bin/cp -R "$TEMP_DIR/ollama/." "$VENDOR_DIR/ollama/"
/bin/cp "$TEMP_DIR/OLLAMA-LICENSE" "$VENDOR_DIR/ollama/LICENSE"
/bin/chmod +x "$VENDOR_DIR/codex/codex" "$VENDOR_DIR/ollama/ollama"

print "Vendor runtimes installed and verified:"
"$VENDOR_DIR/codex/codex" --version
"$VENDOR_DIR/ollama/ollama" --version
