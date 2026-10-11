#!/usr/bin/env bash
# map.sh - function index and coupling report for lib/.
# Index (default): one line per function, "name<TAB>file:line<TAB>summary". The summary is the
# comment directly above the definition, stripped of a leading "name ARGS -".
# Coupling (-c): per lib file, the _TUI_* arrays and _tui.* helpers it uses but does not define,
# as "file<TAB>arrays<TAB>helpers<TAB>direct<TAB>untagged". direct counts raw _TUI_[WP]_*[ accesses in
# functions tagged "# state:direct" (comment line directly above the definition: a known hot-path
# exception); untagged counts the rest, still to migrate. Names defined nowhere in lib/ are ignored.
# -p renders a table.
#
# Usage: tools/map.sh [PATTERN]            PATTERN filters by function name or file path (grep -E)
#        tools/map.sh -c|-p [PATTERN]      PATTERN filters by file path
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

coupling=0 pretty=0
while (($#)); do
	case $1 in
		-c | --coupling) coupling=1 ;;
		-p | --pretty) coupling=1 pretty=1 ;;
		*) break ;;
	esac
	shift
done

function_index() {
	find lib -name '*.sh' | sort | xargs awk '
		FNR == 1 { comment = "" }
		/^[[:space:]]*#/ { line = $0; sub(/^[[:space:]]*#[[:space:]]?/, "", line); if (comment == "") comment = line; next }
		/^[A-Za-z_][A-Za-z0-9_.]*[[:space:]]*\(\)/ {
			name = $0; sub(/[[:space:]]*\(\).*/, "", name)
			summary = comment; sub("^" name "[^-]*- ?", "", summary)
			printf "%s\t%s:%d\t%s\n", name, FILENAME, FNR, substr(summary, 1, 100)
		}
		{ comment = "" }
	'
}

