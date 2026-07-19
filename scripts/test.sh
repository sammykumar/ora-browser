#!/usr/bin/env bash

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/workspace.sh"

"${workspace_root}/scripts/check-workspace.sh"

bun_bin="${BUN_BIN:-/opt/homebrew/bin/bun}"
if [[ ! -x "${bun_bin}" ]]; then
    echo "Bun was not found at ${bun_bin}." >&2
    exit 1
fi

if [[ ! -d "${runtime_dir}/node_modules" || ! -d "${opencode_dir}/node_modules" ]]; then
    "${workspace_root}/scripts/bootstrap.sh"
fi

"${bun_bin}" run --cwd "${runtime_dir}" test
"${bun_bin}" run --cwd "${runtime_dir}" typecheck

if [[ -f "${opencode_dir}/packages/opencode/package.json" ]]; then
    "${bun_bin}" run --cwd "${opencode_dir}/packages/opencode" typecheck
fi

echo "Evo workspace tests passed."
