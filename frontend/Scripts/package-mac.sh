#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

APP_NAME="PlacementPrep"
VOL_NAME="Placement Prep"
BUILD="$(pwd)/build/mac"
ARCHIVE="$BUILD/$APP_NAME.xcarchive"
EXPORT="$BUILD/export"
STAGE="$BUILD/stage"
DMG="$BUILD/$APP_NAME.dmg"

DEVELOPER_ID="${DEVELOPER_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

rm -rf "$BUILD"
mkdir -p "$BUILD"

echo "▸ Archiving (Release, Mac Catalyst)…"
ARCHIVE_SIGNING=()
if [[ -z "$DEVELOPER_ID" ]]; then
  ARCHIVE_SIGNING=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO)
fi
xcodebuild archive \
  -project "$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -destination 'generic/platform=macOS,variant=Mac Catalyst' \
  -archivePath "$ARCHIVE" \
  "${ARCHIVE_SIGNING[@]}" \
  | grep -E "error:|warning: .*(deprecat|unavail)|ARCHIVE " || true

[[ -d "$ARCHIVE" ]] || { echo "✗ Archive failed — rerun without the grep filter to see why." >&2; exit 1; }

mkdir -p "$EXPORT"
if [[ -n "$DEVELOPER_ID" ]]; then
  echo "▸ Exporting with Developer ID…"
  TEAM_ID="$(sed -n 's/.*(\([A-Z0-9]\{10\}\))$/\1/p' <<< "$DEVELOPER_ID")"
  [[ -n "$TEAM_ID" ]] || { echo "✗ Couldn't read a team id out of DEVELOPER_ID." >&2; exit 1; }
  cat > "$BUILD/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>developer-id</string>
	<key>teamID</key><string>$TEAM_ID</string>
	<key>signingStyle</key><string>automatic</string>
	<key>destination</key><string>export</string>
</dict>
</plist>
PLIST
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$BUILD/ExportOptions.plist" \
    -exportPath "$EXPORT"
else
  echo "▸ No DEVELOPER_ID set — copying the unsigned app straight out of the archive."
  cp -R "$ARCHIVE/Products/Applications/$APP_NAME.app" "$EXPORT/"
fi

APP="$EXPORT/$APP_NAME.app"
[[ -d "$APP" ]] || { echo "✗ No $APP_NAME.app was produced." >&2; exit 1; }

echo "▸ Building disk image…"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG" >/dev/null

if [[ -n "$DEVELOPER_ID" ]]; then
  echo "▸ Signing the disk image…"
  codesign --sign "$DEVELOPER_ID" --timestamp "$DMG"
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
  echo "▸ Notarizing (this waits on Apple; a few minutes is normal)…"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "▸ Stapling…"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
fi

SIZE="$(du -h "$DMG" | cut -f1)"
echo
echo "✓ $DMG  ($SIZE)"
if [[ -n "$DEVELOPER_ID" && -n "$NOTARY_PROFILE" ]]; then
  echo "  Signed and notarized — safe to put on a website."
else
  echo "  Unsigned. Gatekeeper blocks this on any Mac it was downloaded to, until:"
  echo
  echo "    xattr -dr com.apple.quarantine /Applications/PlacementPrep.app"
  echo
  echo "  That is the whole workaround, and it is why this build skips the \$99"
  echo "  Developer ID."
fi
