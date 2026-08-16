#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_DIR="$PROJECT_DIR/dist/LoopForge.app"
CONTENTS_DIR="$APP_DIR/Contents"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MACOS_DIR="$CONTENTS_DIR/MacOS"
CODEX_SOURCE="$PROJECT_DIR/.vendor/codex/codex"
OLLAMA_SOURCE="$PROJECT_DIR/.vendor/ollama"
HOST_RESOURCE_BROKER_SOURCE="$PROJECT_DIR/Resources/bin/loopforge-host-resource-broker"
SIGNING_IDENTITY="${LOOPFORGE_SIGNING_IDENTITY:--}"
RELEASE_VERSION="${LOOPFORGE_RELEASE_VERSION:-1.0.0}"
BUILD_NUMBER="${LOOPFORGE_BUILD_NUMBER:-100}"
TEST_LOG_TEMP="$(mktemp /tmp/loopforge-package-tests.XXXXXX)"
HARNESS_SELF_TEST_TEMP="$(mktemp /tmp/loopforge-provider-self-test.XXXXXX)"
DMG_STAGE=""
CHECKSUM_TMP=""
cleanup_package() {
  [[ -z "$DMG_STAGE" ]] || /bin/rm -rf "$DMG_STAGE"
  [[ -z "$CHECKSUM_TMP" ]] || /bin/rm -f "$CHECKSUM_TMP"
  /bin/rm -f "$TEST_LOG_TEMP" "$HARNESS_SELF_TEST_TEMP"
}
trap cleanup_package EXIT

if [[ ! -x "$CODEX_SOURCE" ]]; then
  print -u2 "Missing bundled Codex at $CODEX_SOURCE"
  exit 1
fi
if [[ ! -x "$OLLAMA_SOURCE/ollama" ]]; then
  print -u2 "Missing bundled Ollama at $OLLAMA_SOURCE/ollama"
  exit 1
fi
if [[ ! -x "$HOST_RESOURCE_BROKER_SOURCE" ]]; then
  print -u2 "Missing host-resource broker at $HOST_RESOURCE_BROKER_SOURCE"
  exit 1
fi

cd "$PROJECT_DIR"
swift test 2>&1 | /usr/bin/tee "$TEST_LOG_TEMP"
TEST_LOG_SHA256="$(/usr/bin/shasum -a 256 "$TEST_LOG_TEMP" | /usr/bin/awk '{print $1}')"
SOURCE_REVISION="$(git rev-parse HEAD)"
SOURCE_SNAPSHOT_SHA256="$(zsh "$SCRIPT_DIR/source_snapshot.sh")"
if [[ -n "$(git status --porcelain=v1 -- Package.swift README.md THIRD_PARTY_NOTICES.md Sources Tests/KernelProcessFixture Tests/LoopForgeTests Scripts Resources)" ]]; then
  SOURCE_DIRTY=true
else
  SOURCE_DIRTY=false
fi
swift build -c release --arch arm64 --product LoopForge
swift build -c release --arch arm64 --product KernelSandboxGate
swift build -c release --arch arm64 --product LoopForgeProviderHarness

