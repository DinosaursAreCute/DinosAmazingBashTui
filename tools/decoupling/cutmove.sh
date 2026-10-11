#!/usr/bin/env bash
# cutmove.sh SRC DEST HEADER RANGE... - pure cut-and-paste of line ranges (A-B, 1-based, of the current SRC) into a new
# module DEST: DEST = HEADER file + each range's lines (blank line between ranges); the ranges, and the single blank
# line after each, leave SRC. No line is edited. Check the result with tools/decoupling/verify_move.sh.
set -euo pipefail
src=$1 dest=$2 header=$3
shift 3
mkdir -p "$(dirname "$dest")"
{
	cat "$header"
	for r in "$@"; do
		printf '\n'
		sed -n "${r%-*},${r#*-}p" "$src"
	done
} >"$dest"
expr=""
for r in "$@"; do
	end=${r#*-}
	next=$(sed -n "$((end + 1))p" "$src")
	[[ -z $next ]] && end=$((end + 1))
	expr+="${r%-*},${end}d;"
done
sed -i "$expr" "$src"
