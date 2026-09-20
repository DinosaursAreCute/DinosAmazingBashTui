#!/usr/bin/env bash
# screenshot_all.sh [OUTDIR] [ROWSxCOLS] - screenshots of every DABT demo page x theme, plus the interesting tabs (case study table, every docu tab)
#   -> OUTDIR/<size>/<theme>/<page>.png  (default: tools/debug/screenshots, sizes 45x150 and 70x280). Extra args go to screenshots.py (e.g. --settle 1).
HERE="$(cd "$(dirname "$0")" && pwd)"
out="${1:-$HERE/screenshots}"; size="${2:-45x150,70x280}"; shift 2 2>/dev/null
rm -rf "$out"; python3 "$HERE/screenshots.py" -o "$out" -r "$size" "$@" && echo "done: $(find "$out" -name '*.png' | wc -l) screenshots in $out"
