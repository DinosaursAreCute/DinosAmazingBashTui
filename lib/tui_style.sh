#!/usr/bin/env bash
# tui_style.sh - CSS-like theming for tui.sh (pure bash + POSIX utilities).
#
# Stylesheet format (see config/theme.css):
#   .classname { fg: red; bg: black; mods: bold underline; }
#   .classname:focus { ... }   applied while a widget is focused; on a pane,
#                               applied to its border ring while any widget
#                               inside it is focused - see _tui._draw_pane_border
#                               and _tui._draw_widget in tui.sh.
#   .classname:border { ... }  a pane's border in its normal (unfocused) state
#   .classname:title { ... }   applied to a pane's title text
#   .classname:hover { ... }   applied to a *widget* (button/input) while the
#                               mouse is over it; a widget with no :hover
#                               rules keeps its normal look. Has no effect on
#                               panes - pane borders only react to :focus.
#   .classname:checked { ... } / :unchecked { ... }   a checkbox's look while on / off (focus and hover still
#                               win; fields left out fall back to the normal look).
#
# fg/bg accept a colors.sh name (e.g. "red") or a "#RRGGBB" hex value.
# mods is a space-separated list of style.* modifiers (e.g. "bold underline").
#
# tui.load_theme FILE   parses a stylesheet into the class table.
# tui.class ID CLASS    applies a class's rules to a pane or widget id.
# tui.style ID:STATE FG BG MODS   sets style directly, bypassing classes.
#   STATE is one of: normal (default), focus, border, title, hover, checked, unchecked.

declare -gA _TUI_STYLE_FG=() _TUI_STYLE_BG=() _TUI_STYLE_MOD=()
declare -gA _TUI_CLASS_FG=() _TUI_CLASS_BG=() _TUI_CLASS_MOD=()
declare -g _TUI_THEME_OVERLAY=""

# tui.style ID FG BG MODS [STATE]  - low-level setter behind tui.class.
tui.style() {
	local id="$1" fg="$2" bg="$3" mods="$4" state="${5:-normal}"
	local key="${id}_${state}"
	[[ -n "$fg" ]] && _TUI_STYLE_FG[$key]="$fg"
	[[ -n "$bg" ]] && _TUI_STYLE_BG[$key]="$bg"
	[[ -n "$mods" ]] && _TUI_STYLE_MOD[$key]="$mods"
}

# ── theme loading ───────────────────────────────────────────────────────
# tui.load_theme FILE - parse a .css-like stylesheet into the class table.
#   Split in three so tui_cache.sh can memoize the middle one without this file knowing:
#     _tui.theme_parse   FILE   pure, fork-free parse of one file into _TP_* (touches no class table)
#     _tui.theme_commit         copies _TP_* into _TUI_CLASS_* (later files override earlier ones)
#     _tui.theme_load_file FILE parse + commit + collision check. tui_cache.sh REDEFINES this with a
#                               memoized version (parsed once per file, re-applied from memory).
declare -gA _TP_FG=() _TP_BG=() _TP_MOD=() _TP_SEEN=()
declare -ga _TP_ORDER=()

# Records one declaration of the rule being parsed.
_tui.theme_decl() { # CLASS KEY VALUE
	local cls="$1" key="$2" val="$3"
	val="${val#"${val%%[![:space:]]*}"}"
	val="${val%"${val##*[![:space:]]}"}"
	if [[ -z "${_TP_SEEN[$cls]:-}" ]]; then
		_TP_SEEN[$cls]=1
		_TP_ORDER+=("$cls")
	fi
	case "$key" in
		fg) _TP_FG[$cls]="$val" ;;
		bg) _TP_BG[$cls]="$val" ;;
		mods) _TP_MOD[$cls]="$val" ;;
	esac
}

