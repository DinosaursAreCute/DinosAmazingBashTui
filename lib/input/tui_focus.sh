#!/usr/bin/env bash
# tui_focus.sh - focus: which widgets can take it, in what Tab order, and how it moves.
#
# Per widget (markup attribute = tui.focus.set name):
#   focusable  true|false   can hold keyboard focus (default by type: interactive widgets yes, label/progress no)
#   tabbable   true|false   Tab visits it (default: same as focusable)
#   tab_order  N            0 = first, -1 = last, N > 0 ascending after 0, unset = document order; ties keep document order
#   focus_group G           widgets with the same G form a group
#   focus_nav  arrows|tab|both   (any member; default tab) arrows: one Tab stop per group, arrow keys move inside it
#   focus_wrap true|false   (any member) whether arrows wrap at the group's ends (default true)
#   focus_next ID / focus_prev ID   explicit successor / predecessor, overrides the order
#   autofocus  true         focused once when the page is first drawn
#
# _TUI_FOCUSABLE (document order, all focusable) and _TUI_FOCUS_TAB (Tab order) are derived by _tui_focus.rebuild,
# _TUI_FOCUS_POS maps id -> index in _TUI_FOCUS_TAB. _TUI_FOCUS_DIRTY marks them stale (_tui_w.changed, tui.focus.set);
# _tui_focus.ensure rebuilds on next use.
# Which widget types are focusable by default is part of the type's contract: "focusable:yes" in its
# tui.register.style_contract (lib/tui_registry.sh); the markup validator asks the same question.

# _tui_focus.default_focusable TYPE - rc 0 if TYPE takes focus unless focusable="false"
_tui_focus.default_focusable() {
	tui.registered style "$1" && [[ "$_TUI_REGISTERED" == *focusable:yes* ]]
}

declare -gA _TUI_W_FOCUSABLE=() _TUI_W_TABBABLE=() _TUI_W_TABORDER=() _TUI_W_FGROUP=() _TUI_W_FNAV=() _TUI_W_FWRAP=()
declare -gA _TUI_W_FNEXT=() _TUI_W_FPREV=() _TUI_W_AUTOFOCUS=()
declare -gA _TUI_FOCUS_POS=() _TUI_FOCUS_GNAV=() _TUI_FOCUS_GWRAP=() _TUI_FOCUS_REP=() _TUI_FOCUS_GLAST=()
declare -ga _TUI_FOCUS_TAB=()
declare -g _TUI_FOCUS_DIRTY=1 _TUI_FOCUS_WRAP=1 _TUI_FOCUS_AUTO=1

# tui.focus.set ID ATTR VALUE - set one focus attribute of widget ID (see the list above)
tui.focus.set() {
	local id="$1" v="$3"
	case "$2" in
		focusable | tabbable)
			case "$v" in
				true) v=1 ;;
				false) v=0 ;;
				*)
					echo "tui.focus.set: $2 takes true|false, got '$3'" >&2
					return 1
					;;
			esac
			if [[ "$2" == focusable ]]; then _TUI_W_FOCUSABLE[$id]=$v; else _TUI_W_TABBABLE[$id]=$v; fi
			;;
		tab_order) _TUI_W_TABORDER[$id]="$v" ;;
		focus_group) _TUI_W_FGROUP[$id]="$v" ;;
		focus_nav) _TUI_W_FNAV[$id]="$v" ;;
		focus_wrap) _TUI_W_FWRAP[$id]="$v" ;;
		focus_next) _TUI_W_FNEXT[$id]="$v" ;;
		focus_prev) _TUI_W_FPREV[$id]="$v" ;;
		autofocus)
			_TUI_W_AUTOFOCUS[$id]="$v"
			_TUI_FOCUS_AUTO=1
			;;
		*)
			echo "tui.focus.set: unknown attribute '$2'" >&2
			return 1
			;;
	esac
	_TUI_FOCUS_DIRTY=1
}

_tui_focus.ensure() {
	((_TUI_FOCUS_DIRTY)) && _tui_focus.rebuild
	return 0
}

