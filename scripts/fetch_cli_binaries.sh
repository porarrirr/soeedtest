#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLI_DIR="$ROOT_DIR/android/app/src/main/assets/cli"
mkdir -p "$CLI_DIR"

if [[ -n "${OOKLA_CLI_URL:-}" ]]; then
  curl -fsSL "$OOKLA_CLI_URL" -o "$CLI_DIR/speedtest"
  chmod +x "$CLI_DIR/speedtest"
fi

if [[ -n "${PYTHON_SPEEDTEST_CLI_URL:-}" ]]; then
  curl -fsSL "$PYTHON_SPEEDTEST_CLI_URL" -o "$CLI_DIR/speedtest-cli"
  chmod +x "$CLI_DIR/speedtest-cli"
fi

echo "CLI binaries prepared in $CLI_DIR"
