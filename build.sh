#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="MacTwin.app"
BIN="MacTwin"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>MacTwin</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>com.rajeshsood.mactwin</string>
	<key>CFBundleName</key>
	<string>MacTwin</string>
	<key>CFBundleDisplayName</key>
	<string>MacTwin</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.2</string>
	<key>CFBundleVersion</key>
	<string>4</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<false/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>© 2026 Rajesh Sood</string>
</dict>
</plist>
PLIST

# --- App icon: render from an SF Symbol (stays crisp at every size, no text) ---
ICON_SCRIPT="$(mktemp /tmp/rendericon-XXXX).swift"
cat > "$ICON_SCRIPT" <<'SWIFT'
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let bgRect = NSRect(x: 0, y: 0, width: size, height: size)
NSGradient(starting: NSColor(calibratedRed: 0.14, green: 0.28, blue: 0.30, alpha: 1),
           ending: NSColor(calibratedRed: 0.04, green: 0.09, blue: 0.10, alpha: 1))?
    .draw(in: bgRect, angle: -90)

let config = NSImage.SymbolConfiguration(pointSize: size * 0.5, weight: .semibold)
if let symbol = NSImage(systemSymbolName: "doc.on.doc.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config),
   let cg = symbol.cgImage(forProposedRect: nil, context: nil, hints: nil),
   let ctx = NSGraphicsContext.current?.cgContext {
    let symSize = symbol.size
    let rect = CGRect(x: (size - symSize.width) / 2, y: (size - symSize.height) / 2,
                       width: symSize.width, height: symSize.height)
    ctx.saveGState()
    ctx.clip(to: rect, mask: cg)
    NSColor.white.setFill()
    ctx.fill(rect)
    ctx.restoreGState()
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("Failed to render icon\n".data(using: .utf8)!)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT

SQ="$(mktemp /tmp/appicon-XXXX).png"
swift "$ICON_SCRIPT" "$SQ"

ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$SQ" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$SQ" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
echo "Icon:  AppIcon.icns rendered from SF Symbol"

SOURCES=$(find Sources -name '*.swift')

# --- Universal binary: build both slices, glue with lipo ---
# A plain `swiftc` build only targets the host Mac's own architecture — fine
# for local dev, but silently ships arm64-only to anyone running this on an
# Intel Mac. Compiling each slice explicitly and combining them is what
# `xcodebuild`'s ARCHS=$(ARCHS_STANDARD) does under the hood.
MIN_OS="13.0"
TMPBIN="$(mktemp -d)"
for ARCH in arm64 x86_64; do
  echo "Compiling $ARCH slice…"
  swiftc -O -parse-as-library \
    -target "$ARCH-apple-macos$MIN_OS" \
    -o "$TMPBIN/MacTwin-$ARCH" \
    $SOURCES
done
lipo -create -output "$APP/Contents/MacOS/MacTwin" "$TMPBIN/MacTwin-arm64" "$TMPBIN/MacTwin-x86_64"
rm -rf "$TMPBIN"

echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/MacTwin"))"

# --- Sign: hardened runtime + entitlements, no App Sandbox ---
# A real Developer ID Application identity is used when present. That's what
# notarization requires (see notarize.sh), and it also keeps TCC permission
# grants stable across rebuilds, since the grant then keys off a signing
# identity that no longer changes on every build.
#
# Falls back to ad-hoc when no Developer ID is in the keychain, so a fresh
# clone still builds and runs locally. An ad-hoc build is local-only:
# Gatekeeper blocks it on every other Mac, and its TCC grants reset on each
# rebuild because the CDHash is just a hash of the raw binary.
IDENTITY=$( (security find-identity -v -p codesigning 2>/dev/null | grep '"Developer ID Application' | head -1 | sed -E 's/.*"(.+)"/\1/') || true)
if [ -z "$IDENTITY" ]; then
  echo "No Developer ID Application identity in keychain — signing ad-hoc."
  echo "  This build is local-only: Gatekeeper will block it on any other Mac."
  echo "  With Apple Developer enrollment active: Xcode > Settings > Accounts"
  echo "  > Manage Certificates > + > Developer ID Application, then rebuild."
  IDENTITY="-"
fi
# No --deep: Apple deprecated it, and it signs any nested code with the
# *outer* entitlements. These bundles have no nested code to sign anyway.
codesign --force --options runtime --entitlements "$(dirname "$0")/MacTwin.entitlements" --sign "$IDENTITY" "$APP"
echo "Signed with: $IDENTITY (hardened runtime on)"


# --- Install to /Applications ---
DEST="/Applications/$APP"
if [ -d "$DEST" ]; then rm -rf "$DEST"; fi
if ditto "$APP" "$DEST" 2>/dev/null; then
  echo "Installed to $DEST"
  echo "Run:  open \"$DEST\""
else
  echo "WARN: could not write to /Applications (permissions?). Retrying with sudo…"
  sudo rm -rf "$DEST" && sudo ditto "$APP" "$DEST" && echo "Installed to $DEST (sudo)"
fi
