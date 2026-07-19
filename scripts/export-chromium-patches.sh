#!/usr/bin/env bash

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/workspace.sh"

if ! git -C "${chromium_src}" rev-parse --git-dir >/dev/null 2>&1; then
    echo "Chromium repository was not found at ${chromium_src}" >&2
    exit 1
fi
base_revision="$(manifest_value chromium.baseRevision)"
patch_dir="${workspace_root}/$(manifest_value chromium.patchDirectory)"
temporary_dir="$(mktemp -d)"
trap 'find "${temporary_dir}" -type f -delete; rmdir "${temporary_dir}"' EXIT

git -C "${chromium_src}" merge-base --is-ancestor "${base_revision}" HEAD
git -C "${chromium_src}" format-patch \
    --binary \
    --full-index \
    --no-signature \
    --output-directory "${temporary_dir}" \
    "${base_revision}..HEAD" >/dev/null

mkdir -p "${patch_dir}"
find "${patch_dir}" -maxdepth 1 -type f -name '*.patch' -delete
find "${temporary_dir}" -maxdepth 1 -type f -name '*.patch' -exec mv {} "${patch_dir}/" \;

patch_count="$(find "${patch_dir}" -maxdepth 1 -type f -name '*.patch' | wc -l | tr -d ' ')"
echo "Exported ${patch_count} Chromium patches from ${base_revision}..HEAD."
echo "Update workspace.json if the expected revision or patch count changed."
