#!/usr/bin/env bash
# map.sh - function index for lib/: one line per function, "name<TAB>file:line<TAB>summary".
# The summary is the comment directly above the definition, stripped of a leading "name ARGS -".
#
# Usage: tools/map.sh [PATTERN]     PATTERN filters by function name or file path (grep -E)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

find lib -name '*.sh' | sort | xargs awk '
	FNR == 1 { comment = "" }
	/^[[:space:]]*#/ { line = $0; sub(/^[[:space:]]*#[[:space:]]?/, "", line); if (comment == "") comment = line; next }
	/^[A-Za-z_][A-Za-z0-9_.]*[[:space:]]*\(\)/ {
		name = $0; sub(/[[:space:]]*\(\).*/, "", name)
		summary = comment; sub("^" name "[^-]*- ?", "", summary)
		printf "%s\t%s:%d\t%s\n", name, FILENAME, FNR, substr(summary, 1, 100)
	}
	{ comment = "" }
' | { if (($#)); then grep -E -- "$1"; else cat; fi; }
