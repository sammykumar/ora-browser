#!/usr/bin/env bash

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/workspace.sh"

if ! git -C "${chromium_src}" rev-parse --git-dir >/dev/null 2>&1; then
    echo "Chromium repository was not found at ${chromium_src}" >&2
    exit 1
fi
base_revision="$(manifest_value chromium.baseRevision)"
patch_dir="${workspace_root}/$(manifest_value chromium.patchDirectory)"

if [[ -n "$(git -C "${chromium_src}" status --porcelain --untracked-files=no)" ]]; then
    echo "Chromium has tracked changes; commit or stash them before applying patches." >&2
    exit 1
fi
if [[ "$(git -C "${chromium_src}" rev-parse HEAD)" != "${base_revision}" ]]; then
    echo "Chromium must be checked out at ${base_revision} before applying Evo patches." >&2
    exit 1
fi

patches=()
while IFS= read -r patch; do
    patches+=("${patch}")
done < <(find "${patch_dir}" -maxdepth 1 -type f -name '*.patch' | sort)
if [[ "${#patches[@]}" -eq 0 ]]; then
    echo "No Chromium patches were found." >&2
    exit 1
fi

git -C "${chromium_src}" am "${patches[@]}"
echo "Applied ${#patches[@]} Evo Chromium patches."
