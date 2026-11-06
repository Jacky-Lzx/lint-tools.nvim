#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
lint_tmp=$(mktemp -d)
trap 'rm -rf "$lint_tmp"' EXIT HUP INT TERM
export XDG_STATE_HOME="$lint_tmp/state"
export XDG_CACHE_HOME="$lint_tmp/cache"
export NVIM_LOG_FILE="$lint_tmp/nvim.log"
for test in tests/core.lua tests/adapters.lua tests/real.lua; do
  if test -f "$test"; then
    "${NVIM:-nvim}" --headless -u tests/minimal_init.lua -i NONE -n -l "$test"
  fi
done
