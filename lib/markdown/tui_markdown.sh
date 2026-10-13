#!/usr/bin/env bash
# tui_markdown.sh - Markdown renderer: text -> styled, width-fitted terminal rows. Headless: no widget, no terminal.
#
#   tui.md.render TEXT WIDTH             rendered document -> TUI_MD_ROWS, TUI_MD_MAP, TUI_MD_LINK_URLS, TUI_MD_LINK_TEXTS
#   tui.md.style  TEXT                   styled source (every character kept, one row per line) -> TUI_MD_ROWS, TUI_MD_MAP
#   tui.md.style_lines FENCE LINE...     styled rows of the given source lines (FENCE from tui.md.fence_before) -> TUI_MD_ROWS
#   tui.md.fence_before TEXT TOP VAR     fence state ("" or "CHAR:LEN") in force at source line TOP (0-based) -> VAR
#   tui.md.show PANE TEXT                renders TEXT into a scrolling pane; re-fitted when the pane width changes
#   tui.md.show_file PANE FILE           the same for the contents of FILE
#   tui.md.forget PANE                   stops re-rendering PANE (call it before putting other content into the pane)
#   tui.md.strip  STR [VAR]              STR without SGR sequences: printed, or stored in VAR
#   tui.md.row_for_line LINE VAR         first rendered row of the block that holds source line LINE (1-based) -> VAR (0-based)
#   tui.md.line_for_row ROW VAR          source line of rendered row ROW -> VAR
#   tui.md.style_set CLASS SGR           replaces the SGR sequence of a class (h1..h6 strong em code codeblock quote bullet link hr marker)
#   tui.md.fonts on|off|toggle           headings in a block font (banner renderer) where a level has one (default off)
#   tui.md.heading_font LEVEL FONT       the font of heading level 1..6: block5 blk3 seg3 box3 half2, style or "" = no font (default: 1 block5, 2 box3)
#   tui.md.heading_font_of LEVEL VAR     the font of LEVEL ("style" when it has none) -> VAR
#   tui.md.style_spec CLASS SPEC         restyles a class from "COLOR[:MOD,MOD]" (colors: TUI_MD_COLORS or #rrggbb; mods: TUI_MD_MODS)
#   tui.md.style_spec_of CLASS VAR       the spec of a class's current style -> VAR
#   tui.md.style_reset [CLASS]           back to the default style of CLASS, or of every class
#   tui.md.profile dabt|theme            the base look: DABT's own, or the active theme's .md_CLASS styles (own specs go on top)
#   tui.md.tables grid|rounded|plain|stacked   how pipe tables are drawn; tui.md.table_overflow wrap|truncate
#   tui.md.images placeholder|alt|hidden|graphics   what ![alt](src) shows; tui.md.image_protocol VAR -> kitty|iterm2|none
#   tui.md.config_apply                  loads the md.* keys of the app config (tui.config.apply calls it)
#   tui.md.breaks on|off|toggle          every source newline inside a paragraph is a line break (default off: it is a space)
#   tui.md.mono on|off                   attribute-only style table (bold/underline/reverse), no colors
#
# Config: TUI_MD_FONTS=0|1, TUI_MD_BREAKS=0|1, TUI_MD_LINK_URL=inline|hidden (links render "text (url)" or "text"), TUI_MD_MAX_BYTES (above it only blocks are parsed),
# TUI_MD_MONO=1. Every row of TUI_MD_ROWS starts and ends in the reset state, so rows can be cached and painted on their own.
# Supported: ATX headings, paragraphs, hard breaks, quotes, bullet/ordered/nested lists, fenced code, rules;
# **bold** *em* `code` [text](url) and \escapes. Not supported: raw HTML, setext headings, indented code, tables, images.
# requires:

declare -g TUI_MD_LINK_URL="${TUI_MD_LINK_URL:-inline}"
declare -gi TUI_MD_MAX_BYTES="${TUI_MD_MAX_BYTES:-262144}"
declare -gi TUI_MD_MONO="${TUI_MD_MONO:-0}"
declare -gi TUI_MD_BREAKS="${TUI_MD_BREAKS:-0}"
declare -gi TUI_MD_FONTS="${TUI_MD_FONTS:-0}"
declare -g TUI_MD_PROFILE="${TUI_MD_PROFILE:-dabt}"
declare -g TUI_MD_TABLES="${TUI_MD_TABLES:-grid}" TUI_MD_TABLE_OVERFLOW="${TUI_MD_TABLE_OVERFLOW:-wrap}"
declare -g TUI_MD_IMAGES="${TUI_MD_IMAGES:-placeholder}"
declare -g _TUI_MD_SYNC_KEY=""
declare -gA _TUI_MD_HFONT=([1]=block5 [2]=box3) # heading level -> banner font ("" = plain)
declare -gA _TUI_MD_BANNER=()                  # "FONT|TEXT" -> banner rows joined with \x1f
declare -ga _TUI_MD_BR=()
declare -ga TUI_MD_CLASSES=(h1 h2 h3 h4 h5 h6 strong em code codeblock quote bullet link hr marker strike hl_keyword hl_string hl_comment hl_number hl_var page table table_head)
declare -gA _TUI_MD_REFS=()       # reference label (lower case) -> "URL" of the [label]: URL definitions of the last render
declare -ga TUI_MD_LINK_ROWS=()   # row of each link of the last render (parallel to TUI_MD_LINK_URLS)
declare -ga TUI_MD_HEADS=()       # "LEVEL|TITLE|FIRST_ROW|LAST_ROW|LINE" of every heading of the last render
declare -gA TUI_MD_ANCHORS=()     # heading slug -> first row
declare -gi _TUI_MD_FOCUS_LINK=-1 # index of the link drawn as focused (-1 none)
declare -ga TUI_MD_FONT_NAMES=(style block5 blk3 seg3 box3 half2)
declare -ga TUI_MD_COLORS=(default black red green yellow blue magenta cyan white gray bright_red bright_green bright_yellow bright_blue bright_magenta bright_cyan bright_white)
declare -ga TUI_MD_MODS=(bold dim italic underline reverse strike)
declare -gA _TUI_MD_COLOR_CODE=([black]=30 [red]=31 [green]=32 [yellow]=33 [blue]=34 [magenta]=35 [cyan]=36 [white]=37 [gray]=90
	[bright_red]=91 [bright_green]=92 [bright_yellow]=93 [bright_blue]=94 [bright_magenta]=95 [bright_cyan]=96 [bright_white]=97)
declare -gA _TUI_MD_MOD_CODE=([bold]=1 [dim]=2 [italic]=3 [underline]=4 [reverse]=7 [strike]=9)
declare -gi TUI_MD_DEGRADED=0
declare -ga TUI_MD_ROWS=() TUI_MD_MAP=() TUI_MD_LINK_URLS=() TUI_MD_LINK_TEXTS=()
declare -gA _TUI_MD_SGR=()
declare -gA _TUI_MD_HR=() # WIDTH -> rule glyphs; one string per width
declare -gA _TUI_MD_SPEC=()   # class -> "FG[/BG][:MODS]" the user customised it with (always on top of the profile)
declare -gA _TUI_MD_DIRECT=() # class -> SGR set with tui.md.style_set
declare -gA _TUI_MD_HL=() # fence language (lower case) -> function that highlights one code line (tui.md.highlight)
declare -gA _TUI_MD_MEMO=() # source line -> styled row (style mode); dropped when the style table changes
declare -gA _TUI_MD_SHOWN=() _TUI_MD_SHOWN_W=() # pane -> source text / width it was rendered at (tui.md.show)
declare -gi _TUI_MD_HOOKED=0
declare -g _TUI_MD_NEXT_FILE=""
declare -gi _TUI_MD_KEEP=0 _TUI_MD_DEPTH=0
declare -gA _TUI_MD_IMEMO=() # inline results of whole paragraphs/headings: "BASE\x1fLINKS_BEFORE\x1fTEXT" -> record
declare -g _TUI_MD_IMEMO_SIG=""
declare -gi _TUI_MD_TOP=0 _TUI_MD_STOP=0 _TUI_MD_STOP_ROWS=0 _TUI_MD_STOP_AT=0 # resumable top-level block loop
declare -gi _TUI_MD_RES_DONE=1 _TUI_MD_RES_I=0 _TUI_MD_RES_EM=0 _TUI_MD_RES_PP=0 _TUI_MD_RES_W=0
declare -ga _TUI_MD_LINES=() # the numbered source lines of the render in progress
declare -gi _TUI_MD_HIT=0 _TUI_MD_RENDERS=0 # renders started (a cache hit starts none)
declare -g _TUI_MD_LAST="" # the Markdown pane shown last
declare -g _TUI_MD_DISK_SRC="" _TUI_MD_NEXT_DISK="" _TUI_MD_DC_KEY="" _DP=""
declare -gi _TUI_MD_DC_OK=0 _TUI_MD_DISK_DIR_OK=0
declare -ga _TUI_MD_BI=() _TUI_MD_BE=() _TUI_MD_BP=() # top-level blocks of the render: line index, "a block came before", "a paragraph came before"
declare -gi _TUI_MD_END_I=0 _TUI_MD_PD_NEXT=0 _TUI_MD_PREPS=0
declare -ga _TUI_MD_PD_KEY=() _TUI_MD_PD_DEG=() _TUI_MD_PD_HAS=() # prepared documents: slot -> text, degraded flag, blocks known
declare -g _PDS="" _BK="" _TL=0
declare -gA _TUI_MD_PEND=() _TUI_MD_RS=() # pane -> 1 while its render is unfinished; pane.FIELD -> where it resumes
declare -ga _TUI_MD_RC_KEY=() # row cache: slot -> key; the slot's arrays are _TUI_MD_RC_<what>_<slot>
declare -gi _TUI_MD_RC_NEXT=0
declare -g _CK="" _TUI_MD_RES_KEY=""
declare -ga _TUI_MD_RC_DEG=()
declare -gi _CN=0
declare -g _MD_OUT="" _VL=0 _FC=0 _CE=0 _LT="" _LU="" _LN=0 _CH="" _CT="" _MD_ROW=""

# control bytes removed from input: everything below 0x20 except tab and newline, plus DEL
_TUI_MD_CTRL=$'\x01\x02\x03\x04\x05\x06\a\b\v\f\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f\x7f'
_TUI_MD_RESET=$'\e[0m'

_TUI_MD_RE_HEAD='^[[:space:]]{0,3}(#{1,6})([[:space:]]+(.*)|)$'
_TUI_MD_RE_FENCE='^[[:space:]]{0,3}(`{3,}|~{3,})(.*)$'
_TUI_MD_RE_HR='^[[:space:]]{0,3}([-*_])([[:space:]]*\1){2,}[[:space:]]*$'
_TUI_MD_RE_QUOTE='^[[:space:]]{0,3}>[ ]?(.*)$'
_TUI_MD_RE_SETEXT_EQ='^[[:space:]]{0,3}=+[[:space:]]*$'
_TUI_MD_RE_SETEXT_DASH='^[[:space:]]{0,3}-{2,}[[:space:]]*$'
_TUI_MD_RE_LIST='^([[:space:]]{0,3})([-*+]|[0-9]{1,9}[.)])([[:space:]]+(.*)|)$'
_TUI_MD_RE_SQUOTE='^([[:space:]]{0,3}>)(.*)$'
_TUI_MD_RE_SLIST='^([[:space:]]*)([-*+]|[0-9]{1,9}[.)])([[:space:]]+)(.*)$'

# _tui_md.sgr_defaults - fills the class -> SGR table for the current TUI_MD_MONO. The colored table follows the look the
# Settings page was used to build: magenta titles, cyan bullets, bright-blue bold links, a dim red rule, a dim gray delimiter.
_tui_md.sgr_defaults() {
	local e=$'\e['
	if ((TUI_MD_MONO)); then
		_TUI_MD_SGR=([h1]="${e}1;4m" [h2]="${e}1;4m" [h3]="${e}1m" [h4]="${e}1m" [h5]="${e}1m" [h6]="${e}1m"
			[strong]="${e}1m" [em]="${e}3m" [code]="${e}7m" [codeblock]="${e}2m" [quote]="${e}2m" [bullet]="${e}1m"
			[link]="${e}4m" [hr]="${e}2m" [marker]="${e}2m" [strike]="${e}9m" [link_focus]="${e}7;4m" [page]="" [table]="${e}2m" [table_head]="${e}1m"
			[hl_keyword]="${e}1m" [hl_string]="${e}4m" [hl_comment]="${e}2m" [hl_number]="${e}1m" [hl_var]="${e}3m")
	else
		_TUI_MD_SGR=([h1]="${e}1;4;95m" [h2]="${e}1;34m" [h3]="${e}1;35m" [h4]="${e}1;33m" [h5]="${e}1;32m" [h6]="${e}1m"
			[strong]="${e}1m" [em]="${e}3m" [code]="${e}33m" [codeblock]="${e}48;5;236m" [quote]="${e}2m" [bullet]="${e}36m"
			[link]="${e}1;4;94m" [hr]="${e}2;31m" [marker]="${e}2;90m" [strike]="${e}9m" [link_focus]="${e}7;94m" [page]="" [table]="${e}2;90m" [table_head]="${e}1m"
			[hl_keyword]="${e}1;35m" [hl_string]="${e}32m" [hl_comment]="${e}2;37m" [hl_number]="${e}33m" [hl_var]="${e}36m")
	fi
}

