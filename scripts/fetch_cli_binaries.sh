#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLI_DIR="$ROOT_DIR/android/app/src/main/assets/cli"
BUNDLE_DIR="$ROOT_DIR/android/app/src/main/cli-binaries"
JNI_DIR="$ROOT_DIR/android/app/src/main/jniLibs"
ARM64_DIR="$CLI_DIR/arm64-v8a"
ARMV7_DIR="$CLI_DIR/armeabi-v7a"
X86_64_DIR="$CLI_DIR/x86_64"
X86_DIR="$CLI_DIR/x86"
ARM64_BUNDLE_DIR="$BUNDLE_DIR/arm64-v8a"
ARMV7_BUNDLE_DIR="$BUNDLE_DIR/armeabi-v7a"
X86_64_BUNDLE_DIR="$BUNDLE_DIR/x86_64"
X86_BUNDLE_DIR="$BUNDLE_DIR/x86"
ARM64_JNI_DIR="$JNI_DIR/arm64-v8a"
ARMV7_JNI_DIR="$JNI_DIR/armeabi-v7a"
X86_64_JNI_DIR="$JNI_DIR/x86_64"
X86_JNI_DIR="$JNI_DIR/x86"

: "${OOKLA_CLI_AARCH64_TGZ_URL:?Missing OOKLA_CLI_AARCH64_TGZ_URL}"

rm -rf "$CLI_DIR"
rm -rf "$BUNDLE_DIR"
rm -rf "$JNI_DIR"
mkdir -p "$ARM64_DIR"
mkdir -p "$ARM64_BUNDLE_DIR"
mkdir -p "$ARM64_JNI_DIR"

extract_speedtest() {
  local url="$1"
  local dest_dir="$2"
  local bundle_dir="$3"
  local jni_dir="$4"
  local archive
  local temp_dir
  archive="$(mktemp)"
  temp_dir="$(mktemp -d)"
  trap 'rm -f "$archive"; rm -rf "$temp_dir"' RETURN

  curl -fsSL "$url" -o "$archive"
  tar -xzf "$archive" -C "$temp_dir" speedtest
  install -m 0755 "$temp_dir/speedtest" "$dest_dir/speedtest"
  install -m 0755 "$temp_dir/speedtest" "$bundle_dir/speedtest"
  install -m 0755 "$temp_dir/speedtest" "$jni_dir/libspeedtest.so"
}

extract_speedtest "$OOKLA_CLI_AARCH64_TGZ_URL" "$ARM64_DIR" "$ARM64_BUNDLE_DIR" "$ARM64_JNI_DIR"

if [[ -n "${OOKLA_CLI_ARMHF_TGZ_URL:-}" ]]; then
  mkdir -p "$ARMV7_DIR"
  mkdir -p "$ARMV7_BUNDLE_DIR"
  mkdir -p "$ARMV7_JNI_DIR"
  extract_speedtest "$OOKLA_CLI_ARMHF_TGZ_URL" "$ARMV7_DIR" "$ARMV7_BUNDLE_DIR" "$ARMV7_JNI_DIR"
fi

if [[ -n "${OOKLA_CLI_X86_64_TGZ_URL:-}" ]]; then
  mkdir -p "$X86_64_DIR"
  mkdir -p "$X86_64_BUNDLE_DIR"
  mkdir -p "$X86_64_JNI_DIR"
  extract_speedtest "$OOKLA_CLI_X86_64_TGZ_URL" "$X86_64_DIR" "$X86_64_BUNDLE_DIR" "$X86_64_JNI_DIR"
fi

if [[ -n "${OOKLA_CLI_X86_TGZ_URL:-}" ]]; then
  mkdir -p "$X86_DIR"
  mkdir -p "$X86_BUNDLE_DIR"
  mkdir -p "$X86_JNI_DIR"
  extract_speedtest "$OOKLA_CLI_X86_TGZ_URL" "$X86_DIR" "$X86_BUNDLE_DIR" "$X86_JNI_DIR"
fi

echo "CLI binaries prepared in $CLI_DIR"
find "$CLI_DIR" -type f -maxdepth 3 -print
echo "CLI binaries mirrored in $BUNDLE_DIR"
find "$BUNDLE_DIR" -type f -maxdepth 3 -print
echo "CLI native libs mirrored in $JNI_DIR"
find "$JNI_DIR" -type f -maxdepth 3 -print