_tui.theme_parse() {
	local file="$1" line cur="" body decl
	_TP_FG=()
	_TP_BG=()
	_TP_MOD=()
	_TP_SEEN=()
	_TP_ORDER=()
	local open_re='^\.([A-Za-z0-9_-]+(:[a-z]+)?)[[:space:]]*\{$'
	local one_re='^\.([A-Za-z0-9_-]+(:[a-z]+)?)[[:space:]]*\{(.*)\}$' # .name { fg: x; bg: y; }
	local decl_re='^([a-z]+)[[:space:]]*:[[:space:]]*([^;]+);?$'
	while IFS= read -r line || [[ -n "$line" ]]; do
		line="${line#"${line%%[![:space:]]*}"}"
		line="${line%"${line##*[![:space:]]}"}" # trim, no fork
		[[ -z "$line" || "$line" == /\** ]] && continue
		if [[ "$line" =~ $open_re ]]; then
			cur="${BASH_REMATCH[1]/:/_}"
		elif [[ "$line" =~ $one_re ]]; then
			cur="${BASH_REMATCH[1]/:/_}"
			body="${BASH_REMATCH[3]}"
			while [[ -n "$body" ]]; do
				decl="${body%%;*}"
				[[ "$body" == *";"* ]] && body="${body#*;}" || body=""
				decl="${decl#"${decl%%[![:space:]]*}"}"
				[[ "$decl" =~ $decl_re ]] && _tui.theme_decl "$cur" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
			done
			cur=""
		elif [[ "$line" == "}" ]]; then
			cur=""
		elif [[ -n "$cur" && "$line" =~ $decl_re ]]; then
			_tui.theme_decl "$cur" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
		fi
	done <"$file"
}

_tui.theme_commit() {
	local cls
	for cls in "${_TP_ORDER[@]}"; do
		[[ -n "${_TP_FG[$cls]:-}" ]] && _TUI_CLASS_FG[$cls]="${_TP_FG[$cls]}"
		[[ -n "${_TP_BG[$cls]:-}" ]] && _TUI_CLASS_BG[$cls]="${_TP_BG[$cls]}"
		[[ -n "${_TP_MOD[$cls]:-}" ]] && _TUI_CLASS_MOD[$cls]="${_TP_MOD[$cls]}"
	done
}

# Runs the collision lint on the class table and logs findings. Only done when a file is actually
# PARSED (a memo hit re-applies a table that was already checked).
_tui.theme_check() {
	_tui._find_theme_collisions
	local finding
	for finding in "${_TUI_THEME_COLLISIONS[@]}"; do
		tui.log.warn "tui.load_theme($1): $finding"
	done
}

_tui.theme_load_file() {
	_tui.theme_parse "$1" || return 1
	_tui.theme_commit
	_tui.theme_check "$1"
}

tui.load_theme() {
	local file="$1"
	[[ -r "$file" ]] || {
		echo "tui.load_theme: cannot read '$file'" >&2
		return 1
	}
	_tui.theme_load_file "$file" || return 1

	# A user-selected overlay (tui.theme.set) is re-applied on top of every
	# page stylesheet so it stays in force across page changes.
	if [[ -n "${_TUI_THEME_OVERLAY:-}" && "$file" != "$_TUI_THEME_OVERLAY" ]]; then
		tui.load_theme "$_TUI_THEME_OVERLAY"
	fi
}
# _tui._find_theme_collisions - scans the just-loaded theme for classes
# where a pane's border ring, in the state it actually shows while
# focused, resolves to the exact same fg/bg/mods as that class's :title.
# These two are drawn immediately adjacent to each other - the border
# ring, then the title tag right after it - any time a pane using that
# class has a title and gets focused (_tui._draw_pane_border in tui.sh).
# Identical styles there don't produce a visible error; they produce a
# run of same-colored characters that reads, in a screenshot, like
# garbled output rather than what it actually is: nobody chose to make
# the border and the title look different once the pane has focus. This
# is exactly the bug `.sidebar:focus` shipped with earlier in this
# project's history (copied from `.sidebar:title` verbatim) - findings
# are populated into _TUI_THEME_COLLISIONS as plain description strings;
# tui.load_theme logs each one via tui.log.warn, and scripts/lint_theme.sh
# prints them for a human to look at directly, both reading the exact
# same array so there's one place this check can ever be wrong.
declare -ga _TUI_THEME_COLLISIONS=()

# Fork-free: leaves "fg<US>bg<US>mods" for CLASS+STATE in _TT (a command substitution per class
# made the collision lint one of the slowest parts of a theme load).
_tui._theme_state_triplet() {
	local suffix="$1"
	[[ "$2" != "normal" ]] && suffix="${1}_${2}"
	_TT="${_TUI_CLASS_FG[$suffix]:-}"$'\x1f'"${_TUI_CLASS_BG[$suffix]:-}"$'\x1f'"${_TUI_CLASS_MOD[$suffix]:-}"
}

_tui._theme_triplet_set() { [[ "$1" != $'\x1f\x1f' ]]; }

_tui._find_theme_collisions() {
	_TUI_THEME_COLLISIONS=()

	local -A bases=()
	local key base
	for key in "${!_TUI_CLASS_FG[@]}" "${!_TUI_CLASS_BG[@]}" "${!_TUI_CLASS_MOD[@]}"; do
		base="$key"
		base="${base%_focus}"
		base="${base%_border}"
		base="${base%_title}"
		base="${base%_hover}"
		base="${base%_unchecked}"
		base="${base%_checked}"
		bases[$base]=1
	done

	local title ring focus
	for base in "${!bases[@]}"; do
		_tui._theme_state_triplet "$base" title
		title="$_TT"
		_tui._theme_triplet_set "$title" || continue

		_tui._theme_state_triplet "$base" focus
		focus="$_TT"
		if _tui._theme_triplet_set "$focus"; then
			ring="$focus"
		else
			_tui._theme_state_triplet "$base" border
			ring="$_TT"
		fi
		_tui._theme_triplet_set "$ring" || continue

		if [[ "$title" == "$ring" ]]; then
			_TUI_THEME_COLLISIONS+=(".$base - :focus (falling back to :border) resolves identically to :title. A pane using this class will show its title tag blending into its border ring the moment it's focused.")
		fi
	done
}

# tui.class ID CLASS - applies .class (+ optional :focus/:border/:title
# variants) to a widget or pane id's normal/focus/border/title style keys.
tui.class() {
	local id="$1" cls="$2"
	[[ -z "$cls" ]] && return

	local state suffix
	for state in normal focus border title hover checked unchecked; do
		suffix="$cls"
		[[ "$state" != "normal" ]] && suffix="${cls}_${state}"
		if [[ -n "${_TUI_CLASS_FG[$suffix]:-}${_TUI_CLASS_BG[$suffix]:-}${_TUI_CLASS_MOD[$suffix]:-}" ]]; then
			tui.style "$id" "${_TUI_CLASS_FG[$suffix]:-}" "${_TUI_CLASS_BG[$suffix]:-}" "${_TUI_CLASS_MOD[$suffix]:-}" "$state"
		fi
	done
}
