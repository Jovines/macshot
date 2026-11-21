#!/bin/bash
# Package a local macshot build with the Fork's Developer ID identity.
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 /path/to/built/macshot.app /path/to/preview.zip" >&2
    exit 64
fi

repo=$(cd "$(dirname "$0")/.." && pwd)
input=$1
output=$2
team=7437GDF3XU
bundle_id=com.sw33tlie.macshot.macshot

if [[ ! -d "$input" || "$output" != *.zip || -e "$output" ]]; then
    echo "Pass an existing .app and a new .zip path." >&2
    exit 64
fi

identities=$(security find-identity -v -p codesigning)
identity=${MACSHOT_SIGNING_IDENTITY:-}
if [[ -z "$identity" ]]; then
    matches=$(awk -v team="($team)" '$0 ~ /Developer ID Application:/ && index($0, team) {print $2}' <<< "$identities")
    if [[ -z "$matches" || "$matches" == *$'\n'* ]]; then
        echo "Expected one Developer ID Application identity for team $team. Set MACSHOT_SIGNING_IDENTITY to its SHA-1 fingerprint if there are multiple." >&2
        exit 1
    fi
    identity=$matches
fi
if ! awk -v id="$identity" -v team="($team)" '
    $2 == id && /Developer ID Application:/ && index($0, team) {found = 1}
    END {exit !found}
' <<< "$identities"; then
    echo "The selected identity is not a valid Developer ID Application certificate for team $team." >&2
    exit 1
fi

stage=$(mktemp -d "${TMPDIR:-/tmp}/macshot-fork-preview.XXXXXX")
trap 'python3 -c "import shutil, sys; shutil.rmtree(sys.argv[1])" "$stage"' EXIT
app="$stage/macshot.app"
plist="$app/Contents/Info.plist"
ditto --noqtn "$input" "$app"
if [[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist") != "$bundle_id" ]]; then
    echo "Expected bundle identifier $bundle_id." >&2
    exit 1
fi
for key in SUEnableAutomaticChecks SUAutomaticallyUpdate; do
    plutil -replace "$key" -bool NO "$plist" || plutil -insert "$key" -bool NO "$plist"
done

sign() {
    codesign --force --timestamp --options runtime --sign "$identity" "$@"
}

# Work from nested code outwards. Only the main app gets its sandbox entitlements.
while IFS= read -r -d '' item; do
    sign "$item"
done < <(find "$app/Contents" -depth \( -type d \( -name '*.xpc' -o -name '*.app' -o -name '*.framework' \) \
    -o -type f \( -name '*.dylib' -o -name 'Autoupdate' \) \) -print0)
sign --entitlements "$repo/macshot/macshot.entitlements" "$app"
codesign --verify --deep --strict "$app"

zip="$stage/preview.zip"
pack() {
    ditto -c -k --norsrc --noqtn --keepParent "$app" "$zip"
}
pack
if [[ -n "${MACSHOT_NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$zip" --keychain-profile "$MACSHOT_NOTARY_PROFILE" --wait --output-format json > "$stage/notary.json"
    python3 - "$stage/notary.json" <<'PY'
import json
import sys

with open(sys.argv[1]) as stream:
    result = json.load(stream)
print(f"Notarization {result.get('status')}: {result.get('id')}")
if result.get("status") != "Accepted":
    sys.exit(1)
PY
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    spctl --assess --type execute "$app"
    unlink "$zip"
    pack
fi

# Verify the copy a recipient will actually extract.
mkdir "$stage/verify"
ditto -x -k "$zip" "$stage/verify"
codesign --verify --deep --strict "$stage/verify/macshot.app"
mv -n "$zip" "$output"
shasum -a 256 "$output"