# Each file is read twice (same list twice): the first pass records definitions, the second
# collects references to globally defined names that the file does not define itself.
coupling_report() {
	local files
	files=$(find lib -name '*.sh' | sort)
	# shellcheck disable=SC2086
	awk -v list="$files" '
		function sorted(set,    k, keys, n, i, j, t, out) {
			for (k in set) keys[++n] = k
			for (i = 2; i <= n; i++) { t = keys[i]; for (j = i - 1; j >= 1 && keys[j] > t; j--) keys[j + 1] = keys[j]; keys[j + 1] = t }
			for (i = 1; i <= n; i++) out = out (i > 1 ? " " : "") keys[i]
			return out
		}
		function define(file, line,    rest, tok) {
			if (line ~ /^[[:space:]]*(declare|local|typeset)[[:space:]]+-[a-zA-Z]*[aA]/) {
				rest = line
				while (match(rest, /_TUI_[A-Z0-9_]+/)) { tok = substr(rest, RSTART, RLENGTH); arr[tok] = 1; defarr[file SUBSEP tok] = 1; rest = substr(rest, RSTART + RLENGTH) }
			}
			if (match(line, /^[[:space:]]*_TUI_[A-Z0-9_]+=\(/)) { tok = substr(line, RSTART, RLENGTH); gsub(/[[:space:]=(]/, "", tok); arr[tok] = 1; defarr[file SUBSEP tok] = 1 }
			if (match(line, /^[[:space:]]*_(tui|ps)\.[A-Za-z0-9_.]+[[:space:]]*\(\)/)) { tok = substr(line, RSTART, RLENGTH); gsub(/[[:space:]()]/, "", tok); fn[tok] = 1; deffn[file SUBSEP tok] = 1 }
		}
		function reference(file, line,    rest, tok) {
			rest = line
			while (match(rest, /_TUI_[A-Z0-9_]+/)) { tok = substr(rest, RSTART, RLENGTH); if ((tok in arr) && !((file SUBSEP tok) in defarr)) usedarr[tok] = 1; rest = substr(rest, RSTART + RLENGTH) }
			rest = line
			while (match(rest, /_(tui|ps)\.[A-Za-z0-9_.]*[A-Za-z0-9_]/)) { tok = substr(rest, RSTART, RLENGTH); if ((tok in fn) && !((file SUBSEP tok) in deffn)) usedfn[tok] = 1; rest = substr(rest, RSTART + RLENGTH) }
		}
		BEGIN {
			nf = split(list, F, "\n")
			for (i = 1; i <= nf; i++) {
				while ((getline line < F[i]) > 0) if (line !~ /^[[:space:]]*#/) define(F[i], line)
				close(F[i])
			}
			for (i = 1; i <= nf; i++) {
				delete usedarr; delete usedfn
				tagged = 0; direct = 0; untagged = 0; prev = ""
				while ((getline line < F[i]) > 0) {
					if (line ~ /^[[:space:]]*#/) { prev = line; continue }
					if (line ~ /^[A-Za-z_][A-Za-z0-9_.]*[[:space:]]*\(\)/) tagged = (prev ~ /^# state:direct[[:space:]]*$/)
					else if (line ~ /^}/) tagged = 0
					prev = ""
					reference(F[i], line)
					copy = line; n = gsub(/_TUI_[WP]_[A-Z0-9_]+\[/, "&", copy)
					if (tagged) direct += n; else untagged += n
				}
				close(F[i])
				a = sorted(usedarr); h = sorted(usedfn)
				if (a != "" || h != "") printf "%s\t%s\t%s\t%d\t%d\n", F[i], a, h, direct, untagged
			}
		}
	'
}

if ((coupling)); then
	report=$(coupling_report | { if (($#)); then grep -E -- "$1"; else cat; fi; })
	if ((pretty)); then
		# shellcheck source=../lib/terminal_renderer.sh
		source lib/terminal_renderer.sh
		# table neither shrinks nor wraps, so fit the columns to an explicit width and wrap cells
		# at ", " into multi-line cells.
		TR_WIDTH=${COLUMNS:-$(tput cols 2>/dev/null)}
		[[ $TR_WIDTH =~ ^[0-9]+$ ]] || TR_WIDTH=80
		export TR_WIDTH
		rows=() file_w=4 array_w=0 helper_w=0
		while IFS="|" read -r file arrays helpers direct untagged; do
			arrays=${arrays// /, } helpers=${helpers// /, }
			rows+=("$file|$arrays|$helpers|$direct|$untagged")
			((${#file} > file_w)) && file_w=${#file}
			((${#arrays} > array_w)) && array_w=${#arrays}
			((${#helpers} > helper_w)) && helper_w=${#helpers}
		done <<<"${report//$'\t'/|}"
		# 5 columns cost 16 chars of borders and padding, the two count columns 18; the narrower list keeps its natural
		# width, the wider ones split the rest
		free=$((TR_WIDTH - 16 - 18 - file_w))
		if ((array_w + helper_w > free)); then
			half=$((free / 2))
			if ((array_w <= half)); then
				helper_w=$((free - array_w))
			elif ((helper_w <= half)); then
				array_w=$((free - helper_w))
			else array_w=$half helper_w=$((free - half)); fi
		fi
		((array_w < 12)) && array_w=12
		((helper_w < 12)) && helper_w=12
		wrapped=("file|arrays used, not defined|helpers used, not defined|direct|untagged")
		for row in "${rows[@]}"; do
			IFS="|" read -r file arrays helpers direct untagged <<<"$row"
			arrays=$(fold -s -w "$array_w" <<<"$arrays")
			helpers=$(fold -s -w "$helper_w" <<<"$helpers")
			wrapped+=("$file|$arrays|$helpers|$direct|$untagged")
		done
		table -r "${wrapped[@]}"
	else
		printf '%s\n' "$report"
	fi
else
	function_index | { if (($#)); then grep -E -- "$1"; else cat; fi; }
fi
