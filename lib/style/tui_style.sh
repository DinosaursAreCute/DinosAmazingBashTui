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
#   .classname:selected { ... }   a button's look while tui.select marked it selected (a current tab or
#                               nav entry); focus and hover still win, fields left out fall back to normal.
#
#   .type.variant { ... }      a named design of a widget type (markup: variant="NAME"); inherits the base
#                               `.type` rule, so it only states what differs.
#   @import "other.css";       applies other.css here (path relative to this file); rules after it override it.
#   .type { fill: "█"; }       glyph properties: a quoted single-cell glyph per slot of _TUI_G_DEFAULT.
#
#   .classname { cursor: pointer; }   mouse pointer shape while over a widget of the class (CSS names: pointer, text, not-allowed, grab, ...;
#                               `.cls:hover { cursor: x; }` while hovered, `.cls:focus` while the focused widget is hovered (hover wins).
#                               `default` leaves it alone). Widgets without one get a type default (tui_mouse.sh).
#
# fg/bg accept a colors.sh name (e.g. "red") or a "#RRGGBB" hex value.
# mods is a space-separated list of style.* modifiers (e.g. "bold underline").
#
# tui.load_theme FILE   parses a stylesheet into the class table.
# tui.class ID CLASS    applies a class's rules to a pane or widget id.
# tui.style ID:STATE FG BG MODS   sets style directly, bypassing classes.
#   STATE is one of: normal (default), focus, border, title, hover, checked, unchecked, selected.
# tui.glyph.set TYPE KEY GLYPH [VARIANT]   sets one slot at run time.
# tui.glyph.get TYPE KEY [VARIANT]   resolves a glyph slot into TUI_GLYPH: variant, then base, then built-in default.
# requires:

declare -gA _TUI_STYLE_FG=() _TUI_STYLE_BG=() _TUI_STYLE_MOD=()
declare -gA _TUI_CLASS_FG=() _TUI_CLASS_BG=() _TUI_CLASS_MOD=()
declare -gA _TUI_CLASS_CUR=() _TUI_STYLE_CUR=() # `cursor:` shape name: per class, and baked per "id_state" by tui.class
declare -g _TUI_THEME_OVERLAY=""

# Glyph slots. _TUI_G_DEFAULT is the built-in look ("type.key"); _TUI_G holds what themes set ("type.key" or
# "type.variant.key"). A slot missing from _TUI_G_DEFAULT is not themeable.
declare -gA _TUI_G_DEFAULT=(
	[progress.fill]="█" [progress.empty]="░"
	[checkbox.left]="[" [checkbox.on]="x" [checkbox.off]=" " [checkbox.right]="]"
	[select.left]="[" [select.arrow]="▾" [select.right]="]"
	[scrollbar.thumb]="▐" [scrollbar.track]=" "
	[panebar.vthumb]=" " [panebar.vtrack]="│" [panebar.hthumb]=" " [panebar.htrack]="─"
)
declare -gA _TUI_G_EMPTY_OK=([checkbox.left]=1 [checkbox.right]=1 [select.left]=1 [select.right]=1) # slots a theme may blank
declare -gA _TUI_G=()
declare -gA _TUI_G_USER=()   # "type.key" -> the user's own base glyph (Settings page); beats the theme's base, not a variant
declare -gA _TUI_V_DEFAULT=() # type -> the variant widgets of that type use when they name none
declare -ga TUI_VARIANTS=() TUI_GLYPHS=()
declare -g TUI_GLYPH=""
declare -gi _TUI_G_GEN=0 # bumped on every change of _TUI_G: part of the key of cached rows that hold glyphs

# _tui.variant_v ID TYPE -> _V : the widget's own variant, else the default for its type
_tui.variant_v() { _V="${_TUI_W_VARIANT[$1]:-${_TUI_V_DEFAULT[$2]:-}}"; }

# _tui.glyph_v TYPE KEY VARIANT -> TUI_GLYPH : the design's slot, else the theme's base, else the built-in default.
# The design "custom" is the user's own (tui.glyph.user); any other name is a theme variant. Array reads only.
_tui.glyph_v() {
	if [[ "$3" == custom && -n "${_TUI_G_USER[$1.$2]+x}" ]]; then
		TUI_GLYPH="${_TUI_G_USER[$1.$2]}"
	elif [[ -n "$3" && "$3" != custom && -n "${_TUI_G[$1.$3.$2]+x}" ]]; then
		TUI_GLYPH="${_TUI_G[$1.$3.$2]}"
	else
		TUI_GLYPH="${_TUI_G[$1.$2]-${_TUI_G_DEFAULT[$1.$2]-}}"
	fi
}