_tui_focus.rebuild() {
	_tui_perf.begin focus_index
	local id g t o f i j n
	local -a first=() rest=() last=() vals=()
	local -A bucket=()
	_TUI_FOCUSABLE=() _TUI_FOCUS_TAB=() _TUI_FOCUS_POS=() _TUI_FOCUS_GNAV=() _TUI_FOCUS_GWRAP=() _TUI_FOCUS_REP=()
	_TUI_FOCUS_DIRTY=0

	for id in "${_TUI_W_ORDER[@]}"; do
		if [[ -n "${_TUI_W_FOCUSABLE[$id]:-}" ]]; then
			((_TUI_W_FOCUSABLE[$id])) || continue
		else
			_tui_focus.default_focusable "${_TUI_W_TYPE[$id]:-}" || continue
		fi
		_TUI_FOCUSABLE+=("$id")
		g="${_TUI_W_FGROUP[$id]:-}"
		if [[ -n "$g" ]]; then
			[[ -n "${_TUI_W_FNAV[$id]:-}" && -z "${_TUI_FOCUS_GNAV[$g]:-}" ]] && _TUI_FOCUS_GNAV[$g]="${_TUI_W_FNAV[$id]}"
			[[ -n "${_TUI_W_FWRAP[$id]:-}" && -z "${_TUI_FOCUS_GWRAP[$g]:-}" ]] && _TUI_FOCUS_GWRAP[$g]="${_TUI_W_FWRAP[$id]}"
		fi
	done

	for id in "${_TUI_FOCUSABLE[@]}"; do
		[[ "${_TUI_W_TABBABLE[$id]:-1}" == 1 ]] || continue
		g="${_TUI_W_FGROUP[$id]:-}"
		if [[ -n "$g" && "${_TUI_FOCUS_GNAV[$g]:-}" == arrows ]]; then
			[[ -n "${_TUI_FOCUS_REP[$g]:-}" ]] && continue # the group is one Tab stop: its first member
			_TUI_FOCUS_REP[$g]="$id"
		fi
		o="${_TUI_W_TABORDER[$id]:-}"
		case "$o" in
			0) first+=("$id") ;;
			-1) last+=("$id") ;;
			[1-9] | [1-9][0-9]*)
				[[ -z "${bucket[$o]:-}" ]] && vals+=("$o")
				bucket[$o]+="${bucket[$o]:+ }$id"
				;;
			*) rest+=("$id") ;;
		esac
	done

	n=${#vals[@]}
	for ((i = 1; i < n; i++)); do # insertion sort: a page has a handful of distinct tab_order values
		t="${vals[i]}"
		for ((j = i - 1; j >= 0 && vals[j] > t; j--)); do vals[j + 1]="${vals[j]}"; done
		vals[j + 1]="$t"
	done
	_TUI_FOCUS_TAB=("${first[@]}")
	for o in "${vals[@]}"; do
		# shellcheck disable=SC2206 # ids contain no whitespace
		_TUI_FOCUS_TAB+=(${bucket[$o]})
	done
	_TUI_FOCUS_TAB+=("${rest[@]}" "${last[@]}")

	for i in "${!_TUI_FOCUS_TAB[@]}"; do _TUI_FOCUS_POS[${_TUI_FOCUS_TAB[i]}]=$i; done
	for id in "${_TUI_FOCUSABLE[@]}"; do # members of an arrows group sit at their group's Tab stop
		g="${_TUI_W_FGROUP[$id]:-}"
		[[ -n "$g" && -z "${_TUI_FOCUS_POS[$id]+x}" && -n "${_TUI_FOCUS_REP[$g]:-}" ]] && _TUI_FOCUS_POS[$id]="${_TUI_FOCUS_POS[${_TUI_FOCUS_REP[$g]}]}"
	done
	_tui_perf.end focus_index
}

# tui.focus ID - Focuses a widget; its pane becomes the keyboard pane.
# The dirty set is known: the old and the new widget, plus the border of every pane whose keyboard focus changed. So the
# frame goes out raw in one flush, without the row diff of _tui_paint.flush (a hold of Up/Down pays this per repeat).
tui.focus() {
	local id="$1" old="$_TUI_FOCUS_ID" oldpf="$_TUI_PANE_FOCUS" newpane="${_TUI_W_PANE[$1]:-}" oldpane="" x seen=" "
	[[ -n "$old" ]] && oldpane="${_TUI_W_PANE[$old]:-}"
	_tui_focus.set "$id"
	local saved_frame="$_TUI_FRAME"
	_TUI_FRAME=""
	for x in "$old" "$id"; do
		[[ -z "$x" || "$seen" == *" $x "* ]] && continue
		seen+="$x "
		_tui._draw_widget_buf "$x"
	done
	if [[ "$oldpane" != "$newpane" || "$oldpf" != "$newpane" ]]; then
		seen=" "
		for x in "$oldpane" "$newpane" "$oldpf"; do
			[[ -z "$x" || "$seen" == *" $x "* ]] && continue
			seen+="$x "
			_tui._draw_pane_border_buf "$x"
		done
	fi
	local buf="$_TUI_FRAME"
	_TUI_FRAME="$saved_frame"
	[[ -n "$buf" ]] && _tui._flush "$buf"
}

