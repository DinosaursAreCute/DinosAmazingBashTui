#!/usr/bin/env bash
# tui_data.sh - datasets: named rows that code appends to, changes and removes, and that widgets show without a handwritten refresh.
#
#   tui.data.new NAME [--cols "A|B"] [--key COL] [--max N] [--scope page|session|disk]   declare a dataset
#   tui.data.drop NAME                              forget a dataset and its rows
#   tui.data.append NAME ROW...                     add rows at the end (a keyed set replaces the row with that key)
#   tui.data.set NAME ID COL VALUE                  change one cell
#   tui.data.replace NAME ID ROW                    change a whole row
#   tui.data.remove NAME ID...                      delete rows
#   tui.data.clear NAME                             delete every row
#   tui.data.count NAME [VAR]                       number of rows
#   tui.data.has NAME ID                            rc 0 when a row with that id exists
#   tui.data.get NAME ID VAR                        a row, cells joined by |
#   tui.data.cell NAME ID COL VAR                   one cell
#   tui.data.rows NAME ARRAY [--last N]             rows into an array
#   tui.data.col NAME COL ARRAY [--last N]          one column into an array
#   tui.data.find NAME COL VALUE VAR                id of the first row whose cell equals VALUE
#   tui.data.stat NAME COL FN [VAR]                 sum, min, max, avg or count of a numeric column
#   tui.data.sort NAME COL [--desc] [--num]         sort in place
#   tui.data.bind NAME WIDGET KIND [OPTION...]      keep a widget showing the dataset (table, list, label, spark, gauge, chart)
#   tui.data.unbind WIDGET                          stop doing that
#   tui.data.flush                                  update the bound widgets of changed datasets now
#   tui.data.gen NAME VAR                           change counter of a dataset
#   tui.data.save NAME / tui.data.load NAME         write / read the disk copy of a dataset
#
# A row is a string of cells separated by |, like tui.table.set (a cell cannot contain |). An ID is the value of the key
# column for a keyed dataset (--key), else the 0-based index of the row. A COL is a 0-based index or a name from --cols.
# Numbers may have decimals; they are handled in thousandths, so no fork and no floating point is needed.
#
# Cost: append, get, cell, set and replace by key are O(1); remove, sort and clear rebuild the row array (O(n)); --max N drops
# the oldest row on append without shifting the others. Every change bumps the dataset's counter and marks it; the widgets
# bound to it are updated once, after the callback that changed it (tui.data.flush) or on the next tick, and only when the
# text they would show changed.
#
# Scope: page - dropped when the page is left; session (default) - kept for the run; disk - also written to
# $TUI_HOME/state/data/NAME at tui.data.save, at exit and when the page is left, and read by tui.data.new.
# State: _TD_R_NAME (rows), _TD_HEAD/_TD_TAIL[NAME] (first and next index; --max moves the head), _TD_IDX["NAME|KEY"], _TD_GEN[NAME].
# requires:

declare -gA _TD_COLS=() _TD_KEY=() _TD_MAX=() _TD_SCOPE=() _TD_GEN=() _TD_HEAD=() _TD_TAIL=() _TD_IDX=()
declare -gA _TD_DIRTY=() _TD_BOUND=() _TD_BIND=() _TD_OPT=() _TD_SHOWN=() _TD_CLASS=()
declare -gi _TD_PENDING=0
declare -gi _TD_COMPACT_AT=4096 # rows dropped from the head before the array is rebuilt without the holes
declare -g _TDI="" _TDC="" _TDN=0 _TDF=""

