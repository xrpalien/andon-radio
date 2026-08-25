#!/usr/bin/env bash
#
# Install the latest published release onto a connected device over ADB.
#
#   tool/push-to-device.sh                 # the only connected device
#   tool/push-to-device.sh 192.168.1.33:39839
#
# ADB does not go through the "install unknown apps" permission, so this works
# on a phone with Advanced Protection enabled, where tapping the APK is blocked
# outright. That is how Deborah's Pixel is updated.
#
set -euo pipefail

cd "$(dirname "$0")/.."

REPO=$(sed -n "s/.*defaultRepository = '\([^']*\)'.*/\1/p" lib/services/update_checker.dart)
[[ -n "$REPO" ]] || { echo "could not read the repo from update_checker.dart" >&2; exit 1; }

DEVICE="${1:-}"
if [[ -z "$DEVICE" ]]; then
    mapfile -t DEVICES < <(adb devices | awk '/\tdevice$/ {print $1}')
    case "${#DEVICES[@]}" in
        0) echo "no device connected — pair it with: adb pair <host:port>" >&2; exit 1 ;;
        1) DEVICE="${DEVICES[0]}" ;;
        *) echo "several devices connected; name one:" >&2
           adb devices -l | sed -n 's/^\([^ ]*\) *device .*model:\([^ ]*\).*/  \1  (\2)/p' >&2
           exit 1 ;;
    esac
fi

MODEL=$(adb -s "$DEVICE" shell getprop ro.product.model 2>/dev/null | tr -d '\r')
echo "==> device: $MODEL ($DEVICE)"

TAG=$(curl -sf "https://api.github.com/repos/$REPO/releases/latest" \
      | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)
[[ -n "$TAG" ]] || { echo "could not reach the releases API for $REPO" >&2; exit 1; }
VERSION="${TAG#v}"

INSTALLED=$(adb -s "$DEVICE" shell dumpsys package com.jameslosh.andon_radio 2>/dev/null \
            | sed -n 's/.*versionName=\(.*\)/\1/p' | head -1 | tr -d '\r')
echo "==> installed: ${INSTALLED:-none}   latest: $VERSION"

if [[ "$INSTALLED" == "$VERSION" ]]; then
    echo "already up to date."
    exit 0
fi

APK="dist/andon-radio-$VERSION.apk"
if [[ ! -f "$APK" ]]; then
    echo "==> downloading $TAG"
    mkdir -p dist
    URL=$(curl -sf "https://api.github.com/repos/$REPO/releases/latest" \
          | sed -n 's/.*"browser_download_url": *"\([^"]*\.apk\)".*/\1/p' | head -1)
    [[ -n "$URL" ]] || { echo "that release has no APK attached" >&2; exit 1; }
    curl -fL --progress-bar "$URL" -o "$APK"
fi

echo "==> installing $VERSION"
# -r keeps her saved room and station; it works because every build is signed
# with the same key.
adb -s "$DEVICE" install -r "$APK"
echo "Done. $MODEL is on $VERSION."
