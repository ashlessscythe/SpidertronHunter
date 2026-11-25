#!/usr/bin/env bash
# Run in-game tests (factorio-test) inside Docker.
# Usage: scripts/run_factorio_tests.sh [factorio-test args...]   (default: all non-visual tests)
#        scripts/run_factorio_tests.sh --list            list test names (no Docker needed)
#        scripts/run_factorio_tests.sh --run <pattern>   run matching tests, visual ones included;
#                                                        repeatable, Lua patterns (escape - as %-)
# Credentials (needed once to download the factorio-test mod): FACTORIO_USERNAME / FACTORIO_TOKEN,
# or taken from the local Factorio player-data.json on macOS.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
IMAGE=spidertron-hunter-tests

list_tests() {
  # Names written literally in test("...") / describe("..."); loop-generated tests are listed
  # by their template (e.g. "three nests, TA " .. mode), so filter by the literal prefix.
  grep -HnoE '^[[:space:]]*(describe|test|it)\(("[^"]*"|[^,]*)' tests/factorio/*.lua \
    | sed -E 's/^([^:]+):([0-9]+):[[:space:]]*(describe|test|it)\(/\1:\2  \3  /'
}

if [[ "${1:-}" == "--list" || "${1:-}" == "-l" ]]; then
  list_tests
  exit 0
fi

# --run/-r <pattern> (repeatable) -> factorio-test filter arguments.
FILTERS=()
PASSTHRU=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run|-r)
      [[ $# -ge 2 ]] || { echo "missing value for $1" >&2; exit 2; }
      FILTERS+=("$2"); shift 2 ;;
    *) PASSTHRU+=("$1"); shift ;;
  esac
done
set -- ${PASSTHRU[@]+"${PASSTHRU[@]}"}

PD="$HOME/Library/Application Support/factorio/player-data.json"
if [[ -z "${FACTORIO_USERNAME:-}" && -f "$PD" ]]; then
  FACTORIO_USERNAME="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("service-username",""))' "$PD")"
  FACTORIO_TOKEN="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("service-token",""))' "$PD")"
fi

export FACTORIO_USERNAME FACTORIO_TOKEN
docker build --platform linux/amd64 -t "$IMAGE" docker
ARGS=("$@")
if [[ ${#FILTERS[@]} -gt 0 ]]; then
  # Selected by name: do not blacklist the visual-tagged scenarios.
  [[ ${#ARGS[@]} -eq 0 ]] && ARGS=(run --mod-path .)
  ARGS+=("${FILTERS[@]}")
elif [[ ${#ARGS[@]} -eq 0 ]]; then
  ARGS=(run --mod-path . --tag-blacklist visual stress)
fi
# Named volume caches downloaded mods between runs.
exec docker run --rm --platform linux/amd64 \
  -e FACTORIO_USERNAME -e FACTORIO_TOKEN -e CI=1 \
  -v "$ROOT":/work \
  -v spidertron-hunter-fttest-data:/work/factorio-test-data-dir \
  "$IMAGE" "${ARGS[@]}"