# _tui_md.shade_codeblock - a code block background a step away from the pane's own: lighter on a dark theme, darker on a light
# one, so it reads as a block without shouting. Needs the panel color of the theme; otherwise the table's fixed gray stays.
_tui_md.shade_codeblock() {
	((TUI_MD_MONO)) && return 0
	local bg=${_TUI_CLASS_BG[panel]:-} r g b l d
	[[ "$bg" =~ ^#([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})$ ]] || return 0
	r=$((16#${BASH_REMATCH[1]})) g=$((16#${BASH_REMATCH[2]})) b=$((16#${BASH_REMATCH[3]}))
	l=$(((r * 299 + g * 587 + b * 114) / 1000))
	d=16
	((l >= 128)) && d=-16
	r=$((r + d)) g=$((g + d)) b=$((b + d))
	((r < 0)) && r=0
	((g < 0)) && g=0
	((b < 0)) && b=0
	((r > 255)) && r=255
	((g > 255)) && g=255
	((b > 255)) && b=255
	_TUI_MD_SGR[codeblock]=$'\e[48;2;'"$r;$g;${b}m"
}

# _tui_md.theme_base - the active theme's .md_CLASS rules (fg, bg, mods) replace the matching classes of the table.
_tui_md.theme_base() {
	local c
	declare -F tui.class.style >/dev/null || return 0
	for c in "${TUI_MD_CLASSES[@]}" link_focus; do
		tui.class.style "md_$c"
		[[ -n "$TUI_FG$TUI_BG$TUI_MODS" ]] || continue
		_tui._sgr_from "$TUI_FG" "$TUI_BG" "$TUI_MODS" && _TUI_MD_SGR[$c]=$_SGR
	done
}

# _tui_md.rebuild - the style table from the profile, then the user's own specs and direct overrides on top.
_tui_md.rebuild() {
	local c
	_tui_md.sgr_defaults
	_tui_md.shade_codeblock
	[[ "$TUI_MD_PROFILE" == theme ]] && _tui_md.theme_base
	for c in "${!_TUI_MD_SPEC[@]}"; do
		_tui_md.spec_sgr "${_TUI_MD_SPEC[$c]}" && _TUI_MD_SGR[$c]=$_SPEC_SGR
	done
	for c in "${!_TUI_MD_DIRECT[@]}"; do _TUI_MD_SGR[$c]=${_TUI_MD_DIRECT[$c]}; done
	_TUI_MD_MEMO=()
	_tui_md.sync_key
	_TUI_MD_SYNC_KEY=$_SK
}

# _tui_md.sync_key -> _SK - what the table depends on besides the user's settings: profile and theme
_tui_md.sync_key() {
	_SK="$TUI_MD_PROFILE|$TUI_MD_MONO|${_TUI_THEME_OVERLAY:-}|${_TUI_CLASS_BG[panel]:-}|${_TUI_CLASS_BG[md_codeblock]:-}|${_TUI_CLASS_FG[md_h1]:-}|${_TUI_CLASS_BG[md_page]:-}"
}

# _tui_md.sync - rebuilds the table when the theme or profile changed since the last render.
_tui_md.sync() {
	_tui_md.sync_key
	[[ "$_SK" == "$_TUI_MD_SYNC_KEY" ]] || _tui_md.rebuild
}
_tui_md.rebuild

# tui.md.profile dabt|theme - the base look: DABT's table, or the active theme's .md_CLASS rules where it has them.
tui.md.profile() {
	case "${1:-}" in
		dabt | theme) TUI_MD_PROFILE=$1 ;;
		*) return 1 ;;
	esac
	_tui_md.rebuild
}

# tui.md.tables grid|rounded|plain|stacked - how pipe tables are drawn.
tui.md.tables() {
	case "${1:-}" in
		grid | rounded | plain | stacked) TUI_MD_TABLES=$1 ;;
		*) return 1 ;;
	esac
}

# tui.md.table_overflow wrap|truncate - a cell wider than its column wraps onto more lines, or is cut with an ellipsis.
tui.md.table_overflow() {
	case "${1:-}" in
		wrap | truncate) TUI_MD_TABLE_OVERFLOW=$1 ;;
		*) return 1 ;;
	esac
}

# tui.md.images placeholder|alt|hidden|graphics - ![alt](src) draws "[img: alt]", only the alt text, nothing, or (graphics) the
# picture itself where the terminal speaks the kitty protocol and src is a local PNG alone in its paragraph (tui_markdown_img.sh).
tui.md.images() {
	case "${1:-}" in
		placeholder | alt | hidden | graphics) TUI_MD_IMAGES=$1 ;;
		*) return 1 ;;
	esac
}

# tui.md.image_protocol VAR - the inline image protocol the terminal speaks, as far as the environment tells: kitty (kitty and
# Ghostty: the graphics protocol with Unicode placeholders, which DABT draws), iterm2 (iTerm2, WezTerm: a different protocol,
# not drawn) or none (also inside tmux, which needs passthrough). TUI_MD_IMAGE_PROTOCOL overrides the guess.
tui.md.image_protocol() {
	local _ip=none
	if [[ -n "${TUI_MD_IMAGE_PROTOCOL:-}" ]]; then
		_ip=$TUI_MD_IMAGE_PROTOCOL
	elif [[ -n "${TMUX:-}" ]]; then
		_ip=none
	elif [[ -n "${KITTY_WINDOW_ID:-}" || "${TERM:-}" == xterm-kitty || "${TERM_PROGRAM:-}" == ghostty || -n "${GHOSTTY_RESOURCES_DIR:-}" ]]; then
		_ip=kitty
	elif [[ "${TERM_PROGRAM:-}" == @(iTerm.app|WezTerm) || "${LC_TERMINAL:-}" == iTerm2 ]]; then
		_ip=iterm2
	fi
	printf -v "$1" %s "$_ip"
}

# tui.md.mono on|off - switches between the colored and the attribute-only style table (resets style_set overrides).
tui.md.mono() {
	[[ "$1" == on ]] && TUI_MD_MONO=1 || TUI_MD_MONO=0
	_TUI_MD_DIRECT=()
	_tui_md.rebuild
}

# tui.md.breaks on|off|toggle - whether a single source newline inside a paragraph breaks the line (on) or is a space (off).
# Takes effect on the next render. A blank line always separates paragraphs.
tui.md.breaks() {
	case "${1:-toggle}" in
		on) TUI_MD_BREAKS=1 ;;
		off) TUI_MD_BREAKS=0 ;;
		toggle) TUI_MD_BREAKS=$((1 - TUI_MD_BREAKS)) ;;
		*) return 1 ;;
	esac
}

# tui.md.fonts on|off|toggle - headings of a level that has a font (tui.md.heading_font) render as block letters.
# Takes effect on the next render. The styled source (tui.md.style) is never affected.
tui.md.fonts() {
	case "${1:-toggle}" in
		on) TUI_MD_FONTS=1 ;;
		off) TUI_MD_FONTS=0 ;;
		toggle) TUI_MD_FONTS=$((1 - TUI_MD_FONTS)) ;;
		*) return 1 ;;
	esac
}

# tui.md.heading_font LEVEL FONT - the banner font of heading level LEVEL (1..6); "" draws that level as plain text.
tui.md.heading_font() {
	[[ "$1" == [1-6] ]] || return 1
	[[ -z "$2" || " style block5 blk3 seg3 box3 half2 " == *" $2 "* ]] || return 1
	[[ "$2" == style ]] && _TUI_MD_HFONT[$1]="" || _TUI_MD_HFONT[$1]=$2
}

# tui.md.heading_font_of LEVEL VAR - the font name of a heading level ("style" when it has none) -> VAR.
tui.md.heading_font_of() {
	printf -v "$2" %s "${_TUI_MD_HFONT[$1]:-style}"
}

