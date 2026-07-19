#!/usr/bin/env bash

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/workspace.sh"

git -C "${workspace_root}" submodule update --init --recursive

bun_bin="${BUN_BIN:-/opt/homebrew/bin/bun}"
if [[ ! -x "${bun_bin}" ]]; then
    echo "Bun was not found at ${bun_bin}." >&2
    exit 1
fi

(cd "${runtime_dir}" && "${bun_bin}" install --frozen-lockfile)
# OpenCode's pinned lockfile predates the Bun version used by Evo and Bun wants
# to rewrite lock metadata even when dependency resolution is unchanged.
(cd "${opencode_dir}" && "${bun_bin}" install --no-save)

echo "Evo component dependencies are ready."
if [[ ! -d "${chromium_src}" ]]; then
    echo "Chromium is not present at ${chromium_src}."
    echo "Place a depot_tools-managed checkout there, then apply the Evo patch stack."
fi
