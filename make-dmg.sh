#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Packages the already-built, signed + notarized DupeFinder.app into a
# distributable DMG. Deliberately separate from build.sh/notarize.sh: this is
# the final packaging step, run only when cutting a real release, after
# notarize.sh has already stapled the ticket.

APP="DupeFinder.app"
VERSION=$(defaults read "$(pwd)/$APP/Contents/Info" CFBundleShortVersionString)
DMG="DupeFinder-$VERSION.dmg"
VOLNAME="DupeFinder"
KEYCHAIN_PROFILE="${NOTARY_PROFILE:-MacGroom-Notary}"

if [ ! -d "$APP" ]; then
  echo "✗ $APP not found — run ./build.sh first." >&2
  exit 1
fi

# Staple check — a DMG built from an un-stapled app still works, but
# Gatekeeper then needs a live network call to verify on first launch instead
# of working fully offline. Warn, don't block: a local test DMG doesn't need
# this, only a real release does.
if ! xcrun stapler validate "$APP" >/dev/null 2>&1; then
  echo "⚠ $APP has no valid notarization staple — run ./notarize.sh first"
  echo "  if this DMG is meant for real distribution, not just local testing."
fi

rm -f "$DMG"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

ditto "$APP" "$STAGING/$APP"
# A symlink to /Applications in the same staging folder is the standard
# "drag the app onto Applications" DMG layout every Mac user expects.
ln -s /Applications "$STAGING/Applications"

# Custom volume icon — reuses the app's own icon so a mounted DMG doesn't
# show macOS's generic external-drive icon. The "has custom icon" flag only
# takes on a live, writable volume — copying .VolumeIcon.icns into a
# compressed read-only image doesn't stick — so: build read-write first,
# mount it, set the icon, unmount, then convert to the real compressed DMG.
cp "$APP/Contents/Resources/AppIcon.icns" "$STAGING/.VolumeIcon.icns"

RWDMG="$(mktemp -u /tmp/DupeFinder-rw-XXXX).dmg"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGING" -ov -format UDRW "$RWDMG" -quiet
MOUNT_DIR="$(mktemp -d)"
hdiutil attach "$RWDMG" -mountpoint "$MOUNT_DIR" -nobrowse -quiet
xcrun SetFile -a C "$MOUNT_DIR"
hdiutil detach "$MOUNT_DIR" -quiet
rm -rf "$MOUNT_DIR"

hdiutil convert "$RWDMG" -format UDZO -o "$DMG" -ov -quiet
rm -f "$RWDMG"

# Sign the DMG container itself, not just the app inside it — otherwise a
# downloaded DMG shows an "unidentified developer" warning the moment it is
# opened, before the (already notarized) app inside is ever reached.
IDENTITY=$( (security find-identity -v -p codesigning 2>/dev/null | grep '"Developer ID Application' | head -1 | sed -E 's/.*"(.+)"/\1/') || true)
if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" "$DMG"
  echo "Signed DMG with: $IDENTITY"
  if xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" >/dev/null 2>&1; then
    echo "Notarizing DMG…"
    xcrun notarytool submit "$DMG" --keychain-profile "$KEYCHAIN_PROFILE" --wait
    xcrun stapler staple "$DMG"
    echo "✓ DMG signed, notarized, and stapled — ready to distribute."
  else
    echo "⚠ No '$KEYCHAIN_PROFILE' notarytool credentials — DMG signed but not notarized."
    echo "  Notarize it manually:  xcrun notarytool submit \"$DMG\" --keychain-profile \"$KEYCHAIN_PROFILE\" --wait && xcrun stapler staple \"$DMG\""
  fi
else
  echo "⚠ No Developer ID identity — DMG left unsigned (fine for local testing, not for real distribution)."
fi

echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