# _td.name NAME - rc 0 for a usable dataset name (it becomes part of a variable name)
_td.name() { [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; }

# _td.need NAME - rc 0 when NAME exists
_td.need() { [[ -n "${_TD_GEN[$1]+x}" ]]; }

# _td.col NAME COL -> _TDI: the 0-based column index of COL (a number or a --cols name); rc 1 when unknown
_td.col() {
	local cols="${_TD_COLS[$1]:-}" c i=0
	if [[ "$2" =~ ^[0-9]+$ ]]; then
		_TDI=$2
		return 0
	fi
	[[ -n "$cols" ]] || return 1
	local -a names
	IFS='|' read -ra names <<<"$cols"
	for c in "${names[@]}"; do
		[[ "$c" == "$2" ]] && {
			_TDI=$i
			return 0
		}
		((i++))
	done
	return 1
}

# _td.cell ROW COL -> _TDC: cell COL (0-based) of a row; empty when the row is shorter
_td.cell() {
	local -a c
	if ((${2} == 0)); then
		_TDC="${1%%|*}"
		return 0
	fi
	IFS='|' read -ra c <<<"$1"
	_TDC="${c[$2]:-}"
}

# _td.touch NAME - marks the dataset changed: bumps its counter and asks for a flush
_td.touch() {
	((_TD_GEN[$1]++))
	_TD_DIRTY[$1]=1
	_TD_PENDING=1
}

# _td.resolve NAME ID -> _TDI: the absolute index of the row ID names; rc 1 when there is none
_td.resolve() {
	local name="$1" id="$2"
	if [[ -n "${_TD_KEY[$name]:-}" ]]; then
		[[ -n "${_TD_IDX["$name|$id"]+x}" ]] || return 1
		_TDI="${_TD_IDX["$name|$id"]}"
		return 0
	fi
	[[ "$id" =~ ^[0-9]+$ ]] || return 1
	((id < _TD_TAIL[$name] - _TD_HEAD[$name])) || return 1
	_TDI=$((_TD_HEAD[$name] + id))
}

# _td.compact NAME - the rows into indexes 0..n-1 again and the key index rebuilt (after a remove, a sort or many drops)
_td.compact() {
	local name="$1" i n
	local -n r="_TD_R_$name"
	r=("${r[@]}")
	n=${#r[@]}
	_TD_HEAD[$name]=0
	_TD_TAIL[$name]=$n
	[[ -n "${_TD_KEY[$name]:-}" ]] || return 0
	local k
	for k in "${!_TD_IDX[@]}"; do [[ "$k" == "$name|"* ]] && unset '_TD_IDX[$k]'; done
	for ((i = 0; i < n; i++)); do
		_td.cell "${r[i]}" "${_TD_KEY[$name]}"
		_TD_IDX["$name|$_TDC"]=$i
	done
}

# _td.num VALUE -> _TDN (VALUE in thousandths), rc 1 when VALUE is not a number
_td.num() {
	local v="${1// /}" neg=0 int frac
	[[ "$v" =~ ^[+-]?[0-9]+([.,][0-9]+)?$ ]] || return 1
	[[ "$v" == -* ]] && neg=1
	v="${v#[+-]}"
	int="${v%%[.,]*}"
	frac=""
	[[ "$v" == *[.,]* ]] && frac="${v#*[.,]}"
	frac="${frac}000"
	_TDN=$((10#$int * 1000 + 10#${frac:0:3}))
	((neg)) && _TDN=$((-_TDN))
	return 0
}

# _td.fmt THOUSANDTHS -> _TDF: the number as text with the decimals it needs (12500 -> 12.5)
_td.fmt() {
	local n=$1 sign="" int frac
	((n < 0)) && {
		sign="-"
		n=$((-n))
	}
	int=$((n / 1000))
	printf -v frac '%03d' $((n % 1000))
	frac="${frac%"${frac##*[!0]}"}"
	_TDF="$sign$int${frac:+.$frac}"
}

# ── declare, drop ─────────────────────────────────────────────────────────

# tui.data.new NAME [--cols "A|B"] [--key COL] [--max N] [--scope page|session|disk] - declares a dataset. Declaring one that
# exists changes nothing, so a page may declare it on every visit. rc 1 for a bad name or option.
tui.data.new() {
	local name="${1:-}" cols="" key="" max=0 scope=session
	shift
	_td.name "$name" || return 1
	while (($#)); do
		case "$1" in
			--cols) cols="${2:-}" ;;
			--key) key="${2:-}" ;;
			--max) max="${2:-}" ;;
			--scope) scope="${2:-}" ;;
			*) return 1 ;;
		esac
		shift 2
	done
	[[ "$max" =~ ^[0-9]+$ && "$scope" == @(page|session|disk) ]] || return 1
	_td.need "$name" && return 0
	_TD_COLS[$name]="$cols" _TD_MAX[$name]=$max _TD_SCOPE[$name]="$scope"
	_TD_GEN[$name]=0 _TD_HEAD[$name]=0 _TD_TAIL[$name]=0
	declare -ga "_TD_R_$name=()"
	if [[ -n "$key" ]]; then
		_td.col "$name" "$key" || {
			_td.drop "$name"
			return 1
		}
		_TD_KEY[$name]=$_TDI
	else _TD_KEY[$name]=""; fi
	[[ "$scope" == disk ]] && {
		tui.hook.on exit _td.save_all # once per name is enough: the hook list ignores a function it has
		tui.data.load "$name"
	}
	return 0
}

# _td.drop NAME - removes every trace of a dataset
_td.drop() {
	local name="$1" k w
	for k in "${!_TD_IDX[@]}"; do [[ "$k" == "$name|"* ]] && unset '_TD_IDX[$k]'; done
	for w in ${_TD_BOUND[$name]:-}; do tui.data.unbind "$w"; done
	unset "_TD_R_$name" '_TD_COLS[$name]' '_TD_KEY[$name]' '_TD_MAX[$name]' '_TD_SCOPE[$name]' '_TD_GEN[$name]' \
		'_TD_HEAD[$name]' '_TD_TAIL[$name]' '_TD_DIRTY[$name]' '_TD_BOUND[$name]'
}

# tui.data.drop NAME - forgets a dataset, its rows and its widget bindings
tui.data.drop() {
	_td.need "${1:-}" || return 1
	_td.drop "$1"
}

# ── change ────────────────────────────────────────────────────────────────

# tui.data.append NAME ROW... - adds rows at the end; in a keyed dataset a row whose key exists replaces that row. With --max N
# the oldest rows go when there are more than N. rc 1 for an unknown dataset.
tui.data.append() {
	local name="${1:-}" row h
	shift
	_td.need "$name" || return 1
	local -n r="_TD_R_$name"
	local key="${_TD_KEY[$name]}" max=${_TD_MAX[$name]}
	for row in "$@"; do
		if [[ -n "$key" ]]; then
			_td.cell "$row" "$key"
			if [[ -n "${_TD_IDX["$name|$_TDC"]+x}" ]]; then
				r[${_TD_IDX["$name|$_TDC"]}]="$row"
				continue
			fi
			_TD_IDX["$name|$_TDC"]=${_TD_TAIL[$name]}
		fi
		r[_TD_TAIL[$name]]="$row"
		((_TD_TAIL[$name]++))
		if ((max > 0 && _TD_TAIL[$name] - _TD_HEAD[$name] > max)); then
			h=${_TD_HEAD[$name]}
			if [[ -n "$key" ]]; then
				_td.cell "${r[h]}" "$key"
				unset '_TD_IDX["$name|$_TDC"]'
			fi
			unset 'r[h]'
			((_TD_HEAD[$name]++))
		fi
	done
	((_TD_HEAD[$name] > _TD_COMPACT_AT && _TD_HEAD[$name] > _TD_TAIL[$name] - _TD_HEAD[$name])) && _td.compact "$name" # the dropped head left holes
	_td.touch "$name"
}

# _td.put NAME INDEX ROW - stores a row at an absolute index, moving its key entry when the key cell changed
_td.put() {
	local name="$1" i="$2" row="$3" old
	local -n r="_TD_R_$name"
	if [[ -n "${_TD_KEY[$name]}" ]]; then
		_td.cell "${r[i]}" "${_TD_KEY[$name]}"
		old="$_TDC"
		_td.cell "$row" "${_TD_KEY[$name]}"
		if [[ "$old" != "$_TDC" ]]; then
			unset '_TD_IDX["$name|$old"]'
			_TD_IDX["$name|$_TDC"]=$i
		fi
	fi
	r[i]="$row"
}

# tui.data.set NAME ID COL VALUE - changes one cell of a row. rc 1 for an unknown dataset, row or column.
tui.data.set() {
	local name="${1:-}" id="${2:-}" i c k row
	_td.need "$name" && _td.resolve "$name" "$id" || return 1
	i=$_TDI
	_td.col "$name" "${3:-}" || return 1
	c=$_TDI
	local -n r="_TD_R_$name"
	local -a cells
	IFS='|' read -ra cells <<<"${r[i]}"
	for ((k = ${#cells[@]}; k <= c; k++)); do cells[k]=""; done
	cells[c]="${4-}"
	printf -v row '%s|' "${cells[@]}"
	_td.put "$name" "$i" "${row%|}"
	_td.touch "$name"
}

# tui.data.replace NAME ID ROW - changes a whole row. rc 1 for an unknown dataset or row.
tui.data.replace() {
	_td.need "${1:-}" && _td.resolve "$1" "${2:-}" || return 1
	_td.put "$1" "$_TDI" "${3-}"
	_td.touch "$1"
}

# tui.data.remove NAME ID... - deletes rows; ids that do not exist are skipped. The row array is rebuilt once.
tui.data.remove() {
	local name="${1:-}" id i n=0
	shift
	_td.need "$name" || return 1
	local -n r="_TD_R_$name"
	local -A gone=()
	for id in "$@"; do
		_td.resolve "$name" "$id" && gone[$_TDI]=1
	done
	((${#gone[@]})) || return 0
	local -a keep=()
	for ((i = _TD_HEAD[$name]; i < _TD_TAIL[$name]; i++)); do
		[[ -n "${gone[$i]:-}" ]] || keep+=("${r[i]}")
	done
	r=("${keep[@]}")
	_td.compact "$name"
	_td.touch "$name"
}

# tui.data.clear NAME - deletes every row (the dataset stays declared and bound).
tui.data.clear() {
	_td.need "${1:-}" || return 1
	local -n r="_TD_R_$1"
	r=()
	_td.compact "$1"
	_td.touch "$1"
}

# ── read ──────────────────────────────────────────────────────────────────

# The functions below take the name of a caller's variable or array (VAR, ARRAY). Their own locals start with _ so that a
# caller's `n`, `row` or `c` is never shadowed by a local of the same name.

# tui.data.count NAME [VAR] - the number of rows; printed when VAR is missing.
tui.data.count() {
	_td.need "${1:-}" || return 1
	local _n=$((_TD_TAIL[$1] - _TD_HEAD[$1]))
	if [[ -n "${2:-}" ]]; then printf -v "$2" '%s' "$_n"; else printf '%s\n' "$_n"; fi
}

# tui.data.has NAME ID - rc 0 when a row with that id exists.
tui.data.has() { _td.need "${1:-}" && _td.resolve "$1" "${2:-}"; }

# tui.data.get NAME ID VAR - the row ID in VAR (rc 1 when there is none).
tui.data.get() {
	_td.need "${1:-}" && _td.resolve "$1" "${2:-}" || return 1
	local -n _r="_TD_R_$1"
	printf -v "$3" '%s' "${_r[_TDI]}"
}

# tui.data.cell NAME ID COL VAR - one cell in VAR (rc 1 when the row or column is unknown).
tui.data.cell() {
	_td.need "${1:-}" && _td.resolve "$1" "${2:-}" || return 1
	local _i=$_TDI
	_td.col "$1" "${3:-}" || return 1
	local -n _r="_TD_R_$1"
	_td.cell "${_r[_i]}" "$_TDI"
	printf -v "$4" '%s' "$_TDC"
}

# tui.data.rows NAME ARRAY [--last N] - the rows, oldest first, into the array ARRAY (only the newest N with --last).
tui.data.rows() {
	_td.need "${1:-}" || return 1
	local -n _r="_TD_R_$1" _o="$2"
	local _from=${_TD_HEAD[$1]} _to=${_TD_TAIL[$1]}
	[[ "${3:-}" == --last && "${4:-}" =~ ^[0-9]+$ ]] && ((_to - _from > $4)) && _from=$((_to - $4))
	_o=("${_r[@]:_from:_to-_from}")
}

# tui.data.col NAME COL ARRAY [--last N] - one column, oldest first, into the array ARRAY.
tui.data.col() {
	_td.need "${1:-}" && _td.col "$1" "${2:-}" || return 1
	local _c=$_TDI _i
	local -n _r="_TD_R_$1" _o="$3"
	local _from=${_TD_HEAD[$1]} _to=${_TD_TAIL[$1]}
	[[ "${4:-}" == --last && "${5:-}" =~ ^[0-9]+$ ]] && ((_to - _from > $5)) && _from=$((_to - $5))
	_o=()
	for ((_i = _from; _i < _to; _i++)); do
		_td.cell "${_r[_i]}" "$_c"
		_o+=("$_TDC")
	done
}

# tui.data.find NAME COL VALUE VAR - the id of the first row whose cell COL equals VALUE (rc 1 when none does).
tui.data.find() {
	_td.need "${1:-}" && _td.col "$1" "${2:-}" || return 1
	local _c=$_TDI _i
	local -n _r="_TD_R_$1"
	for ((_i = _TD_HEAD[$1]; _i < _TD_TAIL[$1]; _i++)); do
		_td.cell "${_r[_i]}" "$_c"
		[[ "$_TDC" == "${3-}" ]] || continue
		if [[ -n "${_TD_KEY[$1]}" ]]; then
			_td.cell "${_r[_i]}" "${_TD_KEY[$1]}"
			printf -v "$4" '%s' "$_TDC"
		else printf -v "$4" '%s' "$((_i - _TD_HEAD[$1]))"; fi
		return 0
	done
	return 1
}

# tui.data.stat NAME COL FN [VAR] - sum, min, max, avg or count of the numeric cells of a column (cells that are not numbers
# are skipped); printed when VAR is missing. min, max and avg of no numbers give an empty result and rc 1.
tui.data.stat() {
	_td.need "${1:-}" && _td.col "$1" "${2:-}" || return 1
	local _c=$_TDI _fn="${3:-}" _i _n=0 _sum=0 _min="" _max="" _out=""
	local -n _r="_TD_R_$1"
	[[ "$_fn" == @(sum|min|max|avg|count) ]] || return 1
	for ((_i = _TD_HEAD[$1]; _i < _TD_TAIL[$1]; _i++)); do
		_td.cell "${_r[_i]}" "$_c"
		_td.num "$_TDC" || continue
		((_n++, _sum += _TDN))
		{ [[ -z "$_min" ]] || ((_TDN < _min)); } && _min=$_TDN
		{ [[ -z "$_max" ]] || ((_TDN > _max)); } && _max=$_TDN
	done
	case "$_fn" in
		count) _out="$_n" ;;
		sum) _td.fmt "$_sum" && _out="$_TDF" ;;
		min) ((_n)) && _td.fmt "$_min" && _out="$_TDF" ;;
		max) ((_n)) && _td.fmt "$_max" && _out="$_TDF" ;;
		avg) ((_n)) && _td.fmt $((_sum / _n)) && _out="$_TDF" ;;
	esac
	if [[ -n "${4:-}" ]]; then printf -v "$4" '%s' "$_out"; else printf '%s\n' "$_out"; fi
	[[ "$_fn" == @(count|sum) ]] || ((_n))
}

# ── sort ──────────────────────────────────────────────────────────────────

# _td.less KEY_A KEY_B NUMERIC - rc 0 when A sorts before B
_td.less() {
	if (($3)); then
		local a=0 b=0
		_td.num "$1" && a=$_TDN
		_td.num "$2" && b=$_TDN
		((a < b))
	else [[ "$1" < "$2" ]]; fi
}

# tui.data.sort NAME COL [--desc] [--num] - sorts the rows in place, stable. --num compares the cells as numbers.
tui.data.sort() {
	local name="${1:-}" desc=0 num=0 c n i lo mid hi k a b
	_td.need "$name" && _td.col "$name" "${2:-}" || return 1
	c=$_TDI
	shift 2
	while (($#)); do
		case "$1" in
			--desc) desc=1 ;;
			--num) num=1 ;;
			*) return 1 ;;
		esac
		shift
	done
	local -n r="_TD_R_$name"
	_td.compact "$name"
	n=${#r[@]}
	((n > 1)) || return 0
	local -a rows=("${r[@]}") keys=() src dst skey dkey
	for ((i = 0; i < n; i++)); do
		_td.cell "${rows[i]}" "$c"
		keys[i]="$_TDC"
	done
	# bottom-up merge sort of the indexes 0..n-1 by key
	local -a idx=() tmp=()
	for ((i = 0; i < n; i++)); do idx[i]=$i; done
	local w
	for ((w = 1; w < n; w *= 2)); do
		for ((lo = 0; lo < n; lo += 2 * w)); do
			mid=$((lo + w))
			hi=$((lo + 2 * w))
			((mid > n)) && mid=$n
			((hi > n)) && hi=$n
			a=$lo b=$mid k=$lo
			while ((a < mid && b < hi)); do
				if ((desc)); then
					if _td.less "${keys[idx[a]]}" "${keys[idx[b]]}" $num; then tmp[k++]=${idx[b++]}; else tmp[k++]=${idx[a++]}; fi
				else
					if _td.less "${keys[idx[b]]}" "${keys[idx[a]]}" $num; then tmp[k++]=${idx[b++]}; else tmp[k++]=${idx[a++]}; fi
				fi
			done
			while ((a < mid)); do tmp[k++]=${idx[a++]}; done
			while ((b < hi)); do tmp[k++]=${idx[b++]}; done
		done
		idx=("${tmp[@]}")
	done
	r=()
	for ((i = 0; i < n; i++)); do r[i]="${rows[idx[i]]}"; done
	_td.compact "$name"
	_td.touch "$name"
}

# tui.data.gen NAME VAR - the change counter of a dataset in VAR: it grows with every change, so code can tell whether
# something changed since it last looked.
tui.data.gen() {
	_td.need "${1:-}" || return 1
	printf -v "$2" '%s' "${_TD_GEN[$1]}"
}

# ── disk ──────────────────────────────────────────────────────────────────

# _td.file NAME -> _TDF: the disk copy of a dataset ($TUI_HOME/state/data/NAME); rc 1 without a TUI_HOME
_td.file() {
	[[ -n "${TUI_HOME:-}" ]] || return 1
	_TDF="$TUI_HOME/state/data/$1"
}

# tui.data.save NAME - writes the rows to the disk copy: one row per line, \ and newlines escaped, a temp file moved into
# place. rc 1 without a TUI_HOME or for an unknown dataset.
tui.data.save() {
	local name="${1:-}" row out="" i dir
	_td.need "$name" && _td.file "$name" || return 1
	local -n r="_TD_R_$name"
	for ((i = _TD_HEAD[$name]; i < _TD_TAIL[$name]; i++)); do
		row="${r[i]//\\/\\\\}"
		row="${row//$'\n'/\\n}"
		out+="$row"$'\n'
	done
	dir="${_TDF%/*}"
	mkdir -p "$dir" 2>/dev/null || return 1
	printf '%s' "$out" >"$_TDF.tmp.$$" 2>/dev/null && mv -f "$_TDF.tmp.$$" "$_TDF"
}

# tui.data.load NAME - reads the disk copy into the dataset, replacing its rows. A missing copy leaves it as it is (rc 1).
tui.data.load() {
	local name="${1:-}" line
	_td.need "$name" && _td.file "$name" && [[ -r "$_TDF" ]] || return 1
	local -a rows=()
	while IFS= read -r line || [[ -n "$line" ]]; do
		line="${line//\\n/$'\n'}"
		rows+=("${line//\\\\/\\}")
	done <"$_TDF"
	tui.data.clear "$name"
	((${#rows[@]})) && tui.data.append "$name" "${rows[@]}"
	return 0
}

# _td.save_all - writes every disk-scope dataset (the exit hook)
_td.save_all() {
	local name
	for name in "${!_TD_SCOPE[@]}"; do [[ "${_TD_SCOPE[$name]}" == disk ]] && tui.data.save "$name"; done
	return 0
}

# _td.leave_page - the page is going away: page-scope datasets are dropped, disk ones are written
_td.leave_page() {
	local name
	((${#_TD_SCOPE[@]})) || return 0
	for name in "${!_TD_SCOPE[@]}"; do
		case "${_TD_SCOPE[$name]}" in
			page) _td.drop "$name" ;;
			disk) tui.data.save "$name" ;;
		esac
	done
	return 0
}

# ── bind ──────────────────────────────────────────────────────────────────

# tui.data.bind NAME WIDGET KIND [OPTION=VALUE...] - keeps WIDGET showing the dataset. KIND and its options:
#   table            a <table>: the --cols names as header and every row (a keyed dataset keeps the selected row)
#   list             a <list>: one item per row, the cells of col
#   label            a <label>: the cell col of the newest row, shown with format (a printf format with one %s, default "%s")
#   spark            a <label>: one glyph per value of col, the newest last values (default 24), width cells wide
#   gauge            a <label>: the newest value of col as a bar of width cells (default 20) out of max (default 100)
#   chart            a <pane>: tui.chart of type (default linechart) over col, label and last, plus args (renderer flags)
# col is a 0-based index or a --cols name (default 0). Binding a widget again replaces its binding. rc 1 for an unknown
# dataset or kind.
tui.data.bind() {
	local name="${1:-}" w="${2:-}" kind="${3:-}" o
	_td.need "$name" || return 1
	[[ "$kind" == @(table|list|label|spark|gauge|chart) && -n "$w" ]] || return 1
	shift 3
	tui.data.unbind "$w"
	_TD_BIND[$w]="$name|$kind"
	for o in "$@"; do _TD_OPT["$w|${o%%=*}"]="${o#*=}"; done
	_TD_BOUND[$name]+=" $w"
	_TD_DIRTY[$name]=1
	_TD_PENDING=1
	tui.tick.add _td.tick
	return 0
}

# tui.data.unbind WIDGET - removes the binding of a widget.
tui.data.unbind() {
	local w="${1:-}" name k
	[[ -n "${_TD_BIND[$w]+x}" ]] || return 0
	name="${_TD_BIND[$w]%%|*}"
	_TD_BOUND[$name]="${_TD_BOUND[$name]/ $w/}"
	for k in "${!_TD_OPT[@]}"; do [[ "$k" == "$w|"* ]] && unset '_TD_OPT[$k]'; done
	unset '_TD_BIND[$w]' '_TD_SHOWN[$w]' '_TD_CLASS[$w]'
}

# _td.opt WIDGET NAME DEFAULT -> _TDF: an option of the widget's binding
_td.opt() { _TDF="${_TD_OPT["$1|$2"]-$3}"; }

# _td.project NAME SPEC - narrows hdr, keep and rows (locals of _td.show) to the columns of SPEC, comma separated names or indexes
_td.project() {
	local _c _i _r _p
	local -a _idx=() _all=() _cells=() _out=() _h=()
	IFS='|' read -ra _all <<<"${_TD_COLS[$1]}"
	for _c in ${2//,/ }; do
		_td.col "$1" "$_c" || continue
		_idx+=("$_TDI")
		_h+=("${_all[_TDI]:-$_c}")
	done
	((${#_idx[@]})) || return 0
	keep=""
	for _i in "${!_idx[@]}"; do [[ "${_idx[_i]}" == "${_TD_KEY[$1]}" ]] && keep=$_i; done
	for _r in "${rows[@]}"; do
		IFS='|' read -ra _cells <<<"$_r"
		_p=""
		for _i in "${_idx[@]}"; do _p+="${_cells[_i]:-}|"; done
		_out+=("${_p%|}")
	done
	rows=("${_out[@]}")
	printf -v hdr '%s|' "${_h[@]}"
	hdr="${hdr%|}"
}

# _td.fit WIDGET [PAD] -> _TDF: the content width of the widget's pane less PAD (default 2: a one-cell padding each side), at least 4.
# What width=fit means: a spark or gauge as wide as the room it sits in. The width is read when the widget is drawn, so a
# resized terminal gets it at the next change of the data.
_td.fit() {
	local p="${_TUI_W_PANE[$1]:-$1}"
	_tui._content_rect "$p" 2>/dev/null
	_TDF=$((${_CR_W:-0} - ${2:-2}))
	((_TDF < 4)) && _TDF=6 # the pane has no size yet (or none to spare): a small bar now, the real width at the next change
	return 0
}

# _td.fit_h WIDGET [PAD] -> _TDF: the content height of a pane less PAD (default 3: the axis and the legend of a chart), at least 3
_td.fit_h() {
	_tui._content_rect "$1" 2>/dev/null
	_TDF=$((${_CR_H:-0} - ${2:-3}))
	((_TDF < 3)) && _TDF=6
	return 0
}

# _td.level WIDGET VALUE MAX - gauge levels: "levels=WARN,CRIT" (percent of MAX) restyles the widget with gauge_ok, gauge_warn or
# gauge_crit when the level changes
_td.level() {
	local lv w c pct v m cls
	_td.opt "$1" levels ""
	lv="$_TDF"
	[[ -n "$lv" ]] || return 0
	_td.num "$2" && v=$_TDN || v=0
	_td.num "$3" && m=$_TDN || m=100000
	((m > 0)) || m=1000
	pct=$((v * 100 / m))
	w="${lv%%,*}" c="${lv#*,}"
	if ((pct >= c)); then cls=gauge_crit; elif ((pct >= w)); then cls=gauge_warn; else cls=gauge_ok; fi
	[[ "${_TD_CLASS[$1]-}" == "$cls" ]] && return 0
	_TD_CLASS[$1]="$cls"
	tui.restyle "$1" "$cls"
}

# _td.heat WIDGET HEADER - the heat= option of a bound table: "col:WARN:HOT,col:WARN:HOT" colours the numbers of those columns
# (names of the shown header, or indexes into it) with tui.table.heat
_td.heat() {
	local spec c warn hot i
	local -a hdr=()
	_td.opt "$1" heat ""
	[[ -n "$_TDF" ]] || return 0
	IFS='|' read -ra hdr <<<"$2"
	for spec in ${_TDF//,/ }; do
		IFS=: read -r c warn hot <<<"$spec"
		if [[ "$c" =~ ^[0-9]+$ ]]; then
			tui.table.heat "$1" "$c" "$warn" "$hot"
			continue
		fi
		for i in "${!hdr[@]}"; do [[ "${hdr[i]}" == "$c" ]] && tui.table.heat "$1" "$i" "$warn" "$hot"; done
	done
}

# _td.show WIDGET KIND NAME - draws one binding, unless what it shows is what it showed
_td.show() {
	local w="$1" kind="$2" name="$3" col last text fmt max width type args lab cls i pad cellv
	local -a vals=() items=() rows=() extra=() feed=()
	_td.opt "$w" col 0
	col="$_TDF"
	if [[ "$kind" != chart || "$col" != *,* ]]; then # a chart may name several columns, comma separated: one series each
		_td.col "$name" "$col" || return 0
		col=$_TDI
	fi
	case "$kind" in
		table)
			local hdr="${_TD_COLS[$name]}" keep="${_TD_KEY[$name]}"
			tui.data.rows "$name" rows
			_td.opt "$w" show ""
			[[ -n "$_TDF" ]] && _td.project "$name" "$_TDF" # show= picks the columns: hdr, keep and rows follow
			text="$hdr|${rows[*]}"
			[[ "${_TD_SHOWN[$w]-}" == "$text" ]] && return 0
			_TD_SHOWN[$w]="$text"
			if [[ -n "$keep" ]]; then
				tui.table.set --keep "$keep" "$w" "$hdr" "${rows[@]}"
			else tui.table.set "$w" "$hdr" "${rows[@]}"; fi
			_td.heat "$w" "$hdr"
			;;
		list)
			tui.data.col "$name" "$col" items
			text="${items[*]}"
			[[ "${_TD_SHOWN[$w]-}" == "$text" ]] && return 0
			_TD_SHOWN[$w]="$text"
			tui.list.set "$w" "${items[@]}"
			;;
		label | spark | gauge)
			_td.opt "$w" last 24
			last="$_TDF"
			_td.opt "$w" key ""
			if [[ -n "$_TDF" && "$kind" != spark ]]; then # key=ID: the cell of that row of a keyed dataset instead of the newest row
				tui.data.cell "$name" "$_TDF" "$col" cellv || cellv=""
				vals=("$cellv")
			elif [[ "$kind" == label ]]; then
				tui.data.col "$name" "$col" vals --last 1
			else tui.data.col "$name" "$col" vals --last "$last"; fi
			_td.opt "$w" width 0
			width="$_TDF"
			if [[ "$width" == fit ]]; then # a gauge adds " 100%" to its bar: leave room for it
				if [[ "$kind" == gauge ]]; then _td.fit "$w" 8; else _td.fit "$w" 3; fi
				width="$_TDF"
			fi
			case "$kind" in
				label)
					_td.opt "$w" format "%s"
					printf -v text "$_TDF" "${vals[0]:-}"
					;;
				spark) tui.chart.spark text -w "${width:-0}" "${vals[@]}" ;;
				gauge)
					_td.opt "$w" max 100
					max="$_TDF"
					[[ "$width" == 0 ]] && width=20
					tui.chart.gauge text "${vals[-1]:-0}" "$max" -w "$width"
					_td.level "$w" "${vals[-1]:-0}" "$max"
					;;
			esac
			[[ "${_TD_SHOWN[$w]-}" == "$text" ]] && return 0
			_TD_SHOWN[$w]="$text"
			tui.set_label "$w" "$text"
			;;
		chart)
			_td.opt "$w" type linechart
			type="$_TDF"
			_td.opt "$w" args ""
			read -ra extra <<<"$_TDF"
			for i in "${!extra[@]}"; do # -w fit / -h fit: the size of the pane the chart is in, less what the chart draws around its plot
				[[ "${extra[i]}" == fit ]] || continue
				case "$type" in
					hbar | vbar) pad=16 ;;                     # the label before the bar and the value after it
					linechart | histogram | scatter) pad=12 ;; # the y axis
					boxplot | forest) pad=30 ;;                # the name before and the numbers after
					*) pad=5 ;;
				esac
				if [[ "${extra[i - 1]:-}" == -w ]]; then
					_td.fit "$w" "$pad"
					extra[i]="$_TDF"
				elif [[ "${extra[i - 1]:-}" == -h ]]; then
					_td.fit_h "$w" 5
					extra[i]="$_TDF"
				fi
			done
			_td.opt "$w" label ""
			lab="$_TDF"
			_td.opt "$w" last 0
			last="$_TDF"
			_td.opt "$w" class ""
			cls="$_TDF"
			feed=(--data "$name" --col "$col")
			[[ -n "$lab" ]] && feed+=(--label "$lab")
			((last > 0)) && feed+=(--last "$last")
			[[ -n "$cls" ]] && feed+=(--class "$cls")
			tui.chart "$type" text "${feed[@]}" "${extra[@]}" || return 0
			[[ "${_TD_SHOWN[$w]-}" == "$text" ]] && return 0
			_TD_SHOWN[$w]="$text"
			tui.output "$w" "$text"
			;;
	esac
}

# tui.data.flush - updates the widgets bound to datasets that changed since the last flush, each only when what it shows
# changed. It runs by itself after a callback and on every tick; call it to draw inside a long callback.
tui.data.flush() {
	((_TD_PENDING)) || return 0
	_TD_PENDING=0
	local name w b
	for name in "${!_TD_DIRTY[@]}"; do
		unset '_TD_DIRTY[$name]'
		for w in ${_TD_BOUND[$name]:-}; do
			b="${_TD_BIND[$w]:-}"
			[[ -n "$b" ]] && tui.exists "$w" && _td.show "$w" "${b#*|}" "$name"
		done
	done
	return 0
}

# _td.tick - the tick listener: flushes pending changes
_td.tick() {
	((_TD_PENDING)) || return 0
	_TUI_BATCH_PACED=1
	_tui.batch_call tui.data.flush
	_TUI_BATCH_PACED=0
}

# _td.reset - tui.reset_ui: page-scope datasets go with the page, and every binding (its widget is gone)
_td.reset() {
	local name
	((${#_TD_GEN[@]})) || return 0
	_td.leave_page
	for name in "${!_TD_BOUND[@]}"; do _TD_BOUND[$name]=""; done
	_TD_BIND=() _TD_OPT=() _TD_SHOWN=() _TD_CLASS=()
}