# _tui_md.spec_sgr SPEC -> _SPEC_SGR - "FG[/BG][:MOD,MOD]" as an SGR sequence; rc 1 for an unknown color or modifier.
# FG and BG: default, a name of TUI_MD_COLORS, or #rrggbb.
_tui_md.spec_sgr() {
	local spec=$1 color mods="" bg="" mod code
	local -a codes=()
	color=${spec%%:*}
	[[ "$spec" == *:* ]] && mods=${spec#*:}
	if [[ "$color" == */* ]]; then
		bg=${color#*/}
		color=${color%%/*}
	fi
	for mod in ${mods//,/ }; do
		code=${_TUI_MD_MOD_CODE[$mod]:-}
		[[ -n "$code" ]] || return 1
		codes+=("$code")
	done
	case "$color" in
		default | "") ;;
		\#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])
			codes+=("38;2;$((16#${color:1:2}));$((16#${color:3:2}));$((16#${color:5:2}))")
			;;
		*)
			code=${_TUI_MD_COLOR_CODE[$color]:-}
			[[ -n "$code" ]] || return 1
			codes+=("$code")
			;;
	esac
	case "$bg" in
		default | "") ;;
		\#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])
			codes+=("48;2;$((16#${bg:1:2}));$((16#${bg:3:2}));$((16#${bg:5:2}))")
			;;
		*)
			code=${_TUI_MD_COLOR_CODE[$bg]:-}
			[[ -n "$code" ]] || return 1
			codes+=("$((code + 10))")
			;;
	esac
	local IFS=';'
	_SPEC_SGR=$'\e['"${codes[*]}"m
	((${#codes[@]})) || _SPEC_SGR=""
}

# tui.md.style_spec CLASS SPEC - restyles a class from "FG[/BG][:MOD,MOD...]": colors are default, a name of TUI_MD_COLORS or
# #rrggbb, mods are TUI_MD_MODS ("cyan/#202030:bold"). The spec goes on top of the profile and is remembered. An empty SPEC
# restores the profile's style. rc 1 (nothing changed) for an unknown class, color or modifier.
tui.md.style_spec() {
	local class=$1 spec=$2
	[[ " ${TUI_MD_CLASSES[*]} " == *" $class "* ]] || return 1
	if [[ -z "$spec" ]]; then
		tui.md.style_reset "$class"
		return 0
	fi
	_tui_md.spec_sgr "$spec" || return 1
	_TUI_MD_SPEC[$class]=$spec
	_tui_md.rebuild
}

# tui.md.style_spec_of CLASS VAR - the "COLOR:MODS" spec of a class's current style -> VAR (read back from its SGR).
tui.md.style_spec_of() {
	local class=$1 seq p color=default bg="" mods="" name n
	if [[ -n "${_TUI_MD_SPEC[$class]+x}" ]]; then
		printf -v "$2" %s "${_TUI_MD_SPEC[$class]}"
		return 0
	fi
	seq=${_TUI_MD_SGR[$class]#$'\e['}
	seq=${seq%m}
	local -a parts
	IFS=';' read -ra parts <<<"$seq"
	local i=0
	while ((i < ${#parts[@]})); do
		p=${parts[i]}
		if [[ "$p" == 38 && "${parts[i + 1]:-}" == 2 ]]; then
			printf -v color '#%02x%02x%02x' "${parts[i + 2]:-0}" "${parts[i + 3]:-0}" "${parts[i + 4]:-0}"
			((i += 5))
			continue
		fi
		if [[ "$p" == 48 && "${parts[i + 1]:-}" == 2 ]]; then
			printf -v bg '#%02x%02x%02x' "${parts[i + 2]:-0}" "${parts[i + 3]:-0}" "${parts[i + 4]:-0}"
			((i += 5))
			continue
		fi
		if [[ "$p" == 48 && "${parts[i + 1]:-}" == 5 ]]; then # 256-color background: no name, no round trip
			bg="#808080"
			((i += 3))
			continue
		fi
		if ((p >= 40 && p <= 47 || p >= 100 && p <= 107)); then
			for name in "${!_TUI_MD_COLOR_CODE[@]}"; do
				[[ "${_TUI_MD_COLOR_CODE[$name]}" == "$((p - 10))" ]] && bg=$name
			done
			((i++))
			continue
		fi
		for name in "${!_TUI_MD_MOD_CODE[@]}"; do
			[[ "${_TUI_MD_MOD_CODE[$name]}" == "$p" ]] && mods+="${mods:+,}$name"
		done
		for name in "${!_TUI_MD_COLOR_CODE[@]}"; do
			[[ "${_TUI_MD_COLOR_CODE[$name]}" == "$p" ]] && color=$name
		done
		((i++))
	done
	# fixed order, so the spec does not depend on associative-array order
	n=""
	for name in "${TUI_MD_MODS[@]}"; do [[ ",$mods," == *",$name,"* ]] && n+="${n:+,}$name"; done
	printf -v "$2" %s "$color${bg:+/$bg}${n:+:$n}"
}

# tui.md.style_reset [CLASS] - drops the own style of CLASS, or of every class when CLASS is omitted: the profile shows again.
tui.md.style_reset() {
	if [[ -z "${1:-}" ]]; then
		_TUI_MD_SPEC=()
		_TUI_MD_DIRECT=()
	else
		unset '_TUI_MD_SPEC[$1]' '_TUI_MD_DIRECT[$1]'
	fi
	_tui_md.rebuild
}

# tui.md.config_apply - loads the persisted settings: md.fonts md.breaks md.link_url md.profile md.tables md.table_overflow
# md.images, md.font.N (N = 1..6) and md.style.CLASS (a spec).
tui.md.config_apply() {
	local lvl c v
	[[ -n "${_TUI_CFG[md.fonts]:-}" ]] && TUI_MD_FONTS=${_TUI_CFG[md.fonts]}
	[[ -n "${_TUI_CFG[md.breaks]:-}" ]] && TUI_MD_BREAKS=${_TUI_CFG[md.breaks]}
	[[ -n "${_TUI_CFG[md.link_url]:-}" ]] && TUI_MD_LINK_URL=${_TUI_CFG[md.link_url]}
	[[ -n "${_TUI_CFG[md.profile]:-}" ]] && TUI_MD_PROFILE=${_TUI_CFG[md.profile]}
	[[ -n "${_TUI_CFG[md.tables]:-}" ]] && tui.md.tables "${_TUI_CFG[md.tables]}"
	[[ -n "${_TUI_CFG[md.table_overflow]:-}" ]] && tui.md.table_overflow "${_TUI_CFG[md.table_overflow]}"
	[[ -n "${_TUI_CFG[md.images]:-}" ]] && tui.md.images "${_TUI_CFG[md.images]}"
	[[ -n "${_TUI_CFG[md.fetch]:-}" ]] && TUI_MD_IMAGE_FETCH=${_TUI_CFG[md.fetch]}
	for lvl in 1 2 3 4 5 6; do
		v=${_TUI_CFG[md.font.$lvl]:-}
		[[ -n "$v" ]] && tui.md.heading_font "$lvl" "$v"
	done
	for c in "${TUI_MD_CLASSES[@]}"; do
		v=${_TUI_CFG[md.style.$c]:-}
		[[ -n "$v" ]] && _tui_md.spec_sgr "$v" && _TUI_MD_SPEC[$c]=$v
	done
	_tui_md.rebuild
	return 0
}

# _tui_md.banner FONT TEXT -> _TUI_MD_BR - the banner rows of TEXT (memoized); rc 1 when TEXT is empty.
_tui_md.banner() {
	local key="$1|$2" rows r out="" n=0
	if [[ -z "${_TUI_MD_BANNER[$key]+x}" ]]; then
		declare -F _banner_build >/dev/null || tui.require terminal_renderer
		_banner_build "$2" "$1" || return 1
		for r in "${TR_RESULT[@]}"; do
			((n++)) && out+=$'\x1f'
			out+=${r//\\\\/\\}
		done
		((${#_TUI_MD_BANNER[@]} >= 512)) && _TUI_MD_BANNER=()
		_TUI_MD_BANNER[$key]=$out
	fi
	IFS=$'\x1f' read -ra _TUI_MD_BR <<<"${_TUI_MD_BANNER[$key]}"
}

# _tui_md.cellw STR -> _VL - cells of a plain string with multi-byte glyphs: continuation bytes are not counted, so the
# result is the same under a UTF-8 locale and under LC_ALL=C.
_tui_md.cellw() {
	local s=${1//[$'\x80'-$'\xbf']/}
	_VL=${#s}
}

# _tui_md.heading_banner TEXT FONT WIDTH SGR LINENO - appends TEXT as block letters, words greedily packed into banner
# lines that fit WIDTH; rc 1 (nothing appended, no link collected) when a single word is wider than WIDTH or there is no text.
_tui_md.heading_banner() {
	local font=$2 width=$3 sgr=$4 lineno=$5 plain line="" cand w r marks nu=${#TUI_MD_LINK_URLS[@]}
	local -a words out=()
	# an underline would strike through the letter rows
	sgr=${sgr//\[4;/\[}
	sgr=${sgr//;4;/;}
	sgr=${sgr//;4m/m}
	_tui_md.inline_memo "$1" ""
	plain=${_MD_OUT//[!$'\x02']/}
	marks=${#plain}
	tui.md.strip "$_MD_OUT" plain
	plain=${plain//$'\x02'/}
	read -ra words <<<"$plain"
	if ((${#words[@]} == 0)); then
		_tui_md.unlink "$nu"
		return 1
	fi
	for w in "${words[@]}"; do
		cand=${line:+$line }$w
		if ! _tui_md.banner "$font" "$cand"; then
			_tui_md.unlink "$nu"
			return 1
		fi
		_tui_md.cellw "${_TUI_MD_BR[0]}"
		if ((_VL <= width)); then
			line=$cand
			continue
		fi
		if [[ -z "$line" ]]; then
			_tui_md.unlink "$nu"
			return 1
		fi
		_tui_md.banner "$font" "$line"
		for r in "${_TUI_MD_BR[@]}"; do out+=("${sgr}${r}${_TUI_MD_RESET}"); done
		_tui_md.banner "$font" "$w" || {
			_tui_md.unlink "$nu"
			return 1
		}
		_tui_md.cellw "${_TUI_MD_BR[0]}"
		if ((_VL > width)); then
			_tui_md.unlink "$nu"
			return 1
		fi
		line=$w
	done
	_tui_md.banner "$font" "$line"
	for r in "${_TUI_MD_BR[@]}"; do out+=("${sgr}${r}${_TUI_MD_RESET}"); done
	while ((marks-- > 0)); do TUI_MD_LINK_ROWS+=("${#TUI_MD_ROWS[@]}"); done
	for r in "${out[@]}"; do
		TUI_MD_ROWS+=("$r")
		TUI_MD_MAP+=("$lineno")
	done
}

# _tui_md.unlink COUNT - forgets the links collected after the first COUNT (a heading that fell back to plain text).
_tui_md.unlink() {
	TUI_MD_LINK_URLS=("${TUI_MD_LINK_URLS[@]:0:$1}")
	TUI_MD_LINK_TEXTS=("${TUI_MD_LINK_TEXTS[@]:0:$1}")
}

# tui.md.style_set CLASS SGR - replaces one class of the style table.
tui.md.style_set() {
	_TUI_MD_SGR[$1]="$2"
	_TUI_MD_DIRECT[$1]="$2"
	_TUI_MD_MEMO=()
}

# tui.md.strip STR [VAR] - STR with every SGR sequence removed: printed, or stored in VAR.
tui.md.strip() {
	local _in=$1 _out=""
	while [[ $_in == *$'\e['* ]]; do
		_out+=${_in%%$'\e['*}
		_in=${_in#*$'\e['}
		_in=${_in#*m}
	done
	_out+=$_in
	if [[ -n "${2:-}" ]]; then printf -v "$2" %s "$_out"; else printf %s "$_out"; fi
}

# _tui_md.charw CODEPOINT -> _CW - terminal cells of one character: 2 for East Asian wide and emoji, 0 for combining marks.
_tui_md.charw() {
	local cp=$1
	_CW=1
	if ((cp < 0x300)); then return 0; fi
	if ((cp <= 0x36F || (cp >= 0x200B && cp <= 0x200F) || cp == 0xFE0F || (cp >= 0x20D0 && cp <= 0x20FF))) || [[ -n "${_TUI_MD_ZW[$cp]:-}" ]]; then
		_CW=0
	elif ((cp >= 0x1100 && cp <= 0x115F || cp >= 0x2E80 && cp <= 0xA4CF || cp >= 0xAC00 && cp <= 0xD7A3 ||
		cp >= 0xF900 && cp <= 0xFAFF || cp >= 0xFE30 && cp <= 0xFE6F || cp >= 0xFF00 && cp <= 0xFF60 ||
		cp >= 0xFFE0 && cp <= 0xFFE6 || cp >= 0x1F300 && cp <= 0x1F64F || cp >= 0x1F900 && cp <= 0x1F9FF ||
		cp >= 0x20000 && cp <= 0x3FFFD)); then
		_CW=2
	fi
}

# _tui_md.cells STR -> _VL - terminal cells of a plain string. Pure ASCII is ${#}; under a UTF-8 locale wide characters count
# twice and combining marks not at all. Under LC_ALL=C bytes are counted, as ${#} does.
_tui_md.cells() {
	local s=$1 run c cp
	_VL=${#s}
	[[ "$s" != *[!\ -~]* ]] && return 0
	local u=$'\xc3\xa9'
	((${#u} == 1)) || return 0
	while [[ -n "$s" ]]; do
		run=${s%%[!\ -~]*} # an ASCII run costs one cell per character: skipped whole
		s=${s:${#run}}
		[[ -z "$s" ]] && break
		c=${s:0:1}
		s=${s:1}
		printf -v cp '%d' "'$c"
		((cp < 0x300)) && continue
		_tui_md.charw "$cp"
		((_VL += _CW - 1))
	done
}

# _tui_md.vlen STR -> _VL - visible cells of STR (SGR excluded).
_tui_md.vlen() {
	local t=$1 v=""
	if [[ $t != *$'\e['* ]]; then
		_tui_md.cells "$t"
		return 0
	fi
	while [[ $t == *$'\e['* ]]; do
		v+=${t%%$'\e['*}
		t=${t#*$'\e['}
		t=${t#*m}
	done
	v+=$t
	_tui_md.cells "$v"
}

# _tui_md.track STR - updates the caller's `act` (the SGR active after STR).
_tui_md.track() {
	local t=$1 q
	[[ $t == *$'\e['* ]] || return 0
	while [[ $t == *$'\e['* ]]; do
		t=${t#*$'\e['}
		q=${t%%m*}
		t=${t#*m}
		if [[ -z "$q" || "$q" == 0 ]]; then act=""; else act+=$'\e['"${q}m"; fi
	done
}

# _tui_md.cut STR N -> _CH _CT _CN - the first N visible cells of STR, the rest, and the cells of the head; SGR sequences stay whole.
_tui_md.cut() {
	local s=$1 n=$2 head="" seq run cnt=0 c cp w left
	if [[ $s != *$'\e['* && "$s" != *[!\ -~]* ]]; then
		_CH=${s:0:n} _CT=${s:n}
		_CN=${#_CH}
		return 0
	fi
	while [[ -n "$s" ]] && ((cnt < n)); do
		run=${s%%[!\ -~]*} # an ASCII run is one cell per character: taken whole, no per-character loop
		if [[ -n "$run" ]]; then
			left=$((n - cnt))
			((${#run} > left)) && run=${run:0:left}
			head+=$run
			s=${s:${#run}}
			((cnt += ${#run}))
			continue
		fi
		if [[ "${s:0:2}" == $'\e[' ]]; then
			seq=${s%%m*}m
			head+=$seq
			s=${s:${#seq}}
			continue
		fi
		c=${s:0:1}
		printf -v cp '%d' "'$c"
		_tui_md.charw "$cp"
		w=$_CW
		((cnt + w > n)) && break # a wide character that does not fit starts the next row
		head+=$c
		s=${s:1}
		((cnt += w))
	done
	_CH=$head _CT=$s _CN=$cnt
}

# _tui_md.wrap STR WIDTH LINENO - word-wraps STR (words split on spaces, \x01 = hard break) and appends the rows.
# A style open at a row break is closed there and reopened on the next row.
_tui_md.wrap() {
	local width=$2 lineno=$3 row="" rw=0 act="" placed=0 w wl
	local -a words
	read -ra words <<<"$1"
	local marks=0
	for w in "${words[@]}"; do
		if [[ "$w" == $'\x01' ]]; then
			((placed)) && _tui_md.wrap_flush
			continue
		fi
		marks=0
		if [[ "$w" == *[!\ -~]* ]]; then # SGR, a link marker or a non-ASCII character: the slow path
			while [[ "$w" == *$'\x02'* ]]; do # link start: not a cell, remembers the row
				w=${w/$'\x02'/}
				((marks++))
			done
			_tui_md.vlen "$w"
			wl=$_VL
		else
			wl=${#w}
		fi
		if ((placed && rw + 1 + wl <= width)); then
			row+=" $w"
			((rw += 1 + wl))
		else
			((placed)) && _tui_md.wrap_flush
			while ((wl > width)); do
				_tui_md.cut "$w" "$width"
				row=$act$_CH
				_tui_md.track "$_CH"
				placed=1
				_tui_md.wrap_flush
				w=$_CT
				_tui_md.vlen "$w"
				wl=$_VL
			done
			row=$act$w
			rw=$wl
			placed=1
		fi
		while ((marks > 0)); do
			TUI_MD_LINK_ROWS+=("${#TUI_MD_ROWS[@]}")
			((marks--))
		done
		[[ "$w" == *$'\e['* ]] && _tui_md.track "$w"
	done
	((placed)) && _tui_md.wrap_flush
}

# _tui_md.wrap_flush - appends the caller's `row` (closed with a reset while a style is still open) and clears it.
_tui_md.wrap_flush() {
	[[ -n "$act" ]] && row+=$_TUI_MD_RESET
	TUI_MD_ROWS+=("$row")
	TUI_MD_MAP+=("$lineno")
	row="" rw=0 placed=0
}

# _tui_md.code_end STR FROM N -> _CE - index of the next run of exactly N backticks at or after FROM; rc 1 when there is none.
_tui_md.code_end() {
	local s=$1 i=$2 n=$3 len=${#1} j pre
	while ((i < len)); do
		pre=${s:i}
		pre=${pre%%\`*}
		((i += ${#pre}))
		((i >= len)) && return 1
		j=$i
		while [[ "${s:j:1}" == '`' ]]; do ((j++)); done
		if ((j - i == n)); then
			_CE=$i
			return 0
		fi
		i=$j
	done
	return 1
}

# _tui_md.find_close STR FROM CH N DEPTH -> _FC - start of the N delimiter characters that close an emphasis opened before FROM.
# A run that can only open (space before, text after) is a nested span: it is skipped together with its own closer.
_tui_md.find_close() {
	local s=$1 i=$2 ch=$3 n=$4 d=$5 len=${#1} c j m p nx can_close can_open k
	while ((i < len)); do
		c=${s:i:1}
		if [[ "$c" == '\' ]]; then
			((i += 2))
			continue
		fi
		if [[ "$c" == '`' ]]; then
			j=$i
			while [[ "${s:j:1}" == '`' ]]; do ((j++)); done
			if _tui_md.code_end "$s" "$j" $((j - i)); then i=$((_CE + j - i)); else i=$j; fi
			continue
		fi
		if [[ "$c" != "$ch" ]]; then
			((i++))
			continue
		fi
		j=$i
		while [[ "${s:j:1}" == "$ch" ]]; do ((j++)); done
		m=$((j - i))
		p=" " nx=" "
		((i > 0)) && p=${s:i-1:1}
		((j < len)) && nx=${s:j:1}
		can_close=0 can_open=0
		[[ "$p" != [[:space:]] ]] && can_close=1
		[[ "$nx" != [[:space:]] ]] && can_open=1
		if [[ "$ch" == _ ]]; then
			[[ "$nx" == [[:alnum:]] ]] && can_close=0
			[[ "$p" == [[:alnum:]] ]] && can_open=0
		fi
		if ((can_close && m >= n)); then
			_FC=$((j - n))
			return 0
		fi
		if ((can_open && !can_close && d < 3)) && _tui_md.find_close "$s" "$j" "$ch" "$m" $((d + 1)); then
			i=$((_FC + m))
			continue
		fi
		i=$j
	done
	return 1
}

# _tui_md.link STR -> _LT _LU _LN - parses "[text](url "title")" at the start of STR: text, url, index after ")"; rc 1 when it is not a link.
_tui_md.link() {
	local s=$1 len=${#1} i=1 depth=1 j pd=1 ch dest
	while ((i < len)); do
		ch=${s:i:1}
		case "$ch" in
			'\')
				((i += 2))
				continue
				;;
			'`')
				j=$i
				while [[ "${s:j:1}" == '`' ]]; do ((j++)); done
				if _tui_md.code_end "$s" "$j" $((j - i)); then i=$((_CE + j - i)); else i=$j; fi
				continue
				;;
			'[') ((depth++)) ;;
			']') ((--depth == 0)) && break ;;
		esac
		((i++))
	done
	((depth == 0)) || return 1
	if [[ "${s:i+1:1}" != "(" ]]; then
		# [text][label], [text][] and the shortcut [label]: the URL comes from a [label]: URL definition
		local label=${s:1:i-1} k
		if [[ "${s:i+1:1}" == "[" ]]; then
			k=${s:i+2}
			k=${k%%]*}
			[[ "${s:i+2+${#k}:1}" == "]" ]] || return 1
			[[ -n "$k" ]] && label=$k
			_LN=$((i + 3 + ${#k}))
		else
			_LN=$((i + 1))
		fi
		label=${label,,}
		label=${label//[[:space:]]/ }
		[[ -n "${_TUI_MD_REFS[$label]+x}" ]] || return 1
		_LT=${s:1:i-1}
		_LU=${_TUI_MD_REFS[$label]}
		return 0
	fi
	j=$((i + 2))
	while ((j < len)); do
		ch=${s:j:1}
		case "$ch" in
			'\')
				((j += 2))
				continue
				;;
			'(') ((pd++)) ;;
			')') ((--pd == 0)) && break ;;
		esac
		((j++))
	done
	((pd == 0)) || return 1
	dest=${s:i+2:j-i-2}
	_LT=${s:1:i-1} _LN=$((j + 1))
	dest=${dest#"${dest%%[![:space:]]*}"}
	_LU=${dest%%[[:space:]]*}
}

# _tui_md.inline TEXT BASE -> _MD_OUT - the inline spans of one paragraph. BASE is the style already open around TEXT: every
# span closes with a reset and reopens BASE. In keep mode (styled source) the delimiters stay, drawn with the marker style.
_tui_md.inline() {
	local s=$1 base=$2 out="" pre c n m run inner after sgr delim fc nx pv prevc=" " next lk
	local marker=${_TUI_MD_SGR[marker]} reset=$_TUI_MD_RESET
	if ((TUI_MD_DEGRADED)) || [[ "$s" != *[\\*_\`\[~\<]* ]]; then
		_MD_OUT=$s
		return 0
	fi
	while [[ -n "$s" ]]; do
		pre=${s%%[\\*_\`\[~\<]*}
		if [[ "$pre" == "$s" ]]; then
			out+=$s
			break
		fi
		out+=$pre
		[[ -n "$pre" ]] && prevc=${pre: -1}
		s=${s:${#pre}}
		c=${s:0:1}
		case "$c" in
			'\')
				next=${s:1:1}
				if [[ -n "$next" && "$next" == [[:punct:]] ]]; then
					if ((_TUI_MD_KEEP)); then out+="${marker}\\${reset}${base}$next"; else out+=$next; fi
					s=${s:2} prevc=$next
				else
					out+='\'
					s=${s:1} prevc='\'
				fi
				;;
			'`')
				run=${s%%[!\`]*}
				n=${#run}
				if _tui_md.code_end "$s" "$n" "$n"; then
					inner=${s:n:_CE-n}
					if ((_TUI_MD_KEEP)); then
						out+="${marker}${run}${reset}${base}${_TUI_MD_SGR[code]}${inner}${reset}${marker}${run}${reset}${base}"
					else
						if [[ "$inner" == " "*" " && -n "${inner//[ ]/}" ]]; then inner=${inner:1:${#inner}-2}; fi
						out+="${_TUI_MD_SGR[code]}${inner}${reset}${base}"
					fi
					s=${s:_CE+n} prevc='`'
				else
					out+=$run
					s=${s:n} prevc='`'
				fi
				;;
			'<')
				# an autolink <scheme:rest> or <user@host>: its own text and target
				if [[ "$s" =~ ^\<([a-zA-Z][a-zA-Z0-9+.-]*:[^[:space:]\<\>]+|[^[:space:]\<\>@]+@[^[:space:]\<\>@]+\.[^[:space:]\<\>@]+)\> ]]; then
					lk=${BASH_REMATCH[1]}
					delim=$lk
					[[ "$lk" != *:* ]] && delim="mailto:$lk"
					fc=${#BASH_REMATCH[0]}
					if ((_TUI_MD_KEEP)); then
						out+="${marker}<${reset}${base}${_TUI_MD_SGR[link]}${lk}${reset}${marker}>${reset}${base}"
					else
						n=${#TUI_MD_LINK_URLS[@]}
						TUI_MD_LINK_URLS+=("$delim")
						TUI_MD_LINK_TEXTS+=("$lk")
						sgr=${_TUI_MD_SGR[link]}
						((n == _TUI_MD_FOCUS_LINK)) && sgr=${_TUI_MD_SGR[link_focus]}
						out+=$'\x02'"${sgr}${lk}${reset}${base}"
					fi
					s=${s:fc} prevc='>'
				else
					out+='<'
					s=${s:1} prevc='<'
				fi
				;;
			'[')
				if _tui_md.link "$s"; then
					lk=$_LT fc=$_LN delim=$_LU
					if ((_TUI_MD_KEEP)); then
						_tui_md.inline "$lk" "$base${_TUI_MD_SGR[link]}"
						out+="${marker}[${reset}${base}${_TUI_MD_SGR[link]}${_MD_OUT}${reset}${marker}${s:${#lk}+1:fc-${#lk}-1}${reset}${base}"
					elif [[ "${out: -1}" == "!" ]]; then
						# an image: a placeholder with its description (no terminal graphics here)
						out=${out%!}
						case "$TUI_MD_IMAGES" in
							hidden) ;;
							alt) out+=$lk ;;
							*) out+="${marker}[img${lk:+: $lk}]${reset}${base}" ;;
						esac
					else
						n=${#TUI_MD_LINK_URLS[@]} # numbered before its text, so a nested link comes after
						TUI_MD_LINK_URLS+=("$delim")
						TUI_MD_LINK_TEXTS+=("$lk")
						sgr=${_TUI_MD_SGR[link]}
						((n == _TUI_MD_FOCUS_LINK)) && sgr=${_TUI_MD_SGR[link_focus]}
						_tui_md.inline "$lk" "$base$sgr"
						out+=$'\x02'"${sgr}${_MD_OUT}${reset}${base}"
						# a link that is only a picture (a badge) stays quiet: its URL would be longer than the badge
						[[ "$TUI_MD_LINK_URL" != hidden && -n "$delim" && "$lk" != '!['* ]] && out+=" ($delim)"
					fi
					s=${s:fc} prevc=')'
				else
					out+='['
					s=${s:1} prevc='['
				fi
				;;
			*)
				m=0
				while [[ "${s:m:1}" == "$c" ]]; do ((m++)); done
				nx=${s:m:1}
				pv=$prevc
				if ((m > 3)) || [[ -z "$nx" || "$nx" == [[:space:]] ]] || [[ "$c" == _ && "$pv" == [[:alnum:]] ]] ||
					[[ "$c" == "~" && $m != 2 ]]; then
					out+=${s:0:m}
					s=${s:m} prevc=$c
					continue
				fi
				if _tui_md.find_close "$s" "$m" "$c" "$m" 0; then
					fc=$_FC
					inner=${s:m:fc-m}
					case "$m" in
						1) sgr=${_TUI_MD_SGR[em]} ;;
						2) [[ "$c" == "~" ]] && sgr=${_TUI_MD_SGR[strike]} || sgr=${_TUI_MD_SGR[strong]} ;;
						*) sgr=${_TUI_MD_SGR[strong]}${_TUI_MD_SGR[em]} ;;
					esac
					_tui_md.inline "$inner" "$base$sgr"
					delim=${s:0:m}
					if ((_TUI_MD_KEEP)); then
						out+="${marker}${delim}${reset}${base}${sgr}${_MD_OUT}${reset}${marker}${s:fc:m}${reset}${base}"
					else
						out+="${sgr}${_MD_OUT}${reset}${base}"
					fi
					after=${s:fc+m}
					prevc=${s:fc+m-1:1}
					s=$after
				else
					out+=${s:0:m}
					s=${s:m} prevc=$c
				fi
				;;
		esac
	done
	_MD_OUT=$out
}

# _tui_md.memo_clear - forgets the memoized inline results.
_tui_md.memo_clear() {
	_TUI_MD_IMEMO=()
	_TUI_MD_IMEMO_SIG=""
}

# _tui_md.memo_sync - drops the memo when anything an inline result depends on besides its text changed.
_tui_md.memo_sync() {
	local sig="${_TUI_MD_SGR[*]}|$TUI_MD_IMAGES|$TUI_MD_LINK_URL|$TUI_MD_DEGRADED|${_TUI_MD_PLACEHOLDER:-}|$TUI_MD_BASE_DIR|${!_TUI_MD_REFS[*]}|${_TUI_MD_REFS[*]}"
	[[ "$sig" == "$_TUI_MD_IMEMO_SIG" ]] && return 0
	_TUI_MD_IMEMO=()
	_TUI_MD_IMEMO_SIG=$sig
}

# _tui_md.inline_memo TEXT BASE -> _MD_OUT - _tui_md.inline of a whole paragraph or heading, memoized: the result does not
# depend on the width, so a resize reuses it. A hit replays the links the span collected. The focus style is part of the
# result: an entry is reused only while the focused link is outside the links it holds, or was the same when it was made.
_tui_md.inline_memo() {
	if ((TUI_MD_DEGRADED)) || [[ "$1" != *[\\*_\`\[~\<]* ]]; then
		_tui_md.inline "$1" "$2"
		return 0
	fi
	local n0=${#TUI_MD_LINK_URLS[@]} key v k fc urls texts f=$_TUI_MD_FOCUS_LINK e i
	key="$2"$'\x1f'"$n0"$'\x1f'"$1"
	if [[ -n "${_TUI_MD_IMEMO[$key]+x}" ]]; then
		v=${_TUI_MD_IMEMO[$key]}
		k=${v%%$'\x1e'*} v=${v#*$'\x1e'}
		fc=${v%%$'\x1e'*} v=${v#*$'\x1e'}
		urls=${v%%$'\x1e'*} v=${v#*$'\x1e'}
		texts=${v%%$'\x1e'*}
		if ((f == fc)) || ! { ((f >= n0 && f < n0 + k)) || ((fc >= n0 && fc < n0 + k)); }; then
			_MD_OUT=${v#*$'\x1e'}
			if ((k > 0)); then
				local -a arr
				IFS=$'\x1f' read -ra arr <<<"$urls"
				for e in "${arr[@]}"; do TUI_MD_LINK_URLS+=("${e:1}"); done
				IFS=$'\x1f' read -ra arr <<<"$texts"
				for e in "${arr[@]}"; do TUI_MD_LINK_TEXTS+=("${e:1}"); done
			fi
			return 0
		fi
	fi
	_tui_md.inline "$1" "$2"
	k=$((${#TUI_MD_LINK_URLS[@]} - n0))
	urls="" texts=""
	for ((i = n0; i < n0 + k; i++)); do
		urls+="E${TUI_MD_LINK_URLS[i]}"$'\x1f'
		texts+="E${TUI_MD_LINK_TEXTS[i]}"$'\x1f'
	done
	((${#_TUI_MD_IMEMO[@]} >= 4096)) && _TUI_MD_IMEMO=()
	_TUI_MD_IMEMO[$key]="$k"$'\x1e'"$f"$'\x1e'"$urls"$'\x1e'"$texts"$'\x1e'"$_MD_OUT"
}

# ── row cache ──────────────────────────────────────────────────────────

_TUI_MD_RC_SLOTS=6
_TUI_MD_RC_ARRAYS=(ROWS MAP URLS TEXTS LROWS HEADS)

# _tui_md.cache_clear - forgets every cached render.
_tui_md.cache_clear() { _TUI_MD_RC_KEY=(); _TUI_MD_RC_NEXT=0; }

# _tui_md.cache_flags WIDTH -> _CK - everything a render depends on besides the text. Graphics images read files and
# allocate ids, so a render that may show one is not cacheable (rc 1).
_tui_md.cache_flags() {
	[[ "$TUI_MD_IMAGES" == graphics ]] && return 1
	_tui_md.sync
	_CK="$1|$TUI_MD_BREAKS|$TUI_MD_FONTS|$TUI_MD_TABLES|$TUI_MD_TABLE_OVERFLOW|$TUI_MD_IMAGES|$TUI_MD_LINK_URL|$TUI_MD_MAX_BYTES"
	_CK+="|$_TUI_MD_FOCUS_LINK|$TUI_MD_BASE_DIR|${_TUI_MD_PLACEHOLDER:-}|${LC_ALL-}${LC_CTYPE-}${LANG-}|${_TUI_MD_HFONT[*]}|${!_TUI_MD_HL[*]}|${_TUI_MD_SGR[*]}"
}

# _tui_md.cache_get FLAGS TEXT - loads a cached render into TUI_MD_*; rc 1 on a miss.
_tui_md.cache_get() {
	local key="$1"$'\x1f'"$2" s k
	for s in "${!_TUI_MD_RC_KEY[@]}"; do
		[[ "${_TUI_MD_RC_KEY[s]}" == "$key" ]] || continue
		local -n rows=_TUI_MD_RC_ROWS_$s map=_TUI_MD_RC_MAP_$s urls=_TUI_MD_RC_URLS_$s texts=_TUI_MD_RC_TEXTS_$s
		local -n lrows=_TUI_MD_RC_LROWS_$s heads=_TUI_MD_RC_HEADS_$s anch=_TUI_MD_RC_ANCH_$s
		TUI_MD_ROWS=("${rows[@]}") TUI_MD_MAP=("${map[@]}") TUI_MD_LINK_URLS=("${urls[@]}") TUI_MD_LINK_TEXTS=("${texts[@]}")
		TUI_MD_LINK_ROWS=("${lrows[@]}") TUI_MD_HEADS=("${heads[@]}")
		TUI_MD_ANCHORS=()
		for k in "${!anch[@]}"; do TUI_MD_ANCHORS[$k]=${anch[$k]}; done
		TUI_MD_DEGRADED=${_TUI_MD_RC_DEG[s]}
		TUI_MD_IMAGE_IDS=() _TUI_MD_REFS=()
		return 0
	done
	return 1
}

# _tui_md.cache_put FLAGS TEXT - keeps the completed render in TUI_MD_* (the oldest of the slots is replaced).
_tui_md.cache_put() {
	local s=$_TUI_MD_RC_NEXT k
	_TUI_MD_RC_NEXT=$(((s + 1) % _TUI_MD_RC_SLOTS))
	declare -ga "_TUI_MD_RC_ROWS_$s" "_TUI_MD_RC_MAP_$s" "_TUI_MD_RC_URLS_$s" "_TUI_MD_RC_TEXTS_$s" "_TUI_MD_RC_LROWS_$s" "_TUI_MD_RC_HEADS_$s"
	declare -gA "_TUI_MD_RC_ANCH_$s"
	local -n rows=_TUI_MD_RC_ROWS_$s map=_TUI_MD_RC_MAP_$s urls=_TUI_MD_RC_URLS_$s texts=_TUI_MD_RC_TEXTS_$s
	local -n lrows=_TUI_MD_RC_LROWS_$s heads=_TUI_MD_RC_HEADS_$s anch=_TUI_MD_RC_ANCH_$s
	rows=("${TUI_MD_ROWS[@]}") map=("${TUI_MD_MAP[@]}") urls=("${TUI_MD_LINK_URLS[@]}") texts=("${TUI_MD_LINK_TEXTS[@]}")
	lrows=("${TUI_MD_LINK_ROWS[@]}") heads=("${TUI_MD_HEADS[@]}")
	anch=()
	for k in "${!TUI_MD_ANCHORS[@]}"; do anch[$k]=${TUI_MD_ANCHORS[$k]}; done
	_TUI_MD_RC_DEG[s]=$TUI_MD_DEGRADED
	_TUI_MD_RC_KEY[s]="$1"$'\x1f'"$2"
}

# ── disk snapshot: a file's render survives the session ──────────────────────
# $TUI_HOME/cache/markdown/<path with / as %>@<width>.rows holds the render of a file shown with tui.md.show_file as shell
# assignments, plus the key it was made for. It is used while it is newer than the file and its key is today's (same width,
# styles, flags): one source, no parse. The last line sets _TUI_MD_DC_OK, so a half-written file is never used.

# _tui_md.disk_path SRC WIDTH -> _DP - rc 1 when there is no usable place.
_tui_md.disk_path() {
	local n=${1//\//%}
	[[ -n "${TUI_HOME:-}" && -n "$1" ]] && ((${#n} < 180)) || return 1
	_DP="$TUI_HOME/cache/markdown/$n@$2.rows"
}

# _tui_md.disk_get SRC WIDTH KEY - loads the snapshot into TUI_MD_*; rc 1 on a miss.
_tui_md.disk_get() {
	_tui_md.disk_path "$1" "$2" || return 1
	[[ -r "$_DP" && "$_DP" -nt "$1" ]] || return 1
	_TUI_MD_DC_KEY="" _TUI_MD_DC_OK=0
	source "$_DP" 2>/dev/null || return 1
	[[ $_TUI_MD_DC_OK == 1 && "$_TUI_MD_DC_KEY" == "$3" ]]
}

# _tui_md.disk_dump NAME - one array as an assignment (nothing for an empty one: printf %q with no argument prints '')
_tui_md.disk_dump() {
	local -n _dd=$1
	((${#_dd[@]})) || {
		printf '%s=()\n' "$1"
		return 0
	}
	printf '%s=(' "$1"
	printf ' %q' "${_dd[@]}"
	printf ' )\n'
}

# _tui_md.disk_put SRC WIDTH KEY - writes the completed render in TUI_MD_* (best effort).
_tui_md.disk_put() {
	local k dir="${TUI_HOME:-}/cache/markdown"
	_tui_md.disk_path "$1" "$2" || return 1
	((_TUI_MD_DISK_DIR_OK)) || {
		mkdir -p "$dir" 2>/dev/null || return 1
		_TUI_MD_DISK_DIR_OK=1
	}
	{
		printf '_TUI_MD_DC_KEY=%q\n' "$3"
		_tui_md.disk_dump TUI_MD_ROWS
		_tui_md.disk_dump TUI_MD_MAP
		_tui_md.disk_dump TUI_MD_LINK_URLS
		_tui_md.disk_dump TUI_MD_LINK_TEXTS
		_tui_md.disk_dump TUI_MD_LINK_ROWS
		_tui_md.disk_dump TUI_MD_HEADS
		printf 'TUI_MD_ANCHORS=()\n'
		for k in "${!TUI_MD_ANCHORS[@]}"; do printf 'TUI_MD_ANCHORS[%q]=%q\n' "$k" "${TUI_MD_ANCHORS[$k]}"; done
		printf 'TUI_MD_DEGRADED=%d\n_TUI_MD_DC_OK=1\n' "$TUI_MD_DEGRADED"
	} >"$_DP" 2>/dev/null
}

# _tui_md.render_cached TEXT WIDTH [ROWS] - tui.md.render through the row cache (_TUI_MD_HIT says whether it hit). With
# ROWS > 0 a miss may stop early (_TUI_MD_RES_DONE=0); the caller finishes it and calls _tui_md.cache_done.
_tui_md.render_cached() {
	local width=$2
	((width < 1)) && width=1
	_TUI_MD_HIT=0
	if _tui_md.cache_flags "$width"; then
		_TUI_MD_RES_KEY=$_CK
		if _tui_md.cache_get "$_CK" "$1"; then
			_TUI_MD_HIT=1 _TUI_MD_RES_DONE=1
			_tui_perf.count md_cache_hit
			return 0
		fi
		if [[ -n "$_TUI_MD_DISK_SRC" ]] && ((_TUI_MD_FOCUS_LINK < 0)) && _tui_perf.begin md_disk_load && _tui_md.disk_get "$_TUI_MD_DISK_SRC" "$width" "$_CK"; then
			_tui_perf.end md_disk_load
			TUI_MD_IMAGE_IDS=() _TUI_MD_REFS=()
			_TUI_MD_HIT=2 _TUI_MD_RES_DONE=1
			_tui_md.cache_put "$_CK" "$1"
			_tui_perf.count md_disk_hit
			return 0
		fi
		_tui_perf.count md_cache_miss
		_tui_perf.begin md_render
		_tui_md.render_begin "$1" "$width" "${3:-0}" "${4:-0}" "${5:-0}" "${6:-0}"
		_tui_perf.end md_render
		if ((_TUI_MD_RES_DONE && ${4:-0} == 0)); then # a render that began mid-document is not the document
			_tui_md.cache_put "$_CK" "$1"
			_tui_md.pd_blocks "$1"
			[[ -n "$_TUI_MD_DISK_SRC" ]] && ((_TUI_MD_FOCUS_LINK < 0)) && _tui_md.disk_put "$_TUI_MD_DISK_SRC" "$width" "$_CK"
		fi
		return 0
	fi
	_TUI_MD_RES_KEY=""
	_tui_md.render_begin "$1" "$width" 0
	((_TUI_MD_RES_DONE)) && _tui_md.pd_blocks "$1"
	return 0
}

# _tui_md.is_blank TEXT - rc 0 when TEXT holds only whitespace.
_tui_md.is_blank() { [[ -z "${1//[[:space:]]/}" ]]; }

# _tui_md.is_plain TEXT - rc 0 when the first character cannot start any block: skips the regex chain for most lines.
_tui_md.is_plain() {
	local c=${1:0:1}
	if [[ "$c" == " " ]]; then
		c=${1#"${1%%[! ]*}"}
		c=${c:0:1}
	fi
	case "$c" in
		[\#\>\`~*_+0-9=-]) return 1 ;;
	esac
	return 0
}

# _tui_md.block_start TEXT - rc 0 when the line opens a block that interrupts a paragraph or lazy continuation.
_tui_md.block_start() {
	_tui_md.is_plain "$1" && return 1
	[[ "$1" =~ $_TUI_MD_RE_HEAD || "$1" =~ $_TUI_MD_RE_FENCE || "$1" =~ $_TUI_MD_RE_HR ||
		"$1" =~ $_TUI_MD_RE_QUOTE || "$1" =~ $_TUI_MD_RE_LIST ]]
}

# _tui_md.code_row LINE WIDTH LINENO [HLFN] - one code line as a row of exactly WIDTH cells: highlighted by HLFN (it sets
# TUI_MD_HL from LINE), clipped with a "›" or padded.
_tui_md.code_row() {
	local line=$1 width=$2 hl=${4:-} sgr=${_TUI_MD_SGR[codeblock]} body pad="" tail="" reset=$_TUI_MD_RESET
	_tui_md.cells "$line"
	if ((_VL > width)); then
		_tui_md.cut "$line" $((width - 1))
		line=$_CH
		tail="›"
		_VL=$((width - 1))
	fi
	body=$line
	if [[ -n "$hl" ]]; then
		TUI_MD_HL=$line
		"$hl" "$line"
		body=${TUI_MD_HL//"$reset"/"$reset$sgr"} # the code block style continues after every span
	fi
	local used=$_VL
	[[ -n "$tail" ]] && ((used++))
	((used < width)) && printf -v pad '%*s' $((width - used)) ''
	TUI_MD_ROWS+=("${sgr}${body}${tail}${pad}${reset}")
	TUI_MD_MAP+=("$3")
}

# _tui_md.slug TEXT -> _SLUG - the anchor of a heading: lower case, spaces to "-", punctuation dropped, "-N" on a repeat.
_tui_md.slug() {
	local t=${1,,} s="" i c n=0
	t=${t//[[:space:]]/-}
	for ((i = 0; i < ${#t}; i++)); do
		c=${t:i:1}
		[[ "$c" == [[:alnum:]_-] || "$c" == [!\ -~] ]] && s+=$c
	done
	_SLUG=$s
	while [[ -n "${TUI_MD_ANCHORS[$_SLUG]+x}" ]]; do _SLUG="$s-$((++n))"; done
}

# _tui_md.heading LEVEL TEXT WIDTH LINENO - a heading in its font or style; records its anchor and outline entry.
_tui_md.heading() {
	local level=$1 text=$2 width=$3 ln=$4 h=${_TUI_MD_SGR[h$1]} first=${#TUI_MD_ROWS[@]} plain
	if ((TUI_MD_FONTS)) && [[ -n "${_TUI_MD_HFONT[$level]:-}" ]] &&
		_tui_md.heading_banner "$text" "${_TUI_MD_HFONT[$level]}" "$width" "$h" "$ln"; then
		:
	else
		_tui_md.inline_memo "$text" "$h"
		_tui_md.wrap "$h$_MD_OUT" "$width" "$ln"
	fi
	plain=${text//[\*_\`~|]/}
	local re='\[([^]]*)\]\([^)]*\)'
	while [[ "$plain" =~ $re ]]; do plain=${plain/"${BASH_REMATCH[0]}"/"${BASH_REMATCH[1]}"}; done
	_tui_md.slug "$plain"
	TUI_MD_ANCHORS[$_SLUG]=$first
	TUI_MD_HEADS+=("$level|$plain|$first|$((${#TUI_MD_ROWS[@]} - 1))|$ln")
}

# _tui_md.blocks WIDTH N:LINE... - scans the numbered lines into blocks and appends their rows. Containers (quote, list item)
# render their content recursively at a narrower width, then prefix the rows they got.
_tui_md.blocks() {
	local width=$1
	shift
	local -a L=("$@") sub
	local n=${#L[@]} i=0 j k ln t tl lnj emitted=0 start
	local fc fchar flen lead ct run rest sgr pad line h text hard
	local setext lang hlfn task level plain ind marker spaces off ordered lkind="" loose iw pw pfx glyph cont first nt prevpara=0 nogap
	local top=$_TUI_MD_TOP start_i=0
	_TUI_MD_TOP=0
	if ((top)); then # the top-level call may resume where the last one stopped
		i=$_TUI_MD_RES_I emitted=$_TUI_MD_RES_EM prevpara=$_TUI_MD_RES_PP start_i=$i
		((_TUI_MD_END_I > 0 && _TUI_MD_END_I < n)) && n=$_TUI_MD_END_I # a window [start, end): the prefix of a viewport-first render
	fi
	while ((i < n)); do
		# stop at a block boundary once the row budget or the time slice is used; one block always makes progress
		if ((top && _TUI_MD_STOP && i > start_i)) &&
			{ ((_TUI_MD_STOP_ROWS && ${#TUI_MD_ROWS[@]} >= _TUI_MD_STOP_ROWS)) ||
				((_TUI_MD_STOP_AT && ${EPOCHREALTIME//[!0-9]/} >= _TUI_MD_STOP_AT)); }; then
			_TUI_MD_RES_I=$i _TUI_MD_RES_EM=$emitted _TUI_MD_RES_PP=$prevpara _TUI_MD_RES_DONE=0
			return 0
		fi
		ln=${L[i]%%:*}
		t=${L[i]#*:}
		if [[ -z "${t//[[:space:]]/}" ]]; then
			prevpara=0
			((i++))
			continue
		fi
		((top)) && { # where this block starts: a later render can begin here instead of at the top
			_TUI_MD_BI+=("$i")
			_TUI_MD_BE+=("$emitted")
			_TUI_MD_BP+=("$prevpara")
		}
		# a list that follows its paragraph line directly is tight (the usual "- a" / "  - b" nesting)
		nogap=0
		((prevpara)) && ! _tui_md.is_plain "$t" && [[ "$t" =~ $_TUI_MD_RE_LIST && ! "$t" =~ $_TUI_MD_RE_HR ]] && nogap=1
		prevpara=0
		((emitted && !nogap)) && {
			TUI_MD_ROWS+=("")
			TUI_MD_MAP+=($((ln - 1)))
		}
		emitted=1
		plain=0
		_tui_md.is_plain "$t" && plain=1
		if ((!plain)) && [[ "$t" =~ $_TUI_MD_RE_FENCE ]]; then
			fc=${BASH_REMATCH[1]} fchar=${BASH_REMATCH[1]:0:1} flen=${#BASH_REMATCH[1]}
			lang=${BASH_REMATCH[2]#"${BASH_REMATCH[2]%%[![:space:]]*}"}
			lang=${lang%%[[:space:]]*}
			hlfn=""
			[[ -n "$lang" ]] && hlfn=${_TUI_MD_HL[${lang,,}]:-}
			j=$((i + 1))
			while ((j < n)); do
				tl=${L[j]#*:}
				lead=${tl%%[! ]*}
				ct=${tl#"$lead"}
				if ((${#lead} <= 3)) && [[ "$ct" == "$fchar"* ]]; then
					run=${ct%%[!"$fchar"]*}
					rest=${ct:${#run}}
					if ((${#run} >= flen)) && [[ -z "${rest//[[:space:]]/}" ]]; then
						((j++))
						break
					fi
				fi
				_tui_md.code_row "$tl" "$width" "${L[j]%%:*}" "$hlfn"
				((j++))
			done
			i=$j
		elif [[ "$t" == "    "* ]]; then
			# indented code: consecutive lines indented by 4+, blank lines between them kept
			j=$i
			k=$i
			while ((j < n)); do
				tl=${L[j]#*:}
				if [[ "$tl" == "    "* ]]; then
					k=$j
				elif ! _tui_md.is_blank "$tl"; then
					break
				fi
				((j++))
			done
			for ((j = i; j <= k; j++)); do
				tl=${L[j]#*:}
				_tui_md.code_row "${tl:4}" "$width" "${L[j]%%:*}"
			done
			i=$((k + 1))
		elif ((!plain)) && [[ "$t" =~ $_TUI_MD_RE_HEAD ]]; then
			level=${#BASH_REMATCH[1]}
			text=${BASH_REMATCH[3]}
			if [[ "$text" =~ ^(.*[^[:space:]#]|)[[:space:]]+#+[[:space:]]*$ ]]; then text=${BASH_REMATCH[1]}; fi
			text=${text#"${text%%[![:space:]]*}"}
			text=${text%"${text##*[![:space:]]}"}
			_tui_md.heading "$level" "$text" "$width" "$ln"
			((i++))
		elif ((!plain)) && [[ "$t" =~ $_TUI_MD_RE_HR ]]; then
			if [[ -z "${_TUI_MD_HR[$width]+x}" ]]; then
				printf -v pad '%*s' "$width" ''
				_TUI_MD_HR[$width]=${pad// /─}
			fi
			TUI_MD_ROWS+=("${_TUI_MD_SGR[hr]}${_TUI_MD_HR[$width]}${_TUI_MD_RESET}")
			TUI_MD_MAP+=("$ln")
			((i++))
		elif ((!plain)) && [[ "$t" =~ $_TUI_MD_RE_QUOTE ]]; then
			sub=()
			j=$i
			while ((j < n)); do
				tl=${L[j]#*:}
				lnj=${L[j]%%:*}
				if [[ "$tl" =~ $_TUI_MD_RE_QUOTE ]]; then
					sub+=("$lnj:${BASH_REMATCH[1]}")
				elif ((j > i)) && [[ -n "${tl//[[:space:]]/}" ]] && ! _tui_md.block_start "$tl"; then
					sub+=("$lnj:$tl")
				else
					break
				fi
				((j++))
			done
			start=${#TUI_MD_ROWS[@]}
			iw=$((width - 2))
			((iw < 1)) && iw=1
			_tui_md.blocks "$iw" "${sub[@]}"
			pfx="${_TUI_MD_SGR[quote]}│${_TUI_MD_RESET} "
			for ((k = start; k < ${#TUI_MD_ROWS[@]}; k++)); do TUI_MD_ROWS[k]=$pfx${TUI_MD_ROWS[k]}; done
			i=$j
		elif ((!plain)) && [[ "$t" =~ $_TUI_MD_RE_LIST ]]; then
			first=1 loose=0 lkind=""
			while :; do
				ln=${L[i]%%:*}
				t=${L[i]#*:}
				[[ "$t" =~ $_TUI_MD_RE_LIST ]] || break
				ind=${BASH_REMATCH[1]} marker=${BASH_REMATCH[2]} rest=${BASH_REMATCH[4]}
				spaces=$((${#BASH_REMATCH[3]} - ${#rest}))
				ordered=0
				[[ "$marker" == *[.\)] ]] && ordered=1
				if ((ordered)); then k=ordered; else k=bullet; fi
				if ((first)); then
					lkind=$k first=0
				elif [[ "$k" != "$lkind" ]]; then
					break
				elif ((loose)); then
					TUI_MD_ROWS+=("")
					TUI_MD_MAP+=($((ln - 1)))
				fi
				if ((spaces < 1)); then
					off=$((${#ind} + ${#marker} + 1))
				elif ((spaces > 4)); then
					off=$((${#ind} + ${#marker} + 1))
					rest=${BASH_REMATCH[3]:1}
				else
					off=$((${#ind} + ${#marker} + spaces))
				fi
				sub=("$ln:$rest")
				j=$((i + 1))
				while ((j < n)); do
					tl=${L[j]#*:}
					lnj=${L[j]%%:*}
					if [[ -z "${tl//[[:space:]]/}" ]]; then
						k=$j
						while ((k < n)) && _tui_md.is_blank "${L[k]#*:}"; do ((k++)); done
						((k >= n)) && break
						nt=${L[k]#*:}
						lead=${nt%%[! ]*}
						((${#lead} >= off)) || break
						while ((j < k)); do
							sub+=("${L[j]%%:*}:")
							((j++))
						done
						continue
					fi
					lead=${tl%%[! ]*}
					if ((${#lead} >= off)); then
						sub+=("$lnj:${tl:off}")
					elif ! _tui_md.is_blank "${L[j-1]#*:}" && ! _tui_md.block_start "$tl"; then
						sub+=("$lnj:${tl#"$lead"}")
					else
						break
					fi
					((j++))
				done
				task=""
				if [[ "${sub[0]#*:}" =~ ^\[([\ xX])\][[:space:]]+(.*)$ ]]; then
					[[ "${BASH_REMATCH[1]}" == " " ]] && task="☐" || task="☑"
					sub[0]="$ln:${BASH_REMATCH[2]}"
				fi
				if [[ -n "$task" ]]; then
					pfx="${_TUI_MD_SGR[bullet]}${task}${_TUI_MD_RESET} "
					pw=2
				elif ((ordered)); then
					pfx="${_TUI_MD_SGR[bullet]}${marker}${_TUI_MD_RESET} "
					pw=$((${#marker} + 1))
				else
					case $((_TUI_MD_DEPTH % 3)) in
						0) glyph="•" ;;
						1) glyph="◦" ;;
						*) glyph="▪" ;;
					esac
					pfx="${_TUI_MD_SGR[bullet]}${glyph}${_TUI_MD_RESET} "
					pw=2
				fi
				printf -v cont '%*s' "$pw" ''
				iw=$((width - pw))
				((iw < 1)) && iw=1
				start=${#TUI_MD_ROWS[@]}
				((_TUI_MD_DEPTH++))
				_tui_md.blocks "$iw" "${sub[@]}"
				((_TUI_MD_DEPTH--))
				if ((${#TUI_MD_ROWS[@]} == start)); then
					TUI_MD_ROWS+=("$pfx")
					TUI_MD_MAP+=("$ln")
				else
					for ((k = start; k < ${#TUI_MD_ROWS[@]}; k++)); do
						if ((k == start)); then
							TUI_MD_ROWS[k]=$pfx${TUI_MD_ROWS[k]}
						elif [[ -n "${TUI_MD_ROWS[k]}" ]]; then
							TUI_MD_ROWS[k]=$cont${TUI_MD_ROWS[k]}
						fi
					done
				fi
				i=$j
				# a sibling item continues the list; a blank line before it makes the list loose
				k=$i
				while ((k < n)) && _tui_md.is_blank "${L[k]#*:}"; do ((k++)); done
				((k < n)) || break
				loose=$((k > i))
				i=$k
			done
		elif [[ "$t" == *"|"* ]] && _tui_md.table_at; then
			_tui_md.table_render "$width"
		else
			j=$((i + 1))
			while ((j < n)); do
				tl=${L[j]#*:}
				[[ -z "${tl//[[:space:]]/}" ]] && break
				if ! _tui_md.is_plain "$tl"; then
					[[ "$tl" =~ $_TUI_MD_RE_SETEXT_EQ ]] && break
					_tui_md.block_start "$tl" && break
				fi
				((j++))
			done
			setext=0
			if ((j < n)); then
				tl=${L[j]#*:}
				if _tui_md.is_plain "$tl"; then
					:
				elif [[ "$tl" =~ $_TUI_MD_RE_SETEXT_EQ ]]; then setext=1; elif [[ "$tl" =~ $_TUI_MD_RE_SETEXT_DASH ]]; then setext=2; fi
			fi
			text=""
			for ((k = i; k < j; k++)); do
				tl=${L[k]#*:}
				tl=${tl#"${tl%%[![:space:]]*}"}
				hard=0
				if [[ "$tl" == *"  " ]]; then
					hard=1
				elif [[ "$tl" == *'\' ]]; then
					hard=1
					tl=${tl%\\}
				fi
				tl=${tl%"${tl##*[![:space:]]}"}
				text+="${text:+ }$tl"
				((hard || TUI_MD_BREAKS)) && ((k < j - 1)) && text+=" "$'\x01'
			done
			if [[ "$TUI_MD_IMAGES" == graphics && "$text" == *"!["* ]] && _tui_md.image_strip "$text" "$width" "$ln"; then
				:
			elif ((setext)); then
				# "Title" over === (level 1) or --- (level 2) is a heading, not a paragraph and a rule
				_tui_md.heading "$setext" "$text" "$width" "$ln"
				((j++))
			else
				_tui_md.inline_memo "$text" ""
				_tui_md.wrap "$_MD_OUT" "$width" "$ln"
				prevpara=1
			fi
			i=$j
		fi
	done
	((top)) && _TUI_MD_RES_DONE=1
	return 0
}

# _tui_md.prepare TEXT -> _MD_ROW (the cleaned text) - drops control bytes and carriage returns; sets TUI_MD_DEGRADED.
_tui_md.prepare() {
	local t=${1//$'\r'/}
	t=${t//[$_TUI_MD_CTRL]/}
	_MD_ROW=$t
	TUI_MD_DEGRADED=0
	((${#t} > TUI_MD_MAX_BYTES)) && TUI_MD_DEGRADED=1
	((_TUI_MD_PREPS++))
	_tui_md.reset_out
	return 0
}

# _tui_md.reset_out - empties what a render produces.
_tui_md.reset_out() {
	TUI_MD_ROWS=() TUI_MD_MAP=() TUI_MD_LINK_URLS=() TUI_MD_LINK_TEXTS=() TUI_MD_LINK_ROWS=() TUI_MD_HEADS=()
	TUI_MD_ANCHORS=() _TUI_MD_REFS=() TUI_MD_IMAGE_IDS=()
}

# ── prepared documents: the width-independent half of a render ────────────────
# Control bytes, tabs, HTML and reference definitions, the split into numbered lines: none of it depends on the width, so it is
# done once per text (4 kept). A render at another width starts from the numbered lines. Once a render has completed the
# slot also holds where every top-level block starts (_tui_md.pd_blocks), which lets a later render begin in the middle.

# _tui_md.pd_find TEXT -> _PDS - the slot of a prepared text (rc 1: none).
_tui_md.pd_find() {
	local s
	for s in "${!_TUI_MD_PD_KEY[@]}"; do
		[[ "${_TUI_MD_PD_KEY[s]}" == "$1" ]] && {
			_PDS=$s
			return 0
		}
	done
	return 1
}

# _tui_md.pd_put TEXT - keeps _TUI_MD_LINES, _TUI_MD_REFS and the degraded flag of a render that just prepared TEXT.
_tui_md.pd_put() {
	local s=$_TUI_MD_PD_NEXT k
	_TUI_MD_PD_NEXT=$(((s + 1) % 4))
	declare -ga "_TUI_MD_PD_LINES_$s" "_TUI_MD_PD_BI_$s" "_TUI_MD_PD_BE_$s" "_TUI_MD_PD_BP_$s"
	declare -gA "_TUI_MD_PD_REFS_$s"
	local -n ln=_TUI_MD_PD_LINES_$s refs=_TUI_MD_PD_REFS_$s bi=_TUI_MD_PD_BI_$s be=_TUI_MD_PD_BE_$s bp=_TUI_MD_PD_BP_$s
	ln=("${_TUI_MD_LINES[@]}")
	refs=()
	for k in "${!_TUI_MD_REFS[@]}"; do refs[$k]=${_TUI_MD_REFS[$k]}; done
	bi=() be=() bp=()
	_TUI_MD_PD_KEY[s]=$1
	_TUI_MD_PD_DEG[s]=$TUI_MD_DEGRADED
	_TUI_MD_PD_HAS[s]=0
}

# _tui_md.pd_blocks TEXT - keeps the block records (_TUI_MD_BI/BE/BP) of the completed render of TEXT.
_tui_md.pd_blocks() {
	_tui_md.pd_find "$1" || return 0
	local -n bi=_TUI_MD_PD_BI_$_PDS be=_TUI_MD_PD_BE_$_PDS bp=_TUI_MD_PD_BP_$_PDS
	bi=("${_TUI_MD_BI[@]}") be=("${_TUI_MD_BE[@]}") bp=("${_TUI_MD_BP[@]}")
	_TUI_MD_PD_HAS[_PDS]=1
}

# _tui_md.block_for_line SLOT LINE -> _BK - index of the top-level block that holds source line LINE (1-based).
_tui_md.block_for_line() {
	local -n bi=_TUI_MD_PD_BI_$1
	local k
	_BK=0
	for k in "${!bi[@]}"; do
		((bi[k] + 1 <= $2)) || break
		_BK=$k
	done
}

# _tui_md.scratch_clean - removes the scratch file at exit.
_tui_md.scratch_clean() {
	[[ -n "$_TUI_MD_SCRATCH" && "$_TUI_MD_SCRATCH" != "-" ]] && rm -f "$_TUI_MD_SCRATCH"
	_TUI_MD_SCRATCH=""
}

# _tui_md.split TEXT ARRAY - TEXT's lines into ARRAY. mapfile reads a file ~3x faster than a here-string (which goes through a
# pipe): the text is written to a private scratch file first (a builtin write, no fork; the file is made once per process).
declare -g _TUI_MD_SCRATCH=""
_tui_md.split() {
	local -n _sp_out=$2
	if [[ -z "$_TUI_MD_SCRATCH" ]]; then
		_tui_mktemp _TUI_MD_SCRATCH dabt-md 2>/dev/null || _TUI_MD_SCRATCH="-"
	fi
	if [[ "$_TUI_MD_SCRATCH" != "-" ]] && printf '%s\n' "$1" >"$_TUI_MD_SCRATCH" 2>/dev/null; then
		mapfile -t _sp_out <"$_TUI_MD_SCRATCH"
	else
		mapfile -t _sp_out <<<"$1"
	fi
}

# tui.md.render TEXT WIDTH - renders TEXT into rows of at most WIDTH cells (containers need a few cells more than their prefix).
tui.md.render() {
	_tui_md.render_begin "$1" "$2" 0
}

# _tui_md.render_begin TEXT WIDTH ROWS [START_I EM PP] - starts a render; with ROWS > 0 it stops at the first block boundary
# past ROWS rows (_TUI_MD_RES_DONE=0) and _tui_md.render_more continues it. ROWS 0 renders everything. START_I EM PP begin
# at a recorded top-level block instead of the first (viewport first: what is above is rendered afterwards).
_tui_md.render_begin() {
	local width=$2
	((width < 1)) && width=1
	_TUI_MD_KEEP=0 _TUI_MD_DEPTH=0
	((_TUI_MD_RENDERS++))
	_tui_md.sync
	_TUI_MD_RES_DONE=1 _TUI_MD_RES_I=${4:-0} _TUI_MD_RES_EM=${5:-0} _TUI_MD_RES_PP=${6:-0} _TUI_MD_RES_W=$width _TUI_MD_LINES=()
	_TUI_MD_BI=() _TUI_MD_BE=() _TUI_MD_BP=() _TUI_MD_END_I=0
	if _tui_md.pd_find "$1"; then # prepared before, at any width
		local k
		local -n _pln=_TUI_MD_PD_LINES_$_PDS _prf=_TUI_MD_PD_REFS_$_PDS
		_tui_md.reset_out
		TUI_MD_DEGRADED=${_TUI_MD_PD_DEG[_PDS]}
		_TUI_MD_LINES=("${_pln[@]}")
		for k in "${!_prf[@]}"; do _TUI_MD_REFS[$k]=${_prf[$k]}; done
		_TUI_MD_RES_DONE=0
		_tui_md.render_more 0 "$3"
		return 0
	fi
	_tui_md.prepare "$1"
	[[ -z "$_MD_ROW" ]] && return 0
	local text=${_MD_ROW//$'\t'/    }
	local -a lines
	local i
	if [[ "$text" == *"<"* || "$text" == *"]:"* || "$text" == *"&"* ]]; then
		_tui_md.html_pass "$text" # tags mapped, comments and [label]: url definitions blanked (same line count)
		text=$_MD_ROW
	fi
	_tui_md.split "$text" lines
	for ((i = 0; i < ${#lines[@]}; i++)); do lines[i]="$((i + 1)):${lines[i]}"; done
	_TUI_MD_LINES=("${lines[@]}")
	_tui_md.pd_put "$1"
	_TUI_MD_RES_I=${4:-0} _TUI_MD_RES_EM=${5:-0} _TUI_MD_RES_PP=${6:-0}
	_TUI_MD_RES_DONE=0
	_tui_md.render_more 0 "$3"
}

# _tui_md.render_more BUDGET_US ROWS - continues a render: stops at the first block boundary after BUDGET_US microseconds
# or when TUI_MD_ROWS holds ROWS rows (0 = no limit). The page background is applied to the rows of this step.
_tui_md.render_more() {
	local from=${#TUI_MD_ROWS[@]}
	((_TUI_MD_RES_DONE)) && return 0
	_tui_md.memo_sync
	_TUI_MD_STOP_ROWS=$2 _TUI_MD_STOP_AT=0 _TUI_MD_STOP=0
	if (($1 > 0)); then _TUI_MD_STOP_AT=$((${EPOCHREALTIME//[!0-9]/} + $1)); fi
	((_TUI_MD_STOP_ROWS || _TUI_MD_STOP_AT)) && _TUI_MD_STOP=1
	_TUI_MD_TOP=1
	_tui_md.blocks "$_TUI_MD_RES_W" "${_TUI_MD_LINES[@]}"
	_TUI_MD_STOP=0
	[[ -n "${_TUI_MD_SGR[page]}" ]] && _tui_md.page_rows "$_TUI_MD_RES_W" "$from"
	return 0
}

# _tui_md.page_rows WIDTH [FROM] - the document background: every row from FROM on, gaps included, padded to WIDTH under the page style.
_tui_md.page_rows() {
	local pg=${_TUI_MD_SGR[page]} reset=$_TUI_MD_RESET i row pad
	for ((i = ${2:-0}; i < ${#TUI_MD_ROWS[@]}; i++)); do
		row=${TUI_MD_ROWS[i]}
		_tui_md.vlen "$row"
		pad=""
		(($1 > _VL)) && printf -v pad '%*s' $(($1 - _VL)) ''
		TUI_MD_ROWS[i]="${pg}${row//"$reset"/"$reset$pg"}${pad}${reset}"
	done
}

# _tui_md.style_line LINE -> _MD_ROW - one source line, styled outside code fences.
_tui_md.style_line() {
	local line=$1 reset=$_TUI_MD_RESET marker=${_TUI_MD_SGR[marker]} h
	if [[ "$line" =~ $_TUI_MD_RE_HEAD ]]; then
		h=${_TUI_MD_SGR[h${#BASH_REMATCH[1]}]}
		local hashes=${BASH_REMATCH[1]} body=${BASH_REMATCH[3]} gap=${BASH_REMATCH[2]%"${BASH_REMATCH[3]}"}
		local lead=${line%%"$hashes"*}
		_tui_md.inline "$body" "$h"
		_MD_ROW="${marker}${lead}${hashes}${gap}${reset}"
		[[ -n "$body" ]] && _MD_ROW+="${h}${_MD_OUT}${reset}"
	elif [[ "$line" =~ $_TUI_MD_RE_HR ]]; then
		_MD_ROW="${_TUI_MD_SGR[hr]}${line}${reset}"
	elif [[ "$line" =~ $_TUI_MD_RE_SQUOTE ]]; then
		local qm=${BASH_REMATCH[1]} qrest=${BASH_REMATCH[2]}
		_tui_md.style_line "$qrest"
		_MD_ROW="${marker}${qm}${reset}${_MD_ROW}"
	elif [[ "$line" =~ $_TUI_MD_RE_SLIST ]]; then
		local li=${BASH_REMATCH[1]} lm=${BASH_REMATCH[2]} ls=${BASH_REMATCH[3]} lr=${BASH_REMATCH[4]}
		_tui_md.inline "$lr" ""
		_MD_ROW="${li}${_TUI_MD_SGR[bullet]}${lm}${reset}${ls}${_MD_OUT}"
	else
		_tui_md.inline "$line" ""
		_MD_ROW=$_MD_OUT
	fi
}

# _tui_md.style_row LINE - styles one source line in keep mode -> _MD_ROW. The caller's infence/fchar/flen carry the code-fence
# state across lines. Lines outside fences are memoized: moving the cursor or editing one line re-styles that line only.
_tui_md.style_row() {
	local line=${1//$'\e'/} run rest
	if ((infence)); then
		run=${line#"${line%%[! ]*}"}
		rest=""
		if [[ "$run" == "$fchar"* ]]; then
			rest=${run#"${run%%[!"$fchar"]*}"}
			run=${run%"$rest"}
		fi
		if [[ "$run" == "$fchar"* ]] && ((${#run} >= flen)) && [[ -z "${rest//[[:space:]]/}" ]]; then
			infence=0
			_MD_ROW="${_TUI_MD_SGR[marker]}${line}${_TUI_MD_RESET}"
		elif [[ -n "$line" ]]; then
			_MD_ROW="${_TUI_MD_SGR[codeblock]}${line}${_TUI_MD_RESET}"
		else
			_MD_ROW=""
		fi
	elif [[ "$line" == *'```'* || "$line" == *'~~~'* ]] && [[ "$line" =~ $_TUI_MD_RE_FENCE ]]; then
		infence=1 fchar=${BASH_REMATCH[1]:0:1} flen=${#BASH_REMATCH[1]}
		_MD_ROW="${_TUI_MD_SGR[marker]}${line}${_TUI_MD_RESET}"
	elif [[ -z "$line" ]]; then
		_MD_ROW=""
	elif [[ -n "${_TUI_MD_MEMO[$line]+x}" ]]; then
		_MD_ROW=${_TUI_MD_MEMO[$line]}
	else
		_tui_md.style_line "$line"
		((${#_TUI_MD_MEMO[@]} >= 4096)) && _TUI_MD_MEMO=()
		_TUI_MD_MEMO[$line]=$_MD_ROW
	fi
}

# tui.md.style TEXT - styled source: one row per source line, characters unchanged, delimiters drawn with the marker style.
tui.md.style() {
	_TUI_MD_KEEP=1 _TUI_MD_DEPTH=0
	_tui_md.prepare "$1"
	local -a lines
	local i infence=0 fchar="" flen=0
	if [[ -n "$_MD_ROW" ]]; then
		mapfile -t lines <<<"$_MD_ROW"
		for ((i = 0; i < ${#lines[@]}; i++)); do
			_tui_md.style_row "${lines[i]}"
			TUI_MD_ROWS+=("$_MD_ROW")
			TUI_MD_MAP+=($((i + 1)))
		done
	fi
	_TUI_MD_KEEP=0
}

# tui.md.fence_before TEXT TOP VAR - the code-fence state ("" outside, "CHAR:LEN" inside) in force at source line TOP (0-based).
tui.md.fence_before() {
	local text=$1 top=$2 i infence=0 fchar="" flen=0 state=""
	if ((top > 0)) && [[ "$text" == *'```'* || "$text" == *'~~~'* ]]; then
		local -a lines
		mapfile -t lines <<<"$text"
		_TUI_MD_KEEP=1
		for ((i = 0; i < top && i < ${#lines[@]}; i++)); do
			[[ "${lines[i]}" == *'`'* || "${lines[i]}" == *'~'* || $infence == 1 ]] && _tui_md.style_row "${lines[i]}"
		done
		_TUI_MD_KEEP=0
		((infence)) && state="$fchar:$flen"
	fi
	printf -v "$3" %s "$state"
}

# tui.md.style_lines FENCE LINE... - styled rows of consecutive source lines -> TUI_MD_ROWS (one per LINE, characters unchanged).
tui.md.style_lines() {
	local state=$1 infence=0 fchar="" flen=0 line
	shift
	[[ -n "$state" ]] && infence=1 fchar=${state%%:*} flen=${state##*:}
	TUI_MD_ROWS=()
	_TUI_MD_KEEP=1 _TUI_MD_DEPTH=0 TUI_MD_DEGRADED=0
	for line in "$@"; do
		_tui_md.style_row "$line"
		TUI_MD_ROWS+=("$_MD_ROW")
	done
	_TUI_MD_KEEP=0
}

# _tui_md.slice ROW LEFT WIDTH -> _SL - the cells [LEFT, LEFT+WIDTH) of a styled row, padded to WIDTH. The slice opens in the
# style active at LEFT and closes any style still open at its end.
_tui_md.slice() {
	local row=$1 left=$2 width=$3 act="" pad="" head
	if ((left > 0)); then
		_tui_md.cut "$row" "$left"
		_tui_md.track "$_CH"
		row=$_CT
	fi
	_tui_md.cut "$row" "$width"
	head=$_CH
	((_CN < width)) && printf -v pad '%*s' $((width - _CN)) ''
	_SL="${act}${head}${pad}"
	_tui_md.track "$head"
	[[ -n "$act" ]] && _SL+=$_TUI_MD_RESET
	return 0
}

# _tui_md.top_line PANE -> _TL - the source line (1-based) of the row at the top of the pane's view; rc 1 without a render.
_tui_md.top_line() {
	local off=${_TUI_P_SOFF_V[$1]:-0} r
	local -n _tm=_TUI_MD_M_$1 _td=_TUI_MD_D_$1
	((${#_tm[@]})) || return 1
	for r in "${!_td[@]}"; do
		if ((_td[r] >= off)); then
			_TL=${_tm[r]:-1}
			((_TL < 1)) && _TL=1
			return 0
		fi
	done
	return 1
}

# _tui_md.scroll_to_line PANE LINE - puts the first row of source line LINE (or the first row after it) at the top of the view.
_tui_md.scroll_to_line() {
	local r
	local -n _tm=_TUI_MD_M_$1 _td=_TUI_MD_D_$1
	for r in "${!_tm[@]}"; do
		if ((_tm[r] >= $2)); then
			_TUI_P_SOFF_V[$1]=${_td[r]:-0}
			((${_TUI_RUNNING:-0})) && _tui._queue_render "$1"
			return 0
		fi
	done
	return 1
}

# _tui_md.paint_pane PANE [full] - renders the pane's source at its current width (folds and search kept) into the pane.
# Without "full" only the first screens are rendered and painted at once; _tui_md.more_timer finishes the rest. A pane that is
# scrolled keeps its place by source line, not by row: when the document is known (its top-level blocks are recorded) the
# render begins at the block that holds the top line, so the view is what is painted first, and the part above follows.
_tui_md.paint_pane() {
	local pane=$1 w rows L=0 start=0 em=0 pp=0 text slot
	_tui._content_rect "$pane"
	w=$((_CR_W - 1)) # the scrollbar column
	((w < 1)) && w=1
	rows=$((_CR_H + _CR_H / 2 + 4))
	[[ "${2:-}" == full ]] && rows=0
	_TUI_MD_SHOWN_W[$pane]=$w
	_TUI_MD_FOCUS_LINK=-1 # the focused link is drawn over the rows by _tui_md.compose, so a focus step re-renders nothing
	TUI_MD_BASE_DIR=""
	[[ -n "${_TUI_MD_V[$pane.file]:-}" ]] && TUI_MD_BASE_DIR=${_TUI_MD_V[$pane.file]%/*}
	unset '_TUI_MD_PEND[$pane]'
	text=${_TUI_MD_SHOWN[$pane]}
	if ((${_TUI_P_SOFF_V[$pane]:-0} > 0)) && _tui_md.top_line "$pane"; then L=$_TL; fi
	if ((L > 1 && rows > 0)); then
		if _tui_md.pd_find "$text" && ((${_TUI_MD_PD_HAS[_PDS]:-0})); then
			slot=$_PDS
			_tui_md.block_for_line "$slot" "$L"
			if ((_BK > 0)); then
				local -n _bi=_TUI_MD_PD_BI_$slot _be=_TUI_MD_PD_BE_$slot _bp=_TUI_MD_PD_BP_$slot
				start=${_bi[_BK]} em=${_be[_BK]} pp=${_bp[_BK]}
			fi
		fi
		((start > 0)) || rows=0 # no record of the blocks yet: render it all now, the place is kept by line
	fi
	_TUI_MD_DISK_SRC=${_TUI_MD_V[$pane.disk]:-}
	_tui_md.render_cached "$text" "$w" "$rows" "$start" "$em" "$pp"
	_TUI_MD_DISK_SRC=""
	_TUI_MD_FOCUS_LINK=-1
	TUI_MD_BASE_DIR=""
	_tui_md.images_present "$pane"
	_tui_md.store "$pane"
	_TUI_MD_RS[$pane.pre_end]="" _TUI_MD_RS[$pane.pstarted]=""
	if ((start > 0 && _TUI_MD_HIT == 0)); then
		# viewport first: the rows shown begin at block START; the part above is rendered by _tui_md.more_pane
		_tui_md.pend_save "$pane"
		_TUI_MD_RS[$pane.pre_end]=$start _TUI_MD_RS[$pane.l]=$L _TUI_MD_RS[$pane.soff0]=0
		((_TUI_MD_RES_DONE)) && _TUI_MD_RS[$pane.phase]=pre || _TUI_MD_RS[$pane.phase]=fwd
		_TUI_MD_RS[$pane.pi]=0 _TUI_MD_RS[$pane.pem]=0 _TUI_MD_RS[$pane.ppp]=0
		_TUI_P_SOFF_V[$pane]=0
		_TUI_MD_PEND[$pane]=1
		tui.after 0.02 _tui_md.more_timer md_more
		_tui_md.compose "$pane"
		return 0
	fi
	if ((!_TUI_MD_RES_DONE)); then
		_tui_md.pend_save "$pane"
		_TUI_MD_RS[$pane.phase]=fwd
		_TUI_MD_PEND[$pane]=1
		tui.after 0.02 _tui_md.more_timer md_more
	fi
	_tui_md.compose "$pane"
	((L > 1 && _TUI_MD_RES_DONE)) && _tui_md.scroll_to_line "$pane" "$L"
	return 0
}

# _tui_md.pend_save PANE - keeps what resuming the unfinished render needs besides the rows _tui_md.store holds.
_tui_md.pend_save() {
	local pane=$1 k
	declare -ga "_TUI_MD_LN_$pane"
	declare -gA "_TUI_MD_RF_$pane"
	local -n ln=_TUI_MD_LN_$pane rf=_TUI_MD_RF_$pane
	ln=("${_TUI_MD_LINES[@]}")
	rf=()
	for k in "${!_TUI_MD_REFS[@]}"; do rf[$k]=${_TUI_MD_REFS[$k]}; done
	_TUI_MD_RS[$pane.i]=$_TUI_MD_RES_I _TUI_MD_RS[$pane.em]=$_TUI_MD_RES_EM _TUI_MD_RS[$pane.pp]=$_TUI_MD_RES_PP
	_TUI_MD_RS[$pane.w]=$_TUI_MD_RES_W _TUI_MD_RS[$pane.key]=$_TUI_MD_RES_KEY _TUI_MD_RS[$pane.deg]=$TUI_MD_DEGRADED
	_TUI_MD_RS[$pane.disk]=${_TUI_MD_V[$pane.disk]:-}
}

# _tui_md.more_pane PANE BUDGET_US - renders the next slice of the pane's unfinished render (BUDGET_US 0: all of it), then
# stores, caches (when complete) and repaints it. Two phases: "fwd" goes on with the blocks after the last one rendered; a
# viewport-first render then continues with "pre", the blocks above where it began, and joins them in front.
_tui_md.more_pane() {
	local pane=$1 k phase
	[[ -n "${_TUI_MD_PEND[$pane]+x}" ]] || return 0
	_tui_md.sync_key
	if [[ "$_SK" != "$_TUI_MD_SYNC_KEY" ]]; then # the theme changed meanwhile: the rows so far no longer match
		_tui_md.paint_pane "$pane" full
		return 0
	fi
	phase=${_TUI_MD_RS[$pane.phase]:-fwd}
	_TUI_MD_KEEP=0 _TUI_MD_DEPTH=0 _TUI_MD_FOCUS_LINK=-1
	TUI_MD_BASE_DIR=""
	[[ -n "${_TUI_MD_V[$pane.file]:-}" ]] && TUI_MD_BASE_DIR=${_TUI_MD_V[$pane.file]%/*}
	if [[ -n "${_TUI_MD_RS[$pane.key]}" ]] && _tui_md.cache_flags "${_TUI_MD_RS[$pane.w]}" && [[ "$_CK" != "${_TUI_MD_RS[$pane.key]}" ]]; then
		TUI_MD_BASE_DIR="" # a style or setting changed since the render began: what is rendered so far does not match
		_tui_md.paint_pane "$pane" full
		return 0
	fi
	_tui_perf.begin md_slice
	if [[ "$phase" == pre ]]; then
		_tui_md.prefix_slice "$pane" "$2"
		_tui_perf.end md_slice
		TUI_MD_BASE_DIR=""
		return 0
	fi
	_tui_md.unstash "_TUI_MD_" "$pane"
	local -n ln=_TUI_MD_LN_$pane rf=_TUI_MD_RF_$pane
	_TUI_MD_LINES=("${ln[@]}")
	_TUI_MD_REFS=()
	for k in "${!rf[@]}"; do _TUI_MD_REFS[$k]=${rf[$k]}; done
	_TUI_MD_RES_I=${_TUI_MD_RS[$pane.i]} _TUI_MD_RES_EM=${_TUI_MD_RS[$pane.em]} _TUI_MD_RES_PP=${_TUI_MD_RS[$pane.pp]}
	_TUI_MD_RES_W=${_TUI_MD_RS[$pane.w]} TUI_MD_DEGRADED=${_TUI_MD_RS[$pane.deg]} _TUI_MD_RES_DONE=0
	_tui_md.render_more "$2" 0
	_tui_perf.end md_slice
	TUI_MD_BASE_DIR=""
	_tui_md.store "$pane"
	if ((_TUI_MD_RES_DONE)); then
		if [[ -n "${_TUI_MD_RS[$pane.pre_end]}" ]]; then
			_TUI_MD_RS[$pane.phase]=pre # the blocks from the start of the render to the end are in: the part above is left
		else
			_tui_md.finish "$pane"
		fi
	else
		_TUI_MD_RS[$pane.i]=$_TUI_MD_RES_I _TUI_MD_RS[$pane.em]=$_TUI_MD_RES_EM _TUI_MD_RS[$pane.pp]=$_TUI_MD_RES_PP
	fi
	_tui_md.compose "$pane"
}

# _tui_md.finish PANE - the render in TUI_MD_* (and stored) is the whole document: cache it, drop the pending state.
_tui_md.finish() {
	local pane=$1
	unset '_TUI_MD_PEND[$pane]'
	_TUI_MD_RS[$pane.pre_end]=""
	if [[ -n "${_TUI_MD_RS[$pane.key]}" ]]; then
		_tui_md.cache_put "${_TUI_MD_RS[$pane.key]}" "${_TUI_MD_SHOWN[$pane]}"
		[[ -n "${_TUI_MD_RS[$pane.disk]}" ]] && _tui_md.disk_put "${_TUI_MD_RS[$pane.disk]}" "${_TUI_MD_RS[$pane.w]}" "${_TUI_MD_RS[$pane.key]}"
	fi
	_tui_md.pd_blocks "${_TUI_MD_SHOWN[$pane]}"
}

# _tui_md.stash PREFIX PANE / _tui_md.unstash PREFIX PANE - copy the render in TUI_MD_* to / from the pane's arrays named
# PREFIX<WHAT>_PANE (the pane's displayed render is stored by _tui_md.store, the prefix of a viewport-first one is parked under
# _TUI_MD_PR_).
_tui_md.stash() {
	local pre=$1 pane=$2 k
	declare -ga "${pre}ROWS_$pane" "${pre}MAP_$pane" "${pre}URLS_$pane" "${pre}TEXTS_$pane" "${pre}LROWS_$pane" "${pre}HEADS_$pane" "${pre}BI_$pane" "${pre}BE_$pane" "${pre}BP_$pane"
	local -n a=${pre}ROWS_$pane b=${pre}MAP_$pane c=${pre}URLS_$pane d=${pre}TEXTS_$pane e=${pre}LROWS_$pane f=${pre}HEADS_$pane
	local -n g=${pre}BI_$pane h=${pre}BE_$pane i=${pre}BP_$pane
	a=("${TUI_MD_ROWS[@]}") b=("${TUI_MD_MAP[@]}") c=("${TUI_MD_LINK_URLS[@]}") d=("${TUI_MD_LINK_TEXTS[@]}")
	e=("${TUI_MD_LINK_ROWS[@]}") f=("${TUI_MD_HEADS[@]}") g=("${_TUI_MD_BI[@]}") h=("${_TUI_MD_BE[@]}") i=("${_TUI_MD_BP[@]}")
}
_tui_md.unstash() {
	local pre=$1 pane=$2 k
	if [[ "$pre" == _TUI_MD_ ]]; then # the pane's displayed render: the names _tui_md.store uses
		local -n a=_TUI_MD_B_$pane b=_TUI_MD_M_$pane c=_TUI_MD_U_$pane d=_TUI_MD_X_$pane e=_TUI_MD_LR_$pane f=_TUI_MD_H_$pane
		local -n g=_TUI_MD_BI_$pane h=_TUI_MD_BE_$pane i=_TUI_MD_BP_$pane an=_TUI_MD_A_$pane
		TUI_MD_ANCHORS=()
		for k in "${!an[@]}"; do TUI_MD_ANCHORS[$k]=${an[$k]}; done
	else
		local -n a=${pre}ROWS_$pane b=${pre}MAP_$pane c=${pre}URLS_$pane d=${pre}TEXTS_$pane e=${pre}LROWS_$pane f=${pre}HEADS_$pane
		local -n g=${pre}BI_$pane h=${pre}BE_$pane i=${pre}BP_$pane
		TUI_MD_ANCHORS=()
	fi
	TUI_MD_ROWS=("${a[@]}") TUI_MD_MAP=("${b[@]}") TUI_MD_LINK_URLS=("${c[@]}") TUI_MD_LINK_TEXTS=("${d[@]}")
	TUI_MD_LINK_ROWS=("${e[@]}") TUI_MD_HEADS=("${f[@]}") _TUI_MD_BI=("${g[@]}") _TUI_MD_BE=("${h[@]}") _TUI_MD_BP=("${i[@]}")
}

# _tui_md.prefix_slice PANE BUDGET_US - the second phase of a viewport-first render: the blocks above the one it began at.
# Rendered on their own, then joined in front of the stored rows (row numbers shifted, anchors rebuilt in document order).
_tui_md.prefix_slice() {
	local pane=$1 k np h lvl plain first last ln soff0 l
	local -n ln_=_TUI_MD_LN_$pane rf=_TUI_MD_RF_$pane
	if [[ -n "${_TUI_MD_RS[$pane.pstarted]:-}" ]]; then
		_tui_md.unstash "_TUI_MD_PR_" "$pane"
	else
		_tui_md.reset_out
		_TUI_MD_BI=() _TUI_MD_BE=() _TUI_MD_BP=()
		_TUI_MD_RS[$pane.pstarted]=1
	fi
	_TUI_MD_LINES=("${ln_[@]}")
	_TUI_MD_REFS=()
	for k in "${!rf[@]}"; do _TUI_MD_REFS[$k]=${rf[$k]}; done
	_TUI_MD_RES_I=${_TUI_MD_RS[$pane.pi]:-0} _TUI_MD_RES_EM=${_TUI_MD_RS[$pane.pem]:-0} _TUI_MD_RES_PP=${_TUI_MD_RS[$pane.ppp]:-0}
	_TUI_MD_RES_W=${_TUI_MD_RS[$pane.w]} TUI_MD_DEGRADED=${_TUI_MD_RS[$pane.deg]} _TUI_MD_RES_DONE=0
	_TUI_MD_END_I=${_TUI_MD_RS[$pane.pre_end]}
	_tui_md.render_more "$2" 0
	_TUI_MD_END_I=0
	if ((!_TUI_MD_RES_DONE)); then
		_tui_md.stash "_TUI_MD_PR_" "$pane"
		_TUI_MD_RS[$pane.pi]=$_TUI_MD_RES_I _TUI_MD_RS[$pane.pem]=$_TUI_MD_RES_EM _TUI_MD_RS[$pane.ppp]=$_TUI_MD_RES_PP
		return 0
	fi
	# join: the prefix first, then the rows shown so far (their row numbers move down by the prefix's length)
	np=${#TUI_MD_ROWS[@]}
	local -n fb=_TUI_MD_B_$pane fm=_TUI_MD_M_$pane fu=_TUI_MD_U_$pane fx=_TUI_MD_X_$pane flr=_TUI_MD_LR_$pane fh=_TUI_MD_H_$pane
	local -n fbi=_TUI_MD_BI_$pane fbe=_TUI_MD_BE_$pane fbp=_TUI_MD_BP_$pane
	TUI_MD_ROWS+=("${fb[@]}")
	TUI_MD_MAP+=("${fm[@]}")
	TUI_MD_LINK_URLS+=("${fu[@]}")
	TUI_MD_LINK_TEXTS+=("${fx[@]}")
	for k in "${flr[@]}"; do TUI_MD_LINK_ROWS+=($((k + np))); done
	for h in "${fh[@]}"; do
		IFS='|' read -r lvl plain first last ln <<<"$h"
		TUI_MD_HEADS+=("$lvl|$plain|$((first + np))|$((last + np))|$ln")
	done
	_TUI_MD_BI+=("${fbi[@]}") _TUI_MD_BE+=("${fbe[@]}") _TUI_MD_BP+=("${fbp[@]}")
	TUI_MD_ANCHORS=()
	for h in "${TUI_MD_HEADS[@]}"; do
		IFS='|' read -r lvl plain first last ln <<<"$h"
		_tui_md.slug "$plain"
		TUI_MD_ANCHORS[$_SLUG]=$first
	done
	_tui_md.store "$pane"
	soff0=${_TUI_MD_RS[$pane.soff0]:-0}
	l=${_TUI_MD_RS[$pane.l]:-0}
	_TUI_MD_RS[$pane.pstarted]=""
	_TUI_MD_RS[$pane.phase]=fwd
	_tui_md.finish "$pane"
	_tui_md.compose "$pane"
	# the view: still where the render left it (nobody scrolled) -> the line it was on; scrolled meanwhile -> kept relative
	if ((${_TUI_P_SOFF_V[$pane]:-0} == soff0)); then
		_tui_md.scroll_to_line "$pane" "$l"
	else
		_TUI_P_SOFF_V[$pane]=$((${_TUI_P_SOFF_V[$pane]:-0} + np))
		((${_TUI_RUNNING:-0})) && _tui._queue_render "$pane"
	fi
}

# _tui_md.complete PANE - finishes the pane's render now; everything that reads the whole document (links, search, outline,
# folds, copy, scrolling to a row) calls it first.
_tui_md.complete() {
	local guard=0
	while [[ -n "${_TUI_MD_PEND[$1]+x}" ]] && ((guard++ < 8)); do _tui_md.more_pane "$1" 0; done # a viewport-first render takes two steps
	return 0
}

# _tui_md.more_timer - one time slice of the next unfinished pane; re-arms itself while any is left.
_tui_md.more_timer() {
	local pane
	for pane in "${!_TUI_MD_PEND[@]}"; do
		_tui_md.more_pane "$pane" 25000
		break
	done
	((${#_TUI_MD_PEND[@]})) && tui.after 0.02 _tui_md.more_timer md_more
	return 0
}

# _tui_md.refit - after a resize, a page switch or the first layout: re-renders the shown panes whose width changed and
# forgets those that left with their page.
_tui_md.refit() {
	local pane
	for pane in "${!_TUI_MD_SHOWN[@]}"; do
		if [[ -z "${_TUI_P_W[$pane]+x}" ]]; then
			unset '_TUI_MD_SHOWN[$pane]' '_TUI_MD_SHOWN_W[$pane]' '_TUI_MD_PEND[$pane]'
			continue
		fi
		_tui._content_rect "$pane"
		((_CR_W - 1 == ${_TUI_MD_SHOWN_W[$pane]:-0})) || _tui_md.paint_pane "$pane"
	done
	declare -F _tui_md.images_send >/dev/null && _tui_md.images_send
	return 0
}

# _tui_md.refit_soon - refit once the size has settled (the old wrapping stays on screen meanwhile).
_tui_md.refit_soon() {
	((${#_TUI_MD_SHOWN[@]})) || return 0
	tui.after 0.12 _tui_md.refit_timer md_refit
}
_tui_md.refit_timer() { _tui_md.refit; }

# tui.md.show PANE TEXT [FILE] - renders TEXT into a scrolling pane (scroll="v"); re-rendered when the pane's width changes.
# FILE is where TEXT came from: relative links resolve against its folder and "back" can return to it.
# Also what <markdown pane="PANE" src="FILE"/> does.
tui.md.show() {
	# a different document starts at the top with no focus, folds or search; the same one (a resize) keeps them
	[[ "${_TUI_MD_SHOWN[$1]-}" == "$2" && -n "${_TUI_MD_SHOWN[$1]+x}" ]] || _tui_md.reset_view "$1"
	_TUI_MD_V[$1.file]=${3:-$_TUI_MD_NEXT_FILE} # a file path when tui.md.show_file or FILE brought the text
	_TUI_MD_V[$1.disk]=$_TUI_MD_NEXT_FILE # only a text that is the file's contents may use its disk snapshot
	_TUI_MD_NEXT_FILE=""
	_TUI_MD_LAST=$1
	_TUI_MD_SHOWN[$1]=$2
	unset '_TUI_MD_SHOWN_W[$1]' '_TUI_MD_PEND[$1]'
	if ((!_TUI_MD_HOOKED)); then
		_TUI_MD_HOOKED=1
		tui.hook.on ready _tui_md.refit # the first frame and a page switch are drawn right
		tui.hook.on page _tui_md.refit
		tui.hook.on resize _tui_md.refit_soon # a drag fires this per step: wait until it pauses
		tui.hook.on layout _tui_md.refit_soon
		tui.hook.on exit _tui_md.images_clear
		tui.hook.on exit _tui_md.scratch_clean
	fi
	# a pane that is not laid out yet (page build) is painted by the ready / page hook
	[[ -n "${_TUI_P_W[$1]+x}" ]] && _tui_md.paint_pane "$1"
	return 0
}

# tui.md.forget PANE - PANE is no longer re-rendered on resize; its current content stays until replaced.
tui.md.forget() {
	unset '_TUI_MD_SHOWN[$1]' '_TUI_MD_SHOWN_W[$1]' '_TUI_MD_PEND[$1]' "_TUI_MD_V[$1.file]"
	return 0
}

# tui.md.show_file PANE FILE - tui.md.show with the contents of FILE (rc 1 when it cannot be read).
tui.md.show_file() {
	local text
	[[ -r "$2" ]] || return 1
	text=$(<"$2")
	_TUI_MD_NEXT_FILE=$2
	tui.md.show "$1" "$text"
}

# tui.md.row_for_line LINE VAR - the first rendered row of the block that holds source line LINE (0 before the first block).
tui.md.row_for_line() {
	local line=$1 r=-1 i
	for ((i = 0; i < ${#TUI_MD_MAP[@]}; i++)); do
		((TUI_MD_MAP[i] <= line)) && r=$i || break
	done
	((r < 0)) && r=0
	while ((r > 0 && TUI_MD_MAP[r - 1] == TUI_MD_MAP[r])); do ((r--)); done
	printf -v "$2" %s "$r"
}

# tui.md.line_for_row ROW VAR - the source line a rendered row came from (0 when the row does not exist).
tui.md.line_for_row() { printf -v "$2" %s "${TUI_MD_MAP[$1]:-0}"; }
