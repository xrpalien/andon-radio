#!/usr/bin/env bash
#
# Cut a release of Andon Radio.
#
#   tool/release.sh 1.1.0 "Group and ungroup speakers from the room picker."
#
# Bumps the version, runs the tests, builds a signed APK, and publishes it to
# GitHub Releases. The app reads that release directly, so publishing here is
# what makes the update banner appear on Deborah's phone.
#
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-}"
NOTES="${2:-}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "usage: ${0##*/} <version> [release notes]" >&2
    echo "       version must look like 1.2.3" >&2
    exit 64
fi

die() { echo "release: $1" >&2; exit 1; }

command -v gh >/dev/null || die "the GitHub CLI (gh) is not installed"
gh auth status >/dev/null 2>&1 || die "gh is not logged in — run: gh auth login"
[[ -f android/key.properties ]] || die "android/key.properties is missing; the build would be signed with debug keys"

# --- version ---------------------------------------------------------------
# pubspec carries "version: 1.0.0+3"; the build number must always climb or
# Android refuses the update as a downgrade.
CURRENT_BUILD=$(sed -n 's/^version:.*+\([0-9]*\)$/\1/p' pubspec.yaml)
[[ -n "$CURRENT_BUILD" ]] || die "could not read the build number from pubspec.yaml"
NEXT_BUILD=$((CURRENT_BUILD + 1))

echo "==> version $VERSION+$NEXT_BUILD"
sed -i '' "s/^version: .*/version: $VERSION+$NEXT_BUILD/" pubspec.yaml

# --- verify ----------------------------------------------------------------
echo "==> tests"
flutter test

echo "==> build"
flutter build apk --release

APK=build/app/outputs/flutter-apk/app-release.apk
[[ -f "$APK" ]] || die "no APK was produced"

# The single most important check here. An APK signed with a different key
# cannot install over the one already on her phone: Android rejects it, and
# the only way out is uninstalling and losing saved settings.
APKSIGNER=$(ls ~/Library/Android/sdk/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1)
if [[ -n "$APKSIGNER" ]]; then
    if "$APKSIGNER" verify --print-certs "$APK" 2>/dev/null | grep -q "CN=Android Debug"; then
        die "this APK is signed with DEBUG keys — it cannot update an installed copy. Check android/key.properties."
    fi
    echo "==> signed with the release key"
fi

mkdir -p dist
OUT="dist/andon-radio-$VERSION.apk"
cp "$APK" "$OUT"
echo "==> $OUT ($(du -h "$OUT" | cut -f1))"

# --- publish ---------------------------------------------------------------
git add -A
git commit -m "Release $VERSION" >/dev/null
git tag "v$VERSION"
git push
git push --tags

gh release create "v$VERSION" "$OUT" \
    --title "$VERSION" \
    --notes "${NOTES:-Maintenance release.}"

echo
echo "Published v$VERSION."
echo
# A phone with Advanced Protection cannot install the download the in-app
# banner points at, so say what actually has to happen rather than implying
# it will sort itself out.
echo "Phones that can sideload will offer the update on next open."
echo "For one with Advanced Protection, push it over ADB:"
echo "    tool/push-to-device.sh"
