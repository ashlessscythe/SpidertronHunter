#!/usr/bin/env bash
# Run in-game tests (factorio-test) inside Docker.
# Usage: scripts/run_factorio_tests.sh [factorio-test args...]   (default: run --mod-path .)
# Credentials (needed once to download the factorio-test mod): FACTORIO_USERNAME / FACTORIO_TOKEN,
# or taken from the local Factorio player-data.json on macOS.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
IMAGE=spidertron-hunter-tests

PD="$HOME/Library/Application Support/factorio/player-data.json"
if [[ -z "${FACTORIO_USERNAME:-}" && -f "$PD" ]]; then
  FACTORIO_USERNAME="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("service-username",""))' "$PD")"
  FACTORIO_TOKEN="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("service-token",""))' "$PD")"
fi

export FACTORIO_USERNAME FACTORIO_TOKEN
docker build --platform linux/amd64 -t "$IMAGE" docker
ARGS=("$@"); [[ ${#ARGS[@]} -eq 0 ]] && ARGS=(run --mod-path . --tag-blacklist visual)
# Named volume caches downloaded mods between runs.
exec docker run --rm --platform linux/amd64 \
  -e FACTORIO_USERNAME -e FACTORIO_TOKEN -e CI=1 \
  -v "$ROOT":/work \
  -v spidertron-hunter-fttest-data:/work/factorio-test-data-dir \
  "$IMAGE" "${ARGS[@]}"
