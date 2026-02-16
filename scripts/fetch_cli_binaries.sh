#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLI_DIR="$ROOT_DIR/android/app/src/main/assets/cli"
ARM64_DIR="$CLI_DIR/arm64-v8a"
ARMV7_DIR="$CLI_DIR/armeabi-v7a"

: "${OOKLA_CLI_AARCH64_TGZ_URL:?Missing OOKLA_CLI_AARCH64_TGZ_URL}"

rm -rf "$CLI_DIR"
mkdir -p "$ARM64_DIR"

extract_speedtest() {
  local url="$1"
  local dest_dir="$2"
  local archive
  local temp_dir
  archive="$(mktemp)"
  temp_dir="$(mktemp -d)"
  trap 'rm -f "$archive"; rm -rf "$temp_dir"' RETURN

  curl -fsSL "$url" -o "$archive"
  tar -xzf "$archive" -C "$temp_dir" speedtest
  install -m 0755 "$temp_dir/speedtest" "$dest_dir/speedtest"
}

extract_speedtest "$OOKLA_CLI_AARCH64_TGZ_URL" "$ARM64_DIR"

if [[ -n "${OOKLA_CLI_ARMHF_TGZ_URL:-}" ]]; then
  mkdir -p "$ARMV7_DIR"
  extract_speedtest "$OOKLA_CLI_ARMHF_TGZ_URL" "$ARMV7_DIR"
fi

echo "CLI binaries prepared in $CLI_DIR"
find "$CLI_DIR" -type f -maxdepth 3 -print
