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

# --- Architecture (Task 2.7 decision, 2026-07-04) ---
# Default: arm64-only. Both target machines (personal + work MBP) are Apple Silicon, and the
# 1Password dylib (libop_sdk_ipc_client.dylib) is thin arm64 on Apple Silicon installs — an x86_64
# helper slice could not dlopen it there. If the work MBP turns out to be Intel, build a universal
# binary instead (its 1Password ships an x86_64 dylib):
#   CGO_ENABLED=1 GOOS=darwin GOARCH=arm64 go build -trimpath -ldflags "-s -w" -o "$OUT_DIR/evo-op-helper-arm64" .
#   CGO_ENABLED=1 GOOS=darwin GOARCH=amd64 go build -trimpath -ldflags "-s -w" -o "$OUT_DIR/evo-op-helper-amd64" .
#   lipo -create -output "$OUT" "$OUT_DIR/evo-op-helper-arm64" "$OUT_DIR/evo-op-helper-amd64"
#   rm -f "$OUT_DIR/evo-op-helper-arm64" "$OUT_DIR/evo-op-helper-amd64"
# (A wrong-arch spawn failure surfaces in the connection panel as an "unavailable" status via
# OnePasswordService.disambiguate / the makeProcessTransport start() failure path.)
