#!/usr/bin/env bash

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/workspace.sh"

python3 -m json.tool "${manifest}" >/dev/null

expected_patch_count="$(manifest_value chromium.patchCount)"
actual_patch_count="$(find "${workspace_root}/patches/chromium" -maxdepth 1 -type f -name '*.patch' | wc -l | tr -d ' ')"
if [[ "${actual_patch_count}" != "${expected_patch_count}" ]]; then
    echo "Expected ${expected_patch_count} Chromium patches, found ${actual_patch_count}." >&2
    exit 1
fi

check_component() {
    local name="$1"
    local path="$2"
    local expected_revision="$3"
    if ! git -C "${path}" rev-parse --git-dir >/dev/null 2>&1; then
        echo "${name} repository was not found at ${path}" >&2
        exit 1
    fi
    local actual_revision
    actual_revision="$(git -C "${path}" rev-parse HEAD)"
    if [[ "${actual_revision}" != "${expected_revision}" ]]; then
        echo "${name} is at ${actual_revision}; expected ${expected_revision}." >&2
        exit 1
    fi
}

check_component "Evo Runtime" "${runtime_dir}" "$(manifest_value components.runtime.revision)"
check_component "Evo OpenCode" "${opencode_dir}" "$(manifest_value components.opencode.revision)"

if git -C "${chromium_src}" rev-parse --git-dir >/dev/null 2>&1; then
    expected_base="$(manifest_value chromium.baseRevision)"
    expected_evo="$(manifest_value chromium.evoRevision)"
    git -C "${chromium_src}" merge-base --is-ancestor "${expected_base}" HEAD
    if ! git -C "${chromium_src}" cat-file -e "${expected_evo}^{commit}"; then
        echo "Pinned Evo Chromium revision ${expected_evo} is unavailable." >&2
        exit 1
    fi
    echo "Chromium checkout: available"
else
    echo "Chromium checkout: not present (patch stack is valid)"
fi

echo "Workspace pins and ${actual_patch_count} Chromium patches are valid."
