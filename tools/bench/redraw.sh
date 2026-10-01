#!/usr/bin/env bash
# redraw.sh [N] - same fixed workload as page_switch.sh, run with the row cache off then on.
# Prints: name mean_us p95_us forks, then the rowcache counters. Run it twice for before/after:
#   TUI_ROWCACHE=0 tools/bench/redraw.sh   # baseline
#   TUI_ROWCACHE=1 tools/bench/redraw.sh   # cached
# Compare the `render` span mean and rowcache_hit/miss.
REPO="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
exec "$REPO/tools/bench/page_switch.sh" "${1:-40}"
