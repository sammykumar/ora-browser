#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HELPER_DIR="$PROJECT_ROOT/tools/op-helper"
OUT_DIR="$HELPER_DIR/bin"
OUT="$OUT_DIR/evo-op-helper"

if ! command -v go >/dev/null 2>&1; then
    echo "error: Go toolchain not found. Install Go >= 1.24 (brew install go, or https://go.dev/dl/)." >&2
    exit 1
fi
if ! xcode-select -p >/dev/null 2>&1; then
    echo "error: Xcode Command Line Tools not found (clang is required for CGO). Run: xcode-select --install" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"
cd "$HELPER_DIR"

echo "Building evo-op-helper (arm64, CGO)..."
CGO_ENABLED=1 GOOS=darwin GOARCH=arm64 go build -trimpath -ldflags "-s -w" -o "$OUT" .

echo "Built: $OUT"
file "$OUT"
