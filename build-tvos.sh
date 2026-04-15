#!/usr/bin/env bash
set -euo pipefail

TEAM_ID="${TEAM_ID:-}"
MODE="${MODE:-app-store}"
WORKSPACE="${WORKSPACE:-Moonfin.xcworkspace}"
SCHEME="${SCHEME:-Moonfin}"
CONFIGURATION="${CONFIGURATION:-Release}"
ALLOW_PROVISIONING_UPDATES="${ALLOW_PROVISIONING_UPDATES:-0}"
EXPORT_OPTIONS_PLIST="${EXPORT_OPTIONS_PLIST:-}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Moonfin"

if [ "$#" -gt 0 ]; then
  echo "Error: this script does not accept positional arguments." >&2
  echo "Run: ./build-tvos.sh" >&2
  exit 1
fi

PRIVATE_ENV_FILE="$REPO_ROOT/build-tvos.private.env"
if [ -f "$PRIVATE_ENV_FILE" ]; then
  source "$PRIVATE_ENV_FILE"
fi

if [ -z "$TEAM_ID" ]; then
  echo "Error: TEAM_ID is required for signing." >&2
  echo "Set TEAM_ID in build-tvos.private.env or pass TEAM_ID=... when running." >&2
  exit 1
fi

case "$MODE" in
  sideload)
    EXPORT_METHOD="development"
    ;;
  app-store)
    EXPORT_METHOD="app-store-connect"
    ;;
  *)
    echo "Error: MODE must be one of: sideload, app-store" >&2
    exit 1
    ;;
esac

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Error: required command not found: xcodebuild" >&2
  exit 1
fi

if ! command -v unzip >/dev/null 2>&1 || ! command -v zip >/dev/null 2>&1; then
  echo "Error: required commands not found: unzip and zip" >&2
  exit 1
fi

APP_VERSION=$(grep 'MARKETING_VERSION:' "$REPO_ROOT/project.yml" | sed 's/.*MARKETING_VERSION:[[:space:]]*//' | tr -d '"[:space:]')
BUILD_NUMBER=$(grep 'CURRENT_PROJECT_VERSION:' "$REPO_ROOT/project.yml" | sed 's/.*CURRENT_PROJECT_VERSION:[[:space:]]*//' | tr -d '"[:space:]')

if [ -z "$APP_VERSION" ]; then
  echo "Error: could not read MARKETING_VERSION from project.yml" >&2
  exit 1
fi
if [ -z "$BUILD_NUMBER" ]; then
  echo "Error: could not read CURRENT_PROJECT_VERSION from project.yml" >&2
  exit 1
fi

ARCHIVE_PATH="$REPO_ROOT/build/tvos/archive/${APP_NAME}.xcarchive"
EXPORT_DIR="$REPO_ROOT/build/tvos/ipa"
EXPORT_OPTIONS_PLIST_GEN="$REPO_ROOT/build/tvos/ExportOptions-${MODE}.plist"
UNSIGNED_IPA="$REPO_ROOT/${APP_NAME}_tvOS_${APP_VERSION}.ipa"
SIGNED_IPA="$REPO_ROOT/${APP_NAME}_tvOS_${APP_VERSION}_signed.ipa"

echo "${APP_NAME} version: ${APP_VERSION} (${BUILD_NUMBER})"

cd "$REPO_ROOT"

echo "Cleaning previous archive and IPA outputs..."
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"
rm -f "$UNSIGNED_IPA" "$SIGNED_IPA"
mkdir -p "$EXPORT_DIR"

echo "Creating archive with xcodebuild archive..."
ARCHIVE_CMD=(
  xcodebuild
  -workspace "$WORKSPACE"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "generic/platform=tvOS"
  -archivePath "$ARCHIVE_PATH"
  CODE_SIGN_STYLE=Automatic
  DEVELOPMENT_TEAM="$TEAM_ID"
  MARKETING_VERSION="$APP_VERSION"
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
  archive
)
if [ "$ALLOW_PROVISIONING_UPDATES" = "1" ]; then
  ARCHIVE_CMD+=( -allowProvisioningUpdates )
fi
"${ARCHIVE_CMD[@]}"

if [ -n "$EXPORT_OPTIONS_PLIST" ] && [[ "$EXPORT_OPTIONS_PLIST" != /* ]]; then
  EXPORT_OPTIONS_PLIST="$REPO_ROOT/$EXPORT_OPTIONS_PLIST"
fi

if [ -n "$EXPORT_OPTIONS_PLIST" ] && [ ! -f "$EXPORT_OPTIONS_PLIST" ]; then
  echo "Error: EXPORT_OPTIONS_PLIST not found: $EXPORT_OPTIONS_PLIST" >&2
  exit 1
fi

if [ -z "$EXPORT_OPTIONS_PLIST" ]; then
  echo "Writing export options plist..."
  {
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    echo '<plist version="1.0">'
    echo '<dict>'
    echo '  <key>method</key>'
    echo "  <string>${EXPORT_METHOD}</string>"
    echo '  <key>destination</key>'
    echo '  <string>export</string>'
    echo '  <key>signingStyle</key>'
    echo '  <string>automatic</string>'
    echo '  <key>teamID</key>'
    echo "  <string>${TEAM_ID}</string>"
    echo '  <key>stripSwiftSymbols</key>'
    echo '  <true/>'
    echo '  <key>compileBitcode</key>'
    echo '  <false/>'
    echo '</dict>'
    echo '</plist>'
  } > "$EXPORT_OPTIONS_PLIST_GEN"
  EXPORT_OPTIONS_PLIST="$EXPORT_OPTIONS_PLIST_GEN"
fi

echo "Exporting IPA (mode: $MODE, method: $EXPORT_METHOD)..."
EXPORT_CMD=(
  xcodebuild
  -exportArchive
  -archivePath "$ARCHIVE_PATH"
  -exportPath "$EXPORT_DIR"
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"
)
if [ "$ALLOW_PROVISIONING_UPDATES" = "1" ]; then
  EXPORT_CMD+=( -allowProvisioningUpdates )
fi
"${EXPORT_CMD[@]}"

IPA_PATH="$(find "$EXPORT_DIR" -maxdepth 1 -type f -name '*.ipa' | head -n 1)"
if [ -z "$IPA_PATH" ]; then
  echo "Error: export completed but no .ipa found in $EXPORT_DIR" >&2
  exit 1
fi

cp -f "$IPA_PATH" "$SIGNED_IPA"

TMP_UNZIP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_UNZIP_DIR"
}
trap cleanup EXIT

unzip -q "$IPA_PATH" -d "$TMP_UNZIP_DIR"
find "$TMP_UNZIP_DIR/Payload" -type d -name "_CodeSignature" -prune -exec rm -rf {} +
find "$TMP_UNZIP_DIR/Payload" -type f -name "embedded.mobileprovision" -delete

(
  cd "$TMP_UNZIP_DIR"
  zip -qry "$UNSIGNED_IPA" Payload
)

echo "Archive: $ARCHIVE_PATH"
echo "Exported IPA: $IPA_PATH"
echo "Signed IPA copy: $SIGNED_IPA"
echo "Unsigned IPA copy: $UNSIGNED_IPA"
