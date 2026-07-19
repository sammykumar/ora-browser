#!/usr/bin/env bash

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/workspace.sh"

require_directory "${chromium_src}/evo" "Evo Chromium layer"
EVO_RUNTIME_DIR="${runtime_dir}" \
DEPOT_TOOLS_DIR="${depot_tools_dir}" \
    "${chromium_src}/evo/run-dev.sh" "$@"
