#!/usr/bin/env bash
# Fetch libMAME4droid.so from the matching upstream release APK.
# The thin JNI (libmame4droid-jni.so) is still built from this repo via NDK.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${ROOT}/app/src/main/jniLibs/arm64-v8a"
VERSION="${MAME4DROID_UPSTREAM_VERSION:-1.38.1}"
APK_NAME="MAME4droid.2026-${VERSION}-release.apk"
URL="${MAME4DROID_UPSTREAM_APK_URL:-https://github.com/seleuco/MAME4droid-Current/releases/download/v${VERSION}/${APK_NAME}}"

mkdir -p "${DEST}"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

echo "Downloading ${URL}"
curl -L --fail --retry 3 -o "${TMP}/upstream.apk" "${URL}"

echo "Extracting libMAME4droid.so (arm64-v8a)"
unzip -o -j "${TMP}/upstream.apk" "lib/arm64-v8a/libMAME4droid.so" -d "${DEST}"
test -f "${DEST}/libMAME4droid.so"
ls -lh "${DEST}/libMAME4droid.so"
echo "OK -> ${DEST}/libMAME4droid.so"