# tui.glyph.available TYPE KEY -> TUI_GLYPHS : the glyphs the Settings page offers for a slot, read once from
# $TUI_DEFAULTS_DIR/glyphs/available.txt ("@group slot ..." line, then the glyph lines of that group); empty when the
# slot has no entry. Words: "none" (a blank bracket), "space" (a blank cell).
declare -gA _TUI_G_AVAIL=()
declare -gi _TUI_G_AVAIL_LOADED=0
tui.glyph.available() {
	if ((!_TUI_G_AVAIL_LOADED)); then
		_TUI_G_AVAIL_LOADED=1
		local file="${TUI_DEFAULTS_DIR:-}/glyphs/available.txt" line slots="" list="" s
		if [[ -r "$file" ]]; then
			while IFS= read -r line || [[ -n "$line" ]]; do
				[[ -z "$line" || "$line" == \#* ]] && continue
				if [[ "$line" == @* ]]; then
					for s in $slots; do _TUI_G_AVAIL[$s]="$list"; done
					slots="${line#@* }" list=""
				else
					list+="${list:+ }$line"
				fi
			done <"$file"
			for s in $slots; do _TUI_G_AVAIL[$s]="$list"; done
		fi
	fi
	TUI_GLYPHS=()
	[[ -n "${_TUI_G_AVAIL[$1.$2]:-}" ]] && read -ra TUI_GLYPHS <<<"${_TUI_G_AVAIL[$1.$2]}"
	return 0
}

# tui.glyph.user TYPE KEY [GLYPH] - one part of the user's own design, "custom" (see tui.variant.default). A missing
# GLYPH removes the part; an empty one blanks it for the bracket slots (_TUI_G_EMPTY_OK) and removes it elsewhere.
# Kept across theme changes. rc 1 for an unknown slot or an unusable glyph.
tui.glyph.user() {
	local slot="$1.$2"
	[[ -n "${_TUI_G_DEFAULT[$slot]+x}" ]] || return 1
	if (($# < 3)) || [[ -z "$3" && -z "${_TUI_G_EMPTY_OK[$slot]+x}" ]]; then
		unset '_TUI_G_USER[$slot]'
	else
		_tui.glyph_ok "$3" "$slot" || return 1
		_TUI_G_USER[$slot]="$3"
	fi
	_TUI_G_GEN+=1
}

# tui.variant.default TYPE [NAME] - the design widgets of TYPE use when they name no variant; empty NAME clears it.
tui.variant.default() {
	if [[ -n "${2:-}" ]]; then _TUI_V_DEFAULT[$1]="$2"; else unset '_TUI_V_DEFAULT[$1]'; fi
	_TUI_G_GEN+=1
}

# tui.variant.list TYPE -> TUI_VARIANTS : the variant names the loaded theme defines for TYPE, sorted
tui.variant.list() {
	local slot name
	local -A seen=()
	TUI_VARIANTS=()
	for slot in "${!_TUI_G[@]}"; do
		[[ "$slot" == "$1".*.* ]] || continue
		name="${slot#"$1".}"
		name="${name%.*}"
		seen[$name]=1
	done
	((${#seen[@]})) || return 0
	TUI_VARIANTS=($(printf '%s\n' "${!seen[@]}" | LC_ALL=C sort))
}

# tui.glyph.get TYPE KEY [VARIANT] -> TUI_GLYPH
tui.glyph.get() { _tui.glyph_v "$1" "$2" "${3:-}"; }

# tui.glyph.set TYPE KEY GLYPH [VARIANT] - sets a slot at run time; rc 1 for an unknown slot or an unusable glyph.
# A theme reload clears it (themes own _TUI_G), so an app re-applies its choice when its page is shown.
tui.glyph.set() {
	local type="$1" key="$2" variant="${4:-}"
	[[ -n "${_TUI_G_DEFAULT[$type.$key]+x}" ]] && _tui.glyph_ok "$3" "$type.$key" || return 1
	_TUI_G[$type${variant:+.$variant}.$key]="$3"
	_TUI_G_GEN+=1
}

# _tui.glyph_ok GLYPH SLOT - true for a glyph without control characters that is one terminal cell wide; empty only
# for the slots in _TUI_G_EMPTY_OK (the width is only measurable under a UTF-8 locale; ${#} counts bytes otherwise).
_tui.glyph_ok() {
	[[ -z "$1" && -n "${_TUI_G_EMPTY_OK[${2:-}]+x}" ]] && return 0
	[[ -n "$1" && "$1" != *[[:cntrl:]]* ]] || return 1
	local u=$'\xc3\xa9'
	((${#u} == 1)) || return 0
	declare -F _tui_md.cells >/dev/null || return 0
	_tui_md.cells "$1"
	((_VL == 1))
}

# tui.style ID FG BG MODS [STATE]  - low-level setter behind tui.class.
tui.style() {
	local id="$1" fg="$2" bg="$3" mods="$4" state="${5:-normal}"
	local key="${id}_${state}"
	tui.log.debug "tui.style: baking $key -> fg=${fg:-<unset>} bg=${bg:-<unset>} mods=${mods:-<unset>}"
	[[ -n "$fg" ]] && _TUI_STYLE_FG[$key]="$fg"
	[[ -n "$bg" ]] && _TUI_STYLE_BG[$key]="$bg"
	[[ -n "$mods" ]] && _TUI_STYLE_MOD[$key]="$mods"
	_tui.epoch_bump style
}

# _tui.style_clear ID - drops every baked style of ID (all states). tui.class only ever adds to the tables, so a
# re-bake after a theme change clears first: a property the new theme leaves out must not keep the old value.
_tui.style_clear() {
	local state
	for state in normal focus border title hover checked unchecked selected; do
		unset '_TUI_STYLE_FG[${1}_$state]' '_TUI_STYLE_BG[${1}_$state]' '_TUI_STYLE_MOD[${1}_$state]' '_TUI_STYLE_CUR[${1}_$state]'
	done
	_tui.epoch_bump style
}

# ── theme loading ───────────────────────────────────────────────────────
# tui.load_theme FILE - parse a .css-like stylesheet into the class table.
#   Split in three so tui_cache.sh can memoize the middle one without this file knowing:
#     _tui.theme_parse   FILE   pure, fork-free parse of one file into _TP_* (touches no class table)
#     _tui.theme_commit         copies _TP_* into _TUI_CLASS_* (later files override earlier ones)
#     _tui.theme_load_file FILE parse + commit + collision check. tui_cache.sh REDEFINES this with a
#                               memoized version (parsed once per file, re-applied from memory).
declare -gA _TP_FG=() _TP_BG=() _TP_MOD=() _TP_CUR=() _TP_SEEN=() _TP_G=()
declare -ga _TP_ORDER=() _TP_DEPS=() # _TP_DEPS: the files the parsed stylesheet imported

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
		cursor) _TP_CUR[$cls]="$val" ;;
		*) _tui.theme_glyph_decl "$cls" "$key" "$val" ;;
	esac
}

# _tui.theme_glyph_decl CLASS KEY VALUE - stages a glyph property ("type.variant.key" slot) of the rule being parsed;
# anything that is not a quoted, themeable, one-cell glyph is dropped with a warning.
_tui.theme_glyph_decl() {
	local cls="$1" key="$2" val="$3" type="${1%%.*}"
	if [[ -z "${_TUI_G_DEFAULT[$type.$key]+x}" || "$val" != \"*\" ]]; then
		tui.log.warn "theme: ignoring '$key: $val' in .$cls (unknown glyph slot or value not quoted)"
		return 0
	fi
	val="${val#\"}"
	val="${val%\"}"
	if ! _tui.glyph_ok "$val" "$type.$key"; then
		tui.log.warn "theme: ignoring '$key' in .$cls: glyph must be one visible cell"
		return 0
	fi
	_TP_G[$cls.$key]="$val"
}

# _tui.theme_parse FILE - parses FILE (and what it imports) into the _TP_* staging tables.
_tui.theme_parse() {
	_TP_FG=()
	_TP_BG=()
	_TP_MOD=()
	_TP_CUR=()
	_TP_SEEN=()
	_TP_G=()
	_TP_ORDER=()
	_TP_DEPS=()
	_tui.theme_parse_into "$1" 0
}

# _tui.theme_parse_into FILE DEPTH - adds FILE's rules to the staging tables. An `@import "x.css";` is parsed in place,
# so everything after it overrides what it brought; x.css is relative to FILE's directory. A missing file, or one
# nested deeper than 8 levels (an import cycle), is skipped with a warning.
_tui.theme_parse_into() {
	local file="$1" depth="$2" line cur="" body decl dir="${1%/*}" imp
	[[ "$file" == */* ]] || dir="."
	((depth > 8)) && {
		tui.log.warn "theme: @import nested too deep at $file (cycle?)"
		return 0
	}
	local open_re='^\.([A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)?(:[a-z]+)?)[[:space:]]*\{$'
	local one_re='^\.([A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)?(:[a-z]+)?)[[:space:]]*\{(.*)\}$' # .name { fg: x; bg: y; }
	local decl_re='^([a-z]+)[[:space:]]*:[[:space:]]*([^;]+);?$'
	local import_re='^@import[[:space:]]+(url\()?"([^"]+)"\)?[[:space:]]*;?$'
	while IFS= read -r line || [[ -n "$line" ]]; do
		line="${line#"${line%%[![:space:]]*}"}"
		line="${line%"${line##*[![:space:]]}"}" # trim, no fork
		[[ -z "$line" || "$line" == /\** ]] && continue
		if [[ "$line" =~ $import_re ]]; then
			imp="${BASH_REMATCH[2]}"
			[[ "$imp" == /* ]] || imp="$dir/$imp"
			if [[ -r "$imp" ]]; then
				_TP_DEPS+=("$imp")
				_tui.theme_parse_into "$imp" $((depth + 1))
			else
				tui.log.warn "theme: @import '$imp' in $file cannot be read"
			fi
		elif [[ "$line" =~ $open_re ]]; then
			cur="${BASH_REMATCH[1]/:/_}"
		elif [[ "$line" =~ $one_re ]]; then
			cur="${BASH_REMATCH[1]/:/_}"
			body="${BASH_REMATCH[4]}"
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
	local cls slot
	tui.log.debug "_tui.theme_commit: committing ${#_TP_ORDER[@]} class(es) into _TUI_CLASS_*"
	for slot in "${!_TP_G[@]}"; do _TUI_G[$slot]="${_TP_G[$slot]}"; done
	_TUI_G_GEN+=1
	for cls in "${_TP_ORDER[@]}"; do
		[[ -n "${_TP_FG[$cls]:-}" ]] && _TUI_CLASS_FG[$cls]="${_TP_FG[$cls]}"
		[[ -n "${_TP_BG[$cls]:-}" ]] && _TUI_CLASS_BG[$cls]="${_TP_BG[$cls]}"
		[[ -n "${_TP_MOD[$cls]:-}" ]] && _TUI_CLASS_MOD[$cls]="${_TP_MOD[$cls]}"
		[[ -n "${_TP_CUR[$cls]:-}" ]] && _TUI_CLASS_CUR[$cls]="${_TP_CUR[$cls]}"
	done
}

# _tui.theme_reset - empties the class table. Loading a theme only ever adds to it (later files override earlier
# ones), so a class or property the new theme leaves out would keep the previous theme's colour; a theme switch
# resets first and rebuilds from the framework default.
_tui.theme_reset() {
	_TUI_CLASS_FG=() _TUI_CLASS_BG=() _TUI_CLASS_MOD=() _TUI_CLASS_CUR=() _TUI_G=()
	_TUI_G_GEN+=1
	_TUI_THEME_COLLISIONS=()
	[[ -r "${TUI_DEFAULTS_DIR:-}/theme.css" ]] && tui.load_theme "$TUI_DEFAULTS_DIR/theme.css"
	return 0
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
	tui.log.debug "_tui.theme_load_file: parsing $1 (unmemoized base version)"
	_tui.theme_parse "$1" || return 1
	_tui.theme_commit
	_tui.theme_check "$1"
}

tui.load_theme() {
	local file="$1"
	tui.log.debug "tui.load_theme: file=$file overlay=${_TUI_THEME_OVERLAY:-<none>}"
	[[ -r "$file" ]] || {
		tui.log.warn "tui.load_theme: cannot read '$file'"
		echo "tui.load_theme: cannot read '$file'" >&2
		return 1
	}
	_tui.theme_load_file "$file" || return 1

	# A user-selected overlay (tui.theme.set) is re-applied on top of every
	# page stylesheet so it stays in force across page changes.
	if [[ -n "${_TUI_THEME_OVERLAY:-}" && "$file" != "$_TUI_THEME_OVERLAY" ]]; then
		tui.log.debug "tui.load_theme: re-applying overlay $_TUI_THEME_OVERLAY on top of $file"
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
		base="${base%_collapsed}"
		base="${base%_unchecked}"
		base="${base%_selected}"
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
	tui.log.debug "tui.class: baking id=$id from class=$cls (bakes _TUI_STYLE_* at build time - not re-run on a cache replay)"

	local state suffix
	for state in normal focus border title hover checked unchecked selected; do
		suffix="$cls"
		[[ "$state" != "normal" ]] && suffix="${cls}_${state}"
		if [[ -n "${_TUI_CLASS_FG[$suffix]:-}${_TUI_CLASS_BG[$suffix]:-}${_TUI_CLASS_MOD[$suffix]:-}" ]]; then
			tui.style "$id" "${_TUI_CLASS_FG[$suffix]:-}" "${_TUI_CLASS_BG[$suffix]:-}" "${_TUI_CLASS_MOD[$suffix]:-}" "$state"
		fi
		[[ -n "${_TUI_CLASS_CUR[$suffix]:-}" ]] && _TUI_STYLE_CUR[${id}_$state]="${_TUI_CLASS_CUR[$suffix]}"
	done
}
