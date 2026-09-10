#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Notarizes the already-built, Developer-ID-signed MacTwin.app from build.sh,
# then staples the ticket so Gatekeeper can verify it offline.
#
# Deliberately a separate script from build.sh: build.sh runs on every local
# rebuild and must still work with no Apple credentials at all (ad-hoc
# fallback); this one is the distribution step, run only when actually
# cutting a release, and it needs real Apple Developer credentials that only
# the account holder can supply.
#
# One-time setup (identity-gated — only the account holder can do this):
#   1. Apple Developer Program enrollment must be fully Active (not
#      "Pending") at developer.apple.com/account.
#   2. Generate a Developer ID Application certificate: Xcode > Settings >
#      Accounts > Manage Certificates > + > Developer ID Application.
#   3. Store notarization credentials once, in the keychain, so this script
#      never needs a plaintext password:
#        xcrun notarytool store-credentials "MacGroom-Notary" \
#          --apple-id "<your Apple ID email>" \
#          --team-id "<your 10-char Team ID>" \
#          --password "<an app-specific password from appleid.apple.com>"
#      (App-specific password, not the Apple ID password.)
#
# That profile is deliberately shared across every app signed by this Team
# ID rather than duplicated per repo: notarytool credentials authenticate
# the *developer account*, not one product, so there is nothing app-specific
# to set up again here. The name is historical — it was first stored while
# releasing MacGroom. Override with NOTARY_PROFILE=<name> if separate
# credentials are ever kept.
KEYCHAIN_PROFILE="${NOTARY_PROFILE:-MacGroom-Notary}"

APP="MacTwin.app"
ZIP="/tmp/MacTwin-notarize.zip"

IDENTITY=$( (security find-identity -v -p codesigning 2>/dev/null | grep '"Developer ID Application' | head -1 | sed -E 's/.*"(.+)"/\1/') || true)
if [ -z "$IDENTITY" ]; then
  echo "✗ No Developer ID Application identity in keychain — nothing to notarize yet."
  echo "  Run 'security find-identity -v -p codesigning' to check, or see the"
  echo "  one-time setup steps at the top of this script."
  exit 1
fi

if ! xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" >/dev/null 2>&1; then
  echo "✗ No '$KEYCHAIN_PROFILE' notarytool credentials in keychain yet."
  echo "  Run the 'xcrun notarytool store-credentials' command documented at"
  echo "  the top of this script once, then re-run."
  exit 1
fi

echo "Rebuilding (Developer ID identity found: $IDENTITY)…"
./build.sh >/dev/null

echo "Re-verifying signature…"
if codesign -dv --verbose=4 "$APP" 2>&1 | grep -q "TeamIdentifier=not set"; then
  echo "✗ build.sh still signed ad-hoc — check the identity match above."
  exit 1
fi

echo "Zipping for submission…"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "Submitting to Apple notary service (this can take a few minutes)…"
xcrun notarytool submit "$ZIP" --keychain-profile "$KEYCHAIN_PROFILE" --wait

echo "Stapling ticket…"
xcrun stapler staple "$APP"

echo "Verifying…"
spctl -a -vvv -t install "$APP"
xcrun stapler validate "$APP"

echo "✓ $APP is signed, notarized, and stapled — ready to distribute."
