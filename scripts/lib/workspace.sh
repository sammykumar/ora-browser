#!/usr/bin/env bash

set -euo pipefail

workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
chromium_src="${EVO_CHROMIUM_SRC:-${workspace_root}/evo-chromium/src}"
runtime_dir="${EVO_RUNTIME_DIR:-${workspace_root}/evo-runtime}"
opencode_dir="${EVO_OPENCODE_DIR:-${workspace_root}/evo-opencode}"
depot_tools_dir="${DEPOT_TOOLS_DIR:-${workspace_root}/depot_tools}"
manifest="${workspace_root}/workspace.json"

manifest_value() {
    python3 - "${manifest}" "$1" <<'PY'
import json
import sys

value = json.load(open(sys.argv[1], encoding="utf-8"))
for key in sys.argv[2].split("."):
    value = value[key]
print(value)
PY
}

require_directory() {
    if [[ ! -d "$1" ]]; then
        echo "$2 was not found at $1" >&2
        exit 1
    fi
}
