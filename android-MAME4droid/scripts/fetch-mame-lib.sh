#!/usr/bin/env bash
# Fetch libMAME4droid.so from upstream or (basic) the mj2 reference APK.
# The thin JNI (libmame4droid-jni.so) is still built from this repo via NDK.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FLAVOR="${FLAVOR:-both}"
BUFFER_SIZE=8192

fetch_from_upstream_apk() {
	local version="$1"
	local dest="$2"
	local apk_name="MAME4droid.2026-${version}-release.apk"
	local url="${MAME4DROID_UPSTREAM_APK_URL:-https://github.com/seleuco/MAME4droid-Current/releases/download/v${version}/${apk_name}}"

	mkdir -p "${dest}"
	local tmp
	tmp="$(mktemp -d)"
	trap 'rm -rf "${tmp}"' RETURN

	echo "Downloading ${url}"
	curl -L --fail --retry 3 -o "${tmp}/upstream.apk" "${url}"

	echo "Extracting libMAME4droid.so -> ${dest}"
	unzip -o -j "${tmp}/upstream.apk" "lib/arm64-v8a/libMAME4droid.so" -d "${dest}"
	test -f "${dest}/libMAME4droid.so"
	ls -lh "${dest}/libMAME4droid.so"
}

fetch_basic_mj2_lib() {
	local dest="${ROOT}/app/src/basic/jniLibs/arm64-v8a"
	mkdir -p "${dest}"

	if [[ -f "${dest}/libMAME4droid.so" ]]; then
		echo "Basic mj2 lib already present: ${dest}/libMAME4droid.so"
		ls -lh "${dest}/libMAME4droid.so"
		return 0
	fi

	local ref_apk=""
	if [[ -n "${BASIC_MAME_REFERENCE_APK_URL:-}" ]]; then
		ref_apk="$(mktemp -d)/mj2-basic-reference.apk"
		echo "Downloading basic reference APK: ${BASIC_MAME_REFERENCE_APK_URL}"
		curl -L --fail --retry 3 -o "${ref_apk}" "${BASIC_MAME_REFERENCE_APK_URL}"
	elif [[ -f "${ROOT}/reference/FeiJuchang-1.38.1-mj2-basic-release.apk" ]]; then
		ref_apk="${ROOT}/reference/FeiJuchang-1.38.1-mj2-basic-release.apk"
		echo "Using local reference APK: ${ref_apk}"
	elif [[ -f "${ROOT}/reference/mj2-basic-reference.apk" ]]; then
		ref_apk="${ROOT}/reference/mj2-basic-reference.apk"
		echo "Using local reference APK: ${ref_apk}"
	fi

	if [[ -n "${ref_apk}" && -f "${ref_apk}" ]]; then
		echo "Extracting mj2 libMAME4droid.so (MAME 1.38.1) -> ${dest}"
		unzip -o -j "${ref_apk}" "lib/arm64-v8a/libMAME4droid.so" -d "${dest}"
		test -f "${dest}/libMAME4droid.so"
		ls -lh "${dest}/libMAME4droid.so"
		return 0
	fi

	if [[ -n "${BASIC_MAME_SO_URL:-}" ]]; then
		echo "Downloading basic libMAME4droid.so: ${BASIC_MAME_SO_URL}"
		curl -L --fail --retry 3 -o "${dest}/libMAME4droid.so" "${BASIC_MAME_SO_URL}"
		test -f "${dest}/libMAME4droid.so"
		ls -lh "${dest}/libMAME4droid.so"
		return 0
	fi

	echo "ERROR: basic flavor needs mj2-era libMAME4droid.so (MAME 1.38.1)." >&2
	echo "Set BASIC_MAME_REFERENCE_APK_URL or BASIC_MAME_SO_URL, or place" >&2
	echo "reference/FeiJuchang-1.38.1-mj2-basic-release.apk under android-MAME4droid/." >&2
	exit 1
}

fetch_full_lib() {
	local version="${MAME4DROID_UPSTREAM_VERSION:-1.38.3}"
	local dest="${ROOT}/app/src/full/jniLibs/arm64-v8a"
	fetch_from_upstream_apk "${version}" "${dest}"
}

case "${FLAVOR}" in
	basic)
		fetch_basic_mj2_lib
		;;
	full)
		fetch_full_lib
		;;
	both)
		fetch_basic_mj2_lib
		fetch_full_lib
		;;
	*)
		echo "Unknown FLAVOR: ${FLAVOR}" >&2
		exit 1
		;;
esac

echo "OK"
