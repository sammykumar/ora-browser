#!/bin/bash
# End-to-end smoke of the debug harness. Requires: debug Evo.app running, fixture server running.
set -euo pipefail

PORT="${EVO_HARNESS_PORT:-4590}"
# NOTE: 'xcodebuild test' rewrites this token file; if requests 401, relaunch the app or re-read the token.
TOKEN=$(cat "$HOME/Library/Application Support/Evo/harness-token")
BASE="http://127.0.0.1:$PORT"
OUT="${1:-/tmp/evo-harness-smoke}"
mkdir -p "$OUT"

req() { curl -sf -H "X-Evo-Harness-Token: $TOKEN" "$@"; }

# Capture prior provider setting to restore on exit
PRIOR_KIND=$(req "$BASE/provider" | python3 -c "import sys,json;print(json.load(sys.stdin)['kind'])")

# Register trap to restore provider on exit (success or failure)
trap 'curl -sf -H "X-Evo-Harness-Token: $TOKEN" -X POST -d "{\"kind\":\"$PRIOR_KIND\"}" "$BASE/provider" >/dev/null || true' EXIT

echo "Provider will be restored to: $PRIOR_KIND"
echo "1. health"; req "$BASE/health"

echo "2. switch to mock provider"
req -X POST -d '{"kind":"mock"}' "$BASE/provider"

echo "3. open the basic login fixture"
TAB=$(req -X POST -d '{"url":"http://127.0.0.1:4599/login-basic.html"}' "$BASE/navigate" | python3 -c "import sys,json;print(json.load(sys.stdin)['tabID'])")
sleep 2

echo "4. focus the username field"
req -X POST -d "{\"tabID\":\"$TAB\",\"js\":\"document.getElementById('username').focus(); true\"}" "$BASE/eval"
sleep 1

echo "5. overlay state (expect visible with 2 mock rows)"
req "$BASE/overlay?tab=$TAB" | tee "$OUT/overlay.json"

echo "6. screenshot the window with overlay up"
req -X POST -d "{\"scope\":\"window\",\"path\":\"$OUT/overlay.png\"}" "$BASE/screenshot"

echo "7. activate the first suggestion"
req -X POST -d "{\"tabID\":\"$TAB\",\"command\":\"activate\"}" "$BASE/keypress"
sleep 1

echo "8. read filled values (expect alice + password)"
req -X POST -d "{\"tabID\":\"$TAB\",\"js\":\"JSON.stringify({u: document.getElementById('username').value, p: document.getElementById('password').value})\"}" "$BASE/eval" | tee "$OUT/filled.json"

echo "9. screenshot the filled page"
req -X POST -d "{\"scope\":\"page\",\"tabID\":\"$TAB\",\"path\":\"$OUT/filled.png\"}" "$BASE/screenshot"

echo "smoke complete → $OUT"
