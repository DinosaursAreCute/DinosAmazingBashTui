#!/usr/bin/env bash
# profile_callbacks_source.sh - what does re-sourcing each page's callback file cost? (they are sourced on EVERY visit)
#   bin/debug/profile_callbacks_source.sh [-d PAGES_DIR]
# Also times the bundled renderer library. Use tui.require terminal_renderer in callback files instead of `source`.
DIR="$(cd "$(dirname "$0")/.." && pwd)"; PAGES_DIR="$DIR/../config/DABT_demo"
[[ "$1" == -d ]] && { PAGES_DIR="$2"; shift 2; }
export XDG_CONFIG_HOME="$(mktemp -d)"; trap 'rm -rf "$XDG_CONFIG_HOME"' EXIT
cd "$DIR" && source ./tui.sh; tui.log() { :; }
t0=${EPOCHREALTIME/[.,]/}; for i in 1 2 3 4 5; do source ./terminal_renderer.sh; done; t1=${EPOCHREALTIME/[.,]/}
echo "terminal_renderer.sh ($(wc -l < terminal_renderer.sh) lines): $(( (t1-t0)/5000 )) ms per source"
for p in "$PAGES_DIR"/*_callbacks.sh; do
    [[ -r "$p" ]] || continue
    t0=${EPOCHREALTIME/[.,]/}; for i in 1 2 3; do source "$p" >/dev/null 2>&1; done; t1=${EPOCHREALTIME/[.,]/}
    printf '%-28s %4d lines   %4d ms per source   (raw source of renderer: %s)\n' "${p##*/}" "$(wc -l < "$p")" $(( (t1-t0)/3000 )) \
        "$(grep -c '^source .*terminal_renderer' "$p")"
done