/bin/rm -rf "$APP_DIR"
/bin/mkdir -p "$MACOS_DIR" "$RESOURCES_DIR/Licenses" "$RESOURCES_DIR/bin" "$PROJECT_DIR/dist"
/bin/cp "$PROJECT_DIR/.build/arm64-apple-macosx/release/LoopForge" "$MACOS_DIR/LoopForge"
/bin/cp "$PROJECT_DIR/.build/arm64-apple-macosx/release/KernelSandboxGate" "$MACOS_DIR/KernelSandboxGate"
/bin/chmod 755 "$MACOS_DIR/KernelSandboxGate"
/bin/cp "$PROJECT_DIR/.build/arm64-apple-macosx/release/LoopForgeProviderHarness" "$MACOS_DIR/LoopForgeProviderHarness"
/bin/chmod 755 "$MACOS_DIR/LoopForgeProviderHarness"
/bin/cp "$CODEX_SOURCE" "$RESOURCES_DIR/codex"
/usr/bin/ditto "$OLLAMA_SOURCE" "$RESOURCES_DIR/ollama-runtime"
/bin/cp "$PROJECT_DIR/.vendor/codex/LICENSE" "$RESOURCES_DIR/Licenses/Codex-Apache-2.0.txt"
/bin/cp "$PROJECT_DIR/.vendor/ollama/LICENSE" "$RESOURCES_DIR/Licenses/Ollama-MIT.txt"
/bin/cp "$PROJECT_DIR/THIRD_PARTY_NOTICES.md" "$RESOURCES_DIR/THIRD_PARTY_NOTICES.md"
/bin/cp "$HOST_RESOURCE_BROKER_SOURCE" "$RESOURCES_DIR/bin/loopforge-host-resource-broker"
/bin/chmod 755 "$RESOURCES_DIR/bin/loopforge-host-resource-broker"

# Nested Mach-O identities must be final before their manifest hashes are
# captured. The enclosing bundle signature is added later without recursively
# rewriting these bytes.
/usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none \
  "$MACOS_DIR/KernelSandboxGate"
/usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none \
  "$MACOS_DIR/LoopForgeProviderHarness"

EXPECTED_HARNESS_SELF_TEST='{"credentialTransport":"length-prefixed-fd-197","invocationContextTransport":"canonical-json-fd-196","operationalMode":"transport-veto-only","productiveProviderBackends":[],"promptTransport":"exact-stdin","protocolVersion":2,"schemaVersion":1}'
"$MACOS_DIR/LoopForgeProviderHarness" \
  --loopforge-provider-self-test > "$HARNESS_SELF_TEST_TEMP"
ACTUAL_HARNESS_SELF_TEST="$(<"$HARNESS_SELF_TEST_TEMP")"
if [[ "$ACTUAL_HARNESS_SELF_TEST" != "$EXPECTED_HARNESS_SELF_TEST" \
      || "$(/usr/bin/wc -l < "$HARNESS_SELF_TEST_TEMP" | /usr/bin/tr -d ' ')" != "1" ]]; then
  print -u2 "Packaged provider harness self-test is not the ratified canonical payload."
  exit 1
fi
HARNESS_SHA256="$(/usr/bin/shasum -a 256 "$MACOS_DIR/LoopForgeProviderHarness" | /usr/bin/awk '{print $1}')"
HARNESS_BYTE_COUNT="$(/usr/bin/stat -f %z "$MACOS_DIR/LoopForgeProviderHarness")"
HARNESS_SELF_TEST_SHA256="$(/usr/bin/shasum -a 256 "$HARNESS_SELF_TEST_TEMP" | /usr/bin/awk '{print $1}')"
PROVIDER_HARNESS_MANIFEST="$RESOURCES_DIR/LoopForgeProviderHarnessManifest.json"
/usr/bin/plutil -create xml1 "$PROVIDER_HARNESS_MANIFEST"
/usr/bin/plutil -insert schemaVersion -integer 1 "$PROVIDER_HARNESS_MANIFEST"
/usr/bin/plutil -insert protocolVersion -integer 2 "$PROVIDER_HARNESS_MANIFEST"
/usr/bin/plutil -insert executableFileName -string LoopForgeProviderHarness "$PROVIDER_HARNESS_MANIFEST"
/usr/bin/plutil -insert executableSHA256 -string "$HARNESS_SHA256" "$PROVIDER_HARNESS_MANIFEST"
/usr/bin/plutil -insert executableByteCount -integer "$HARNESS_BYTE_COUNT" "$PROVIDER_HARNESS_MANIFEST"
/usr/bin/plutil -insert operationalMode -string transportVetoOnly "$PROVIDER_HARNESS_MANIFEST"
/usr/bin/plutil -insert productiveProviderBackends -array "$PROVIDER_HARNESS_MANIFEST"
/usr/bin/plutil -insert releaseCapabilityClassification -string nonProductiveTransportVeto "$PROVIDER_HARNESS_MANIFEST"
/usr/bin/plutil -insert productiveExecutionAvailable -bool false "$PROVIDER_HARNESS_MANIFEST"
/usr/bin/plutil -insert selfTestSHA256 -string "$HARNESS_SELF_TEST_SHA256" "$PROVIDER_HARNESS_MANIFEST"
/usr/bin/plutil -convert json "$PROVIDER_HARNESS_MANIFEST"

