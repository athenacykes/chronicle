#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

TEAM_ID="${TEAM_ID:-${APPLE_TEAM_ID:-}}"
DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
APPLE_API_KEY_PATH="${APPLE_API_KEY_PATH:-}"
APPLE_API_KEY_ID="${APPLE_API_KEY_ID:-}"
APPLE_API_ISSUER_ID="${APPLE_API_ISSUER_ID:-}"
SKIP_NOTARIZATION="${SKIP_NOTARIZATION:-0}"
RUN_QUALITY_GATES="${RUN_QUALITY_GATES:-1}"
BUILD_NAME="${BUILD_NAME:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"

if [[ -z "$TEAM_ID" ]]; then
  echo "TEAM_ID (or APPLE_TEAM_ID) is required."
  exit 1
fi

if [[ "$SKIP_NOTARIZATION" != "1" ]] && [[ -z "$NOTARY_PROFILE" ]]; then
  if [[ -z "$APPLE_API_KEY_PATH" || -z "$APPLE_API_KEY_ID" || -z "$APPLE_API_ISSUER_ID" ]]; then
    cat <<EOF
Notarization credentials are missing.
Provide one of:
1) NOTARY_PROFILE (keychain profile created by notarytool), or
2) APPLE_API_KEY_PATH + APPLE_API_KEY_ID + APPLE_API_ISSUER_ID.
EOF
    exit 1
  fi
fi

if [[ -z "$DEVELOPER_ID_APPLICATION" ]]; then
  DEVELOPER_ID_APPLICATION="$(
    security find-identity -v -p codesigning \
      | awk -F\" '/Developer ID Application:/ {print $2}' \
      | grep "(${TEAM_ID})" \
      | head -n 1 || true
  )"
fi

if [[ -z "$DEVELOPER_ID_APPLICATION" ]]; then
  cat <<EOF
Developer ID Application signing identity not found for team ${TEAM_ID}.
Set DEVELOPER_ID_APPLICATION explicitly, for example:
  DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (${TEAM_ID})"
EOF
  exit 1
fi

APP_NAME="${APP_NAME:-Chronicle}"
WORKSPACE="${WORKSPACE:-macos/Runner.xcworkspace}"
SCHEME="${SCHEME:-Runner}"
CONFIGURATION="${CONFIGURATION:-Release}"
DESTINATION="${DESTINATION:-generic/platform=macOS}"

ARCHIVE_DIR="$ROOT_DIR/build/macos/archive"
EXPORT_DIR="$ROOT_DIR/build/macos/export"
DMG_DIR="$ROOT_DIR/build/macos/dmg"
ARTIFACTS_DIR="$ROOT_DIR/build/macos/release-artifacts"
EXPORT_TEMPLATE="$ROOT_DIR/scripts/release/ExportOptions-DeveloperID.plist"
EXPORT_PLIST="$ARTIFACTS_DIR/ExportOptions.generated.plist"

mkdir -p "$ARCHIVE_DIR" "$EXPORT_DIR" "$DMG_DIR" "$ARTIFACTS_DIR"

ARCHIVE_PATH="$ARCHIVE_DIR/${APP_NAME}.xcarchive"

if [[ -z "$BUILD_NAME" || -z "$BUILD_NUMBER" ]]; then
  VERSION_LINE="$(grep -E '^version:' pubspec.yaml | head -n 1 | sed -E 's/^version:[[:space:]]*//')"
  if [[ "$VERSION_LINE" == *"+"* ]]; then
    DEFAULT_BUILD_NAME="${VERSION_LINE%%+*}"
    DEFAULT_BUILD_NUMBER="${VERSION_LINE##*+}"
  else
    DEFAULT_BUILD_NAME="$VERSION_LINE"
    DEFAULT_BUILD_NUMBER="1"
  fi
  BUILD_NAME="${BUILD_NAME:-$DEFAULT_BUILD_NAME}"
  BUILD_NUMBER="${BUILD_NUMBER:-$DEFAULT_BUILD_NUMBER}"
fi

DMG_NAME="${DMG_NAME:-${APP_NAME}-${BUILD_NAME}+${BUILD_NUMBER}.dmg}"
DMG_PATH="$ARTIFACTS_DIR/$DMG_NAME"

rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"

echo "==> flutter pub get"
flutter pub get

if [[ "$RUN_QUALITY_GATES" == "1" ]]; then
  echo "==> flutter analyze"
  flutter analyze

  echo "==> flutter test"
  flutter test
else
  echo "==> skipping flutter analyze/test (RUN_QUALITY_GATES=0)"
fi

echo "==> flutter build macos --release"
flutter build macos --release \
  --dart-define=CHRONICLE_MACOS_NATIVE_UI=true \
  --build-name "$BUILD_NAME" \
  --build-number "$BUILD_NUMBER"

echo "==> xcodebuild archive"
xcodebuild archive \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$TEAM_ID"

echo "==> prepare ExportOptions plist"
sed "s/__TEAM_ID__/$TEAM_ID/g" "$EXPORT_TEMPLATE" > "$EXPORT_PLIST"

echo "==> xcodebuild -exportArchive"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_PLIST"

APP_PATH="$(find "$EXPORT_DIR" -maxdepth 1 -name '*.app' -print -quit)"
if [[ -z "$APP_PATH" ]]; then
  echo "Export did not produce a .app in $EXPORT_DIR"
  exit 1
fi

echo "==> codesign verify .app"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "==> build DMG"
STAGING_DIR="$DMG_DIR/staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"

echo "==> codesign DMG"
codesign --force --sign "$DEVELOPER_ID_APPLICATION" --timestamp "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

if [[ "$SKIP_NOTARIZATION" == "1" ]]; then
  echo "==> notarization skipped (SKIP_NOTARIZATION=1)"
else
  echo "==> notarize DMG"
  if [[ -n "$NOTARY_PROFILE" ]]; then
    xcrun notarytool submit "$DMG_PATH" --wait --keychain-profile "$NOTARY_PROFILE"
  else
    xcrun notarytool submit "$DMG_PATH" --wait \
      --key "$APPLE_API_KEY_PATH" \
      --key-id "$APPLE_API_KEY_ID" \
      --issuer "$APPLE_API_ISSUER_ID"
  fi

  echo "==> staple DMG"
  xcrun stapler staple "$DMG_PATH"
fi

echo "==> Gatekeeper checks"
spctl -a -t exec -vv "$APP_PATH"
spctl -a -t open --context context:primary-signature -vv "$DMG_PATH"

cat <<EOF
Release artifacts created:
- App: $APP_PATH
- DMG: $DMG_PATH
EOF
