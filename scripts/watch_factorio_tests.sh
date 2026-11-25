#!/usr/bin/env bash
# Usage: watch_factorio_tests.sh [--list] [--run <pattern>]... [--speed <n>] [factorio-test-cli args]
#   --speed <n>  game speed multiplier (default 1 = realtime; e.g. 10), or set WATCH_SPEED=10
# Watch the "visual" in-game tests in a real Factorio window (step mode, normal speed).
# Uses the local Steam install of Factorio (needs 2.1.24+).
# The Steam launcher exits right away, so CLI options never reach the game; the config is
# passed through a temporary tests/factorio/watch_config.lua instead (removed when the game closes).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
F="${FACTORIO_PATH:-$HOME/Library/Application Support/Steam/steamapps/common/Factorio/factorio.app/Contents/MacOS/factorio}"
if [[ "${1:-}" == "--list" || "${1:-}" == "-l" ]]; then
  exec scripts/run_factorio_tests.sh --list
fi
FILTERS=()
PASSTHRU=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run|-r)
      [[ $# -ge 2 ]] || { echo "missing value for $1" >&2; exit 2; }
      FILTERS+=("$2"); shift 2 ;;
    --speed|-s)
      [[ $# -ge 2 ]] || { echo "missing value for $1" >&2; exit 2; }
      WATCH_SPEED="$2"; shift 2 ;;
    *) PASSTHRU+=("$1"); shift ;;
  esac
done
set -- ${PASSTHRU[@]+"${PASSTHRU[@]}"} ${FILTERS[@]+"${FILTERS[@]}"}
CFG=tests/factorio/watch_config.lua
trap 'rm -f "$CFG"' EXIT
cat > "$CFG" <<LUA
return { step = true, game_speed = ${WATCH_SPEED:-1}, tag_whitelist = { "visual" }, default_timeout = 60 * 60 * 5 }
LUA
# The CLI-generated config has no [sound] section; Factorio 2.1.25 on macOS then logs
# "Value must be a dictionary in property tree at ROOT.sound" right after audio init and quits.
TEST_CFG=factorio-test-data-dir/config.ini
if [[ -f "$TEST_CFG" ]] && ! grep -q '^master-volume=' "$TEST_CFG"; then
  grep -q '^\[sound\]' "$TEST_CFG" || printf '\n[sound]\n' >> "$TEST_CFG"
  sed -i '' 's/^\[sound\]$/[sound]\nmaster-volume=0.95/' "$TEST_CFG"
fi
npx --yes factorio-test-cli run --mod-path . --graphics --factorio-path "$F" "$@" >/dev/null 2>&1 || true
sleep 5
echo "Factorio window open; close it to finish."
while pgrep -f "MacOS/factorio" >/dev/null; do sleep 2; done