if /usr/bin/find "$RESOURCES_DIR" -type f \( -iname "*.gguf" -o -iname "*.safetensors" -o -iname "*.bin" \) -print -quit | /usr/bin/grep -q .; then
  print -u2 "Model weights must never be bundled. Local models are user-confirmed downloads."
  exit 1
fi
if /usr/bin/find "$RESOURCES_DIR" -type d \( -name "Models" -o -name "blobs" -o -name "manifests" \) -print -quit | /usr/bin/grep -q .; then
  print -u2 "Ollama model storage must never be copied into the app bundle."
  exit 1
fi

/usr/bin/plutil -create xml1 "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleDevelopmentRegion -string en "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleDisplayName -string LoopForge "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleExecutable -string LoopForge "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleIdentifier -string com.loopforge.autocoder "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleInfoDictionaryVersion -string 6.0 "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleName -string LoopForge "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundlePackageType -string APPL "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleShortVersionString -string "$RELEASE_VERSION" "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleVersion -string "$BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert LSMinimumSystemVersion -string 14.0 "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert LSApplicationCategoryType -string public.app-category.developer-tools "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert NSHighResolutionCapable -bool true "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert NSSupportsAutomaticGraphicsSwitching -bool true "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert NSScreenCaptureUsageDescription -string "LoopForge captures project UI evidence so its local visual supervisor can verify official Codex work before delivery." "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert NSPhotoLibraryUsageDescription -string "LoopForge accesses Photos only when a Full Access task explicitly requires the system photo library." "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert NSPhotoLibraryAddUsageDescription -string "LoopForge saves generated media to Photos only when the task explicitly requests it." "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert NSCameraUsageDescription -string "LoopForge permits a Full Access task to use the camera only when explicitly required by the task." "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert NSMicrophoneUsageDescription -string "LoopForge permits a Full Access task to use the microphone only when explicitly required by the task." "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert NSLocalNetworkUsageDescription -string "LoopForge connects to local model runtimes and task-selected development services on your network." "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert NSAppBundlesUsageDescription -string "LoopForge lets official Codex build, update, test, and package application bundles selected by you." "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert NSAppleEventsUsageDescription -string "LoopForge may automate developer tools you choose while verifying a project." "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert NSAppTransportSecurity -dictionary "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert NSAppTransportSecurity.NSAllowsLocalNetworking -bool true "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert NSHumanReadableCopyright -string "LoopForge 2026 · Bundled components retain their respective licenses" "$CONTENTS_DIR/Info.plist"

BUILD_MANIFEST="$RESOURCES_DIR/LoopForgeBuildManifest.json"
/usr/bin/plutil -create xml1 "$BUILD_MANIFEST"
/usr/bin/plutil -insert schemaVersion -integer 1 "$BUILD_MANIFEST"
/usr/bin/plutil -insert sourceRevision -string "$SOURCE_REVISION" "$BUILD_MANIFEST"
/usr/bin/plutil -insert sourceSnapshotSHA256 -string "$SOURCE_SNAPSHOT_SHA256" "$BUILD_MANIFEST"
/usr/bin/plutil -insert sourceDirty -bool "$SOURCE_DIRTY" "$BUILD_MANIFEST"
/usr/bin/plutil -insert testLogSHA256 -string "$TEST_LOG_SHA256" "$BUILD_MANIFEST"
/usr/bin/plutil -insert builtAtUTC -string "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)" "$BUILD_MANIFEST"
/usr/bin/plutil -insert releaseVersion -string "$RELEASE_VERSION" "$BUILD_MANIFEST"
/usr/bin/plutil -insert buildNumber -string "$BUILD_NUMBER" "$BUILD_MANIFEST"
/usr/bin/plutil -insert releaseCapabilityClassification -string nonProductiveTransportVeto "$BUILD_MANIFEST"
/usr/bin/plutil -insert productiveExecutionAvailable -bool false "$BUILD_MANIFEST"
/usr/bin/plutil -insert providerHarnessOperationalMode -string transportVetoOnly "$BUILD_MANIFEST"
/usr/bin/plutil -convert json "$BUILD_MANIFEST"

