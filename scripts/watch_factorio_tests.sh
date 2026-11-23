#!/usr/bin/env bash
# Watch the "visual" in-game tests in a real Factorio window (step mode, normal speed).
# Uses the local Steam install of Factorio (needs 2.1.24+).
# The Steam launcher exits right away, so CLI options never reach the game; the config is
# passed through a temporary tests/factorio/watch_config.lua instead (removed when the game closes).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
F="${FACTORIO_PATH:-$HOME/Library/Application Support/Steam/steamapps/common/Factorio/factorio.app/Contents/MacOS/factorio}"
CFG=tests/factorio/watch_config.lua
trap 'rm -f "$CFG"' EXIT
cat > "$CFG" <<'LUA'
return { step = true, game_speed = 1, tag_whitelist = { "visual" }, default_timeout = 60 * 60 * 5 }
LUA
npx --yes factorio-test-cli run --mod-path . --graphics --factorio-path "$F" "$@" >/dev/null 2>&1 || true
sleep 5
echo "Factorio window open; close it to finish."
while pgrep -f "MacOS/factorio" >/dev/null; do sleep 2; done