# _tui_focus.set ID - the state half of tui.focus (no drawing)
_tui_focus.set() {
	local id="$1" newpane="${_TUI_W_PANE[$1]:-}" g="${_TUI_W_FGROUP[$1]:-}"
	_tui_focus.ensure
	_TUI_FOCUS_ID="$id"
	_TUI_FOCUS_IDX=-1
	[[ -n "${_TUI_FOCUS_POS[$id]+x}" ]] && _TUI_FOCUS_IDX="${_TUI_FOCUS_POS[$id]}"
	_TUI_PANE_FOCUS="$newpane" # the keyboard pane follows widget focus
	[[ -n "$newpane" ]] && _TUI_PANE_LAST_WIDGET[$newpane]="$id"
	[[ -n "$g" ]] && _TUI_FOCUS_GLAST[$g]="$id"
	_tui_text.is_text "$id" && _tui_text.on_focus "$id"
	return 0
}

# _tui_focus.step 1|-1 - Tab / shift+Tab: explicit focus_next/prev first, else the next stop in Tab order
_tui_focus.step() {
	_tui_focus.ensure
	local dir="$1" n=${#_TUI_FOCUS_TAB[@]} id="$_TUI_FOCUS_ID" i t g
	if [[ -n "$id" ]]; then
		((dir > 0)) && t="${_TUI_W_FNEXT[$id]:-}" || t="${_TUI_W_FPREV[$id]:-}"
		if [[ -n "$t" && -n "${_TUI_W_TYPE[$t]:-}" ]]; then
			tui.focus "$t"
			return 0
		fi
	fi
	((n)) || return 0
	i=-1
	[[ -n "$id" && -n "${_TUI_FOCUS_POS[$id]+x}" ]] && i="${_TUI_FOCUS_POS[$id]}"
	if ((i < 0)); then
		((dir > 0)) && i=0 || i=$((n - 1))
	else
		i=$((i + dir))
		if ((i < 0 || i >= n)); then
			((_TUI_FOCUS_WRAP)) || return 0
			i=$(((i + n) % n))
		fi
	fi
	t="${_TUI_FOCUS_TAB[i]}"
	g="${_TUI_W_FGROUP[$t]:-}"
	[[ -n "$g" && "${_TUI_FOCUS_REP[$g]:-}" == "$t" && -n "${_TUI_FOCUS_GLAST[$g]:-}" ]] && t="${_TUI_FOCUS_GLAST[$g]}"
	tui.focus "$t"
}

# _tui_focus.arrow up|down|left|right - arrow keys inside a focus_nav=arrows|both group; rc 1 if the key is not the group's
_tui_focus.arrow() {
	local id="$_TUI_FOCUS_ID" g step w i=-1 n
	[[ -n "$id" ]] || return 1
	g="${_TUI_W_FGROUP[$id]:-}"
	[[ -n "$g" ]] || return 1
	_tui_focus.ensure
	case "${_TUI_FOCUS_GNAV[$g]:-tab}" in arrows | both) ;; *) return 1 ;; esac
	case "$1" in up | left) step=-1 ;; *) step=1 ;; esac
	local -a members=()
	for w in "${_TUI_FOCUSABLE[@]}"; do
		[[ "${_TUI_W_FGROUP[$w]:-}" == "$g" ]] || continue
		[[ "$w" == "$id" ]] && i=${#members[@]}
		members+=("$w")
	done
	n=${#members[@]}
	((i < 0 || n < 2)) && return 0
	i=$((i + step))
	if ((i < 0 || i >= n)); then
		[[ "${_TUI_FOCUS_GWRAP[$g]:-true}" == false ]] && return 0
		i=$(((i + n) % n))
	fi
	tui.focus "${members[i]}"
}

# _tui_focus.autofocus - armed by every page reset, runs at the first render; once per page: focus the first (in Tab order) widget marked autofocus, without drawing
_tui_focus.autofocus() {
	((_TUI_FOCUS_AUTO)) || return 0
	_TUI_FOCUS_AUTO=0
	[[ -z "$_TUI_FOCUS_ID" ]] || return 0
	_tui_focus.ensure
	local id
	for id in "${_TUI_FOCUS_TAB[@]}"; do
		[[ "${_TUI_W_AUTOFOCUS[$id]:-}" == true ]] && {
			_tui_focus.set "$id"
			return 0
		}
	done
}