ICON_WORK="$PROJECT_DIR/.build/LoopForge.icon-work"
/bin/rm -rf "$ICON_WORK"
/bin/mkdir -p "$ICON_WORK/AppIcon.iconset"
/usr/bin/xcrun swift "$SCRIPT_DIR/make_icon.swift" "$ICON_WORK/icon-1024.png"
for spec in "16:16x16" "32:16x16@2x" "32:32x32" "64:32x32@2x" "128:128x128" "256:128x128@2x" "256:256x256" "512:256x256@2x" "512:512x512" "1024:512x512@2x"; do
  pixels="${spec%%:*}"
  name="${spec#*:}"
  /usr/bin/sips -z "$pixels" "$pixels" "$ICON_WORK/icon-1024.png" --out "$ICON_WORK/AppIcon.iconset/icon_${name}.png" >/dev/null
done
/usr/bin/iconutil -c icns "$ICON_WORK/AppIcon.iconset" -o "$RESOURCES_DIR/AppIcon.icns"
/usr/bin/plutil -insert CFBundleIconFile -string AppIcon "$CONTENTS_DIR/Info.plist"

/usr/bin/xattr -cr "$APP_DIR"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  print -u2 "Warning: ad-hoc signing is build-specific. macOS privacy grants may need to be confirmed again after rebuilding."
fi
/usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$APP_DIR"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR"

ZIP_PATH="$PROJECT_DIR/dist/LoopForge-macOS-arm64.zip"
/bin/rm -f "$ZIP_PATH"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

DMG_PATH="$PROJECT_DIR/dist/LoopForge-${RELEASE_VERSION}-arm64.dmg"
DMG_STAGE="$(mktemp -d /tmp/loopforge-dmg.XXXXXX)"
CHECKSUM_PATH="$PROJECT_DIR/dist/SHA256SUMS"
CHECKSUM_TMP="$PROJECT_DIR/dist/.SHA256SUMS.tmp.$$"
TEST_LOG_PATH="$PROJECT_DIR/dist/LoopForge-package-tests.log"
/bin/cp "$TEST_LOG_TEMP" "$TEST_LOG_PATH"
/usr/bin/ditto "$APP_DIR" "$DMG_STAGE/LoopForge.app"
/bin/ln -s /Applications "$DMG_STAGE/Applications"
/bin/rm -f "$DMG_PATH"
/usr/bin/hdiutil create \
  -volname "LoopForge" \
  -srcfolder "$DMG_STAGE" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

checksum_artifacts=("${ZIP_PATH:t}" "${DMG_PATH:t}" "${TEST_LOG_PATH:t}")
# This packaging invocation produces the application ZIP and DMG. Pre-existing
# optional source archives may describe another revision, so they must not be
# silently promoted into this release's checksum manifest. A source release
# needs its own revision-bound generation and verification step.
(
  cd "$PROJECT_DIR/dist"
  /usr/bin/shasum -a 256 "${checksum_artifacts[@]}"
) > "$CHECKSUM_TMP"
/bin/mv -f "$CHECKSUM_TMP" "$CHECKSUM_PATH"

print "Built: $APP_DIR"
print "Archive: $ZIP_PATH"
print "Disk image: $DMG_PATH"
print "Checksums: $CHECKSUM_PATH"
du -sh "$APP_DIR" "$ZIP_PATH" "$DMG_PATH"
