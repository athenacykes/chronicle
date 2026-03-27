# macOS Release: Developer ID + Notarized DMG

This flow packages Chronicle for direct distribution outside the Mac App Store.

## 1) One-time setup

1. Join Apple Developer Program (active paid membership).
2. In Apple Developer portal, ensure App ID exists for `com.chronicle.app`.
3. In Xcode (`Settings` -> `Accounts`), sign in to the same team.
4. Install/confirm a valid `Developer ID Application` certificate in Keychain.
5. Prepare notarization credentials:
   - Recommended: create a notarytool keychain profile.
   - Alternative: App Store Connect API key (`.p8`) + key ID + issuer ID.

## 2) Release command

From repo root:

```bash
chmod +x scripts/release/macos_release.sh
TEAM_ID=YOURTEAMID \
NOTARY_PROFILE=your-notarytool-profile \
BUILD_NAME=1.0.0 \
BUILD_NUMBER=1 \
scripts/release/macos_release.sh
```

Alternative notarization credentials:

```bash
TEAM_ID=YOURTEAMID \
APPLE_API_KEY_PATH=/absolute/path/AuthKey_ABC123XYZ.p8 \
APPLE_API_KEY_ID=ABC123XYZ \
APPLE_API_ISSUER_ID=11111111-2222-3333-4444-555555555555 \
BUILD_NAME=1.0.0 \
BUILD_NUMBER=1 \
scripts/release/macos_release.sh
```

If auto-detection of Developer ID identity does not work, pass it explicitly:

```bash
TEAM_ID=YOURTEAMID \
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (YOURTEAMID)" \
NOTARY_PROFILE=your-notarytool-profile \
scripts/release/macos_release.sh
```

If you need to bypass analyzer/tests in a local release run:

```bash
RUN_QUALITY_GATES=0 TEAM_ID=YOURTEAMID NOTARY_PROFILE=your-notarytool-profile scripts/release/macos_release.sh
```

## 3) Outputs

- Exported app: `build/macos/export/*.app`
- Final distributable DMG: `build/macos/release-artifacts/*.dmg`
- Generated export options: `build/macos/release-artifacts/ExportOptions.generated.plist`

## 4) Notes

- Script runs quality gates before packaging: `flutter analyze` and `flutter test` (default; disable with `RUN_QUALITY_GATES=0`).
- Release build is forced to native macOS shell via `--dart-define=CHRONICLE_MACOS_NATIVE_UI=true`.
- Script performs `xcodebuild archive` + `xcodebuild -exportArchive` with Developer ID method.
- Script signs the DMG with your `Developer ID Application` identity before notarization.
- Script notarizes the DMG and staples it (unless `SKIP_NOTARIZATION=1`).
