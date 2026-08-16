#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_DIR="$PROJECT_DIR/dist/LoopForge.app"
BUILD_MANIFEST="$APP_DIR/Contents/Resources/LoopForgeBuildManifest.json"
PROVIDER_HARNESS="$APP_DIR/Contents/MacOS/LoopForgeProviderHarness"
PROVIDER_HARNESS_MANIFEST="$APP_DIR/Contents/Resources/LoopForgeProviderHarnessManifest.json"

test -x "$APP_DIR/Contents/MacOS/LoopForge"
test -x "$APP_DIR/Contents/Resources/codex"
test -x "$APP_DIR/Contents/Resources/ollama-runtime/ollama"
test -x "$PROVIDER_HARNESS"
test -f "$BUILD_MANIFEST"
test -f "$PROVIDER_HARNESS_MANIFEST"
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
/usr/bin/plutil -p "$BUILD_MANIFEST" >/dev/null
/usr/bin/plutil -p "$PROVIDER_HARNESS_MANIFEST" >/dev/null
[[ "$(/usr/bin/plutil -extract protocolVersion raw "$PROVIDER_HARNESS_MANIFEST")" == "2" ]]
[[ "$(/usr/bin/plutil -extract operationalMode raw "$PROVIDER_HARNESS_MANIFEST")" == "transportVetoOnly" ]]
[[ "$(/usr/bin/plutil -extract productiveProviderBackends json -o - "$PROVIDER_HARNESS_MANIFEST")" == "[]" ]]
[[ "$(/usr/bin/plutil -extract releaseCapabilityClassification raw "$PROVIDER_HARNESS_MANIFEST")" == "nonProductiveTransportVeto" ]]
[[ "$(/usr/bin/plutil -extract productiveExecutionAvailable raw "$PROVIDER_HARNESS_MANIFEST")" == "false" ]]
[[ "$(/usr/bin/plutil -extract releaseCapabilityClassification raw "$BUILD_MANIFEST")" == "nonProductiveTransportVeto" ]]
[[ "$(/usr/bin/plutil -extract productiveExecutionAvailable raw "$BUILD_MANIFEST")" == "false" ]]
[[ "$(/usr/bin/plutil -extract providerHarnessOperationalMode raw "$BUILD_MANIFEST")" == "transportVetoOnly" ]]
EXPECTED_HARNESS_SHA="$(/usr/bin/plutil -extract executableSHA256 raw "$PROVIDER_HARNESS_MANIFEST")"
ACTUAL_HARNESS_SHA="$(/usr/bin/shasum -a 256 "$PROVIDER_HARNESS" | /usr/bin/awk '{print $1}')"
[[ "$ACTUAL_HARNESS_SHA" == "$EXPECTED_HARNESS_SHA" ]]
EXPECTED_HARNESS_BYTES="$(/usr/bin/plutil -extract executableByteCount raw "$PROVIDER_HARNESS_MANIFEST")"
[[ "$(/usr/bin/stat -f %z "$PROVIDER_HARNESS")" == "$EXPECTED_HARNESS_BYTES" ]]
HARNESS_SELF_TEST_TEMP="$(mktemp /tmp/loopforge-smoke-provider-self-test.XXXXXX)"
trap '/bin/rm -f "$HARNESS_SELF_TEST_TEMP"' EXIT
"$PROVIDER_HARNESS" --loopforge-provider-self-test > "$HARNESS_SELF_TEST_TEMP"
EXPECTED_HARNESS_SELF_TEST_SHA="$(/usr/bin/plutil -extract selfTestSHA256 raw "$PROVIDER_HARNESS_MANIFEST")"
ACTUAL_HARNESS_SELF_TEST_SHA="$(/usr/bin/shasum -a 256 "$HARNESS_SELF_TEST_TEMP" | /usr/bin/awk '{print $1}')"
[[ "$ACTUAL_HARNESS_SELF_TEST_SHA" == "$EXPECTED_HARNESS_SELF_TEST_SHA" ]]
EXPECTED_REVISION="$(git -C "$PROJECT_DIR" rev-parse HEAD)"
PACKAGED_REVISION="$(/usr/bin/plutil -extract sourceRevision raw "$BUILD_MANIFEST")"
[[ "$PACKAGED_REVISION" == "$EXPECTED_REVISION" ]]
EXPECTED_SNAPSHOT="$(zsh "$SCRIPT_DIR/source_snapshot.sh")"
PACKAGED_SNAPSHOT="$(/usr/bin/plutil -extract sourceSnapshotSHA256 raw "$BUILD_MANIFEST")"
if [[ "$PACKAGED_SNAPSHOT" != "$EXPECTED_SNAPSHOT" ]]; then
  print -u2 "Packaged LoopForge does not match the current source snapshot."
  exit 1
fi
TEST_LOG_PATH="$PROJECT_DIR/dist/LoopForge-package-tests.log"
test -f "$TEST_LOG_PATH"
EXPECTED_TEST_LOG_SHA="$(/usr/bin/plutil -extract testLogSHA256 raw "$BUILD_MANIFEST")"
ACTUAL_TEST_LOG_SHA="$(/usr/bin/shasum -a 256 "$TEST_LOG_PATH" | /usr/bin/awk '{print $1}')"
[[ "$ACTUAL_TEST_LOG_SHA" == "$EXPECTED_TEST_LOG_SHA" ]]
(
  cd "$PROJECT_DIR/dist"
  /usr/bin/shasum -a 256 -c SHA256SUMS
)
"$APP_DIR/Contents/Resources/codex" --version
"$APP_DIR/Contents/Resources/ollama-runtime/ollama" --version || true

# Static bundle checks can pass even when the packaged Mach-O aborts during
# startup. Execute the exact signed binary from the bundle and require it to
# remain alive across a bounded startup probe. The reusable probe is itself
# regression-tested with both a deliberately crashing executable and a live
# executable, including child-process cleanup.
zsh "$SCRIPT_DIR/probe_executable_startup.sh" \
  "$APP_DIR/Contents/MacOS/LoopForge" \
  --isolated-inspection-profile

print "Bundle and executable startup smoke test passed."
