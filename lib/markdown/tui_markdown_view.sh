#!/usr/bin/env bash
# tui_markdown_view.sh - Markdown documents in scrolling panes: links you can focus and follow, #anchors and relative .md links
# with a back stack, search with highlight, a heading outline, folding and copy. State is kept per pane (tui.md.show).
#
#   tui.md.link_next PANE | tui.md.link_prev PANE      focus the next / previous link (scrolls to it)
#   tui.md.link_open PANE                              follow the focused link: #anchor, a .md file, or copy the URL
#   tui.md.back PANE                                   back to the document / position before the last followed link
#   tui.md.forward PANE                                forward again after a back
#   tui.md.on_link FN                                  FN URL TEXT PANE runs first; rc 0 = handled
#   tui.md.on_navigate FN                              FN FILE PANE runs after a followed link loaded another file
#   tui.md.search PANE TEXT                            highlight every match (case-insensitive) and jump to the first; "" clears
#   tui.md.search_prompt PANE                          ask for the text in a prompt, then tui.md.search it
#   tui.md.search_next PANE | tui.md.search_prev PANE  next / previous match
#   tui.md.search_info PANE VAR                        "3/12", "no match" or "" -> VAR
#   tui.md.outline_choose PANE                         pick a heading from a list and scroll to it
#   tui.md.fold_toggle PANE [HEADING]                  fold / unfold a heading's section (default: the heading at the top)
#   tui.md.copy PANE [doc|section|rendered]           the document source, the section at the top, or the rendered text -> clipboard
#   tui.md.keys PANE reader|chords|none                which default keys act on PANE (<markdown keys="...">)
#   tui.md.click PANE X Y                              follow the link under the pointer (a click on the pane does this)
#   (the default key actions are _tui_md.key_* and _tui_md.key_r_*: alt chords; plain keys in reader mode)
#   tui.action.md_keys                                 a list of the keys bound to the commands above (f2, the palette)
# requires: tui_markdown

declare -gA _TUI_MD_V=()    # "PANE.field" -> value: file, focus, query, matches, match, folded
declare -gA _TUI_MD_BOUNDS=() # PANE -> row count the pane's measured width belongs to (see compose)
declare -gA _TUI_MD_DID=()  # PANE -> row count when the display map is the identity (nothing folded or marked)
declare -gA _TUI_MD_HIST=() # PANE -> history entries "FILE|OFFSET" separated by newlines
declare -gA _TUI_MD_FWD=()  # PANE -> the entries "back" stepped over, same format
declare -g TUI_MD_ON_LINK="" TUI_MD_ON_NAVIGATE="" _TUI_MD_OUTLINE_PANE="" _TUI_MD_SEARCH_PANE=""

tui.md.on_link() { TUI_MD_ON_LINK=$1; }
tui.md.on_navigate() { TUI_MD_ON_NAVIGATE=$1; }

# _tui_md.store PANE - keeps the last render's rows, links, headings and anchors for the pane.
_tui_md.store() {
	local pane=$1 k
	declare -ga "_TUI_MD_B_$pane" "_TUI_MD_U_$pane" "_TUI_MD_X_$pane" "_TUI_MD_LR_$pane" "_TUI_MD_H_$pane" "_TUI_MD_M_$pane" "_TUI_MD_D_$pane"
	declare -ga "_TUI_MD_BI_$pane" "_TUI_MD_BE_$pane" "_TUI_MD_BP_$pane"
	declare -gA "_TUI_MD_A_$pane"
	local -n b=_TUI_MD_B_$pane u=_TUI_MD_U_$pane x=_TUI_MD_X_$pane lr=_TUI_MD_LR_$pane h=_TUI_MD_H_$pane m=_TUI_MD_M_$pane a=_TUI_MD_A_$pane
	local -n bi=_TUI_MD_BI_$pane be=_TUI_MD_BE_$pane bp=_TUI_MD_BP_$pane
	bi=("${_TUI_MD_BI[@]}") be=("${_TUI_MD_BE[@]}") bp=("${_TUI_MD_BP[@]}")
	b=("${TUI_MD_ROWS[@]}")
	unset '_TUI_MD_BOUNDS[$pane]'
	u=("${TUI_MD_LINK_URLS[@]}")
	x=("${TUI_MD_LINK_TEXTS[@]}")
	lr=("${TUI_MD_LINK_ROWS[@]}")
	h=("${TUI_MD_HEADS[@]}")
	m=("${TUI_MD_MAP[@]}")
	a=()
	for k in "${!TUI_MD_ANCHORS[@]}"; do a[$k]=${TUI_MD_ANCHORS[$k]}; done
}

# _tui_md.mark_row ROW QUERY -> _MARKED - ROW with every occurrence of QUERY (case-insensitive, plain text) in reverse video.
_tui_md.mark_row() {
	local row=$1 q=${2,,} plain pl out="" i=0 p=0 len in=0 seq rest off=0 pre si=0 nextstart endpos=-1 ql=${#2}
	local -a starts=()
	tui.md.strip "$row" plain
	pl=${plain,,}
	if [[ -z "$q" || "$pl" != *"$q"* ]]; then
		_MARKED=$row
		return 0
	fi
	rest=$pl
	while [[ "$rest" == *"$q"* ]]; do
		pre=${rest%%"$q"*}
		starts+=($((off + ${#pre})))
		off=$((off + ${#pre} + ql))
		rest=${rest#*"$q"}
	done
	nextstart=${starts[0]}
	len=${#row}
	while ((i < len)); do
		if [[ "${row:i:2}" == $'\e[' ]]; then
			seq=${row:i}
			seq=${seq%%m*}m
			out+=$seq
			((i += ${#seq}))
			((in)) && [[ "$seq" == $'\e[0m' ]] && out+=$'\e[7m'
			continue
		fi
		if ((!in && p == nextstart)); then
			out+=$'\e[7m'
			in=1
			endpos=$((p + ql))
			((si++))
			nextstart=${starts[si]:--1}
		fi
		out+=${row:i:1}
		((i++, p++))
		if ((in && p == endpos)); then
			out+=$'\e[27m'
			in=0
		fi
	done
	((in)) && out+=$'\e[27m'
	_MARKED=$out
}

# _tui_md.compose PANE - base rows -> displayed rows (folds applied, matches marked) -> the pane.
_tui_md.compose() {
	_tui_perf.begin md_compose
	local pane=$1 k r e lvl title first last ln folded=" ${_TUI_MD_V[$pane.folded]:-} " q=${_TUI_MD_V[$pane.query]:-} out text
	local -n base=_TUI_MD_B_$pane heads=_TUI_MD_H_$pane disp=_TUI_MD_D_$pane
	local -A hide=() cnt=()
	local total=${#base[@]} lvl2 f2
	for k in "${!heads[@]}"; do
		[[ "$folded" == *" $k "* ]] || continue
		IFS='|' read -r lvl title first last ln <<<"${heads[k]}"
		e=$((total - 1))
		for ((r = k + 1; r < ${#heads[@]}; r++)); do
			IFS='|' read -r lvl2 title f2 _ _ <<<"${heads[r]}"
			if ((lvl2 <= lvl)); then
				e=$((f2 - 1))
				break
			fi
		done
		for ((r = last + 1; r <= e; r++)); do hide[$r]=$k; done
		cnt[$k]=$((e - last))
	done
	local -a shown=()
	local -A marked_fold=()
	local -A fover=()
	_tui_md.focus_rows "$pane" fover
	if ((${#hide[@]} == 0)) && [[ -z "$q" ]]; then
		# nothing folded or marked: the displayed rows are the base rows (and the identity map is kept between calls)
		shown=("${base[@]}")
		for r in "${!fover[@]}"; do shown[r]=${fover[$r]}; done
		if [[ "${_TUI_MD_DID[$pane]:-}" != "$total" ]]; then
			disp=()
			for ((r = 0; r < total; r++)); do disp[r]=$r; done
			_TUI_MD_DID[$pane]=$total
		fi
		# the rows are the stored ones with a style swapped: their widest is what it was
		local keep=0
		[[ "${_TUI_MD_BOUNDS[$pane]:-}" == "$total" ]] && keep=1
		_tui.output_rows "$pane" shown "$keep"
		_TUI_MD_BOUNDS[$pane]=$total
		_tui_perf.end md_compose
		return 0
	fi
	unset '_TUI_MD_DID[$pane]' '_TUI_MD_BOUNDS[$pane]'
	disp=()
	for ((r = 0; r < total; r++)); do
		if [[ -n "${hide[$r]+x}" ]]; then
			k=${hide[$r]}
			if [[ -z "${marked_fold[$k]+x}" ]]; then
				marked_fold[$k]=1
				shown+=("${_TUI_MD_SGR[marker]}  ▸ ${cnt[$k]} rows folded${_TUI_MD_RESET}")
			fi
			disp[r]=$((${#shown[@]} - 1))
			continue
		fi
		disp[r]=${#shown[@]}
		text=${fover[$r]:-${base[r]}}
		if [[ -n "$q" ]]; then
			_tui_md.mark_row "$text" "$q"
			shown+=("$_MARKED")
		else
			shown+=("$text")
		fi
	done
	_tui.output_rows "$pane" shown
	_tui_perf.end md_compose
}

# _tui_md.scroll_row PANE BASEROW [top] - scrolls the pane so the row is in view (at the top with "top", else a third down).
_tui_md.scroll_row() {
	local pane=$1 d off h total max
	local -n disp=_TUI_MD_D_$pane base=_TUI_MD_B_$pane
	_tui_md.complete "$pane"
	d=${disp[$2]:-0}
	_tui._content_rect "$pane"
	h=$_CR_H
	total=$((${#disp[@]} > 0 ? ${disp[-1]} + 1 : 0))
	off=${_TUI_P_SOFF_V[$pane]:-0}
	if [[ "${3:-}" == top ]]; then
		off=$d
	elif ((d < off || d >= off + h)); then
		off=$((d - h / 3))
	fi
	max=$((total - h))
	((max < 0)) && max=0
	((off > max)) && off=$max
	((off < 0)) && off=0
	_TUI_P_SOFF_V[$pane]=$off
	((${_TUI_RUNNING:-0})) && _tui._queue_render "$pane"
	return 0
}

# _tui_md.reset_view PANE - a different document: no focus, folds or search, scrolled to the top.
_tui_md.reset_view() {
	local pane=$1
	_TUI_MD_V[$pane.focus]=-1
	_TUI_MD_V[$pane.query]=""
	_TUI_MD_V[$pane.matches]=""
	_TUI_MD_V[$pane.match]=0
	_TUI_MD_V[$pane.folded]=""
	tui.scroll.reset "$pane"
}

# ── links ────────────────────────────────────────────────────────────────

_tui_md.link_step() { # PANE DELTA
	local pane=$1 n f
	local -n urls=_TUI_MD_U_$pane lr=_TUI_MD_LR_$pane
	_tui_md.complete "$pane"
	n=${#urls[@]}
	((n > 0)) || return 1
	f=${_TUI_MD_V[$pane.focus]:--1}
	if ((f < 0)); then
		((($2) > 0)) && f=0 || f=$((n - 1))
	else
		f=$(((f + $2 + n) % n))
	fi
	_TUI_MD_V[$pane.focus]=$f
	_tui_md.compose "$pane"
	_tui_md.scroll_row "$pane" "${lr[f]:-0}"
}
tui.md.link_next() { _tui_md.link_step "$1" 1; }
tui.md.link_prev() { _tui_md.link_step "$1" -1; }

# _tui_md.normpath PATH -> _NP - PATH without "." and ".." segments
_tui_md.normpath() {
	local seg
	local -a parts=() out=()
	IFS='/' read -ra parts <<<"$1"
	for seg in "${parts[@]}"; do
		case "$seg" in
			"" | .) ;;
			..) ((${#out[@]})) && unset 'out[-1]' ;;
			*) out+=("$seg") ;;
		esac
	done
	local IFS=/
	_NP="/${out[*]}"
}

_tui_md.push_hist() { # PANE
	local pane=$1
	_TUI_MD_FWD[$pane]="" # a new trail: what "back" came from is gone
	_TUI_MD_HIST[$pane]+="${_TUI_MD_V[$pane.file]:-}|${_TUI_P_SOFF_V[$pane]:-0}"$'\n'
}

# _tui_md.goto_anchor PANE SLUG - rc 1 when the document has no such heading
_tui_md.goto_anchor() {
	local pane=$1
	local -n anch=_TUI_MD_A_$pane
	_tui_md.complete "$pane"
	[[ -n "${anch[$2]+x}" ]] || return 1
	_tui_md.scroll_row "$pane" "${anch[$2]}" top
}

_tui_md.follow() { # PANE URL TEXT
	local pane=$1 url=$2 text=$3 target frag="" cur path
	if [[ -n "$TUI_MD_ON_LINK" ]] && "$TUI_MD_ON_LINK" "$url" "$text" "$pane"; then return 0; fi
	case "$url" in
		\#*)
			_tui_md.push_hist "$pane"
			_tui_md.goto_anchor "$pane" "${url#\#}" || tui.notify "No heading '${url#\#}' in this document" warn 3
			return 0
			;;
		"" | *://* | mailto:*) ;;
		*)
			target=${url%%#*}
			[[ "$url" == *#* ]] && frag=${url#*#}
			cur=${_TUI_MD_V[$pane.file]:-}
			if [[ -n "$cur" && "$target" == *.md ]]; then
				if [[ "$target" == /* ]]; then path=$target; else path="${cur%/*}/$target"; fi
				_tui_md.normpath "$path"
				if [[ -f "$_NP" ]]; then
					_tui_md.push_hist "$pane"
					tui.md.show_file "$pane" "$_NP"
					[[ -n "$frag" ]] && _tui_md.goto_anchor "$pane" "$frag"
					[[ -n "$TUI_MD_ON_NAVIGATE" ]] && "$TUI_MD_ON_NAVIGATE" "$_NP" "$pane"
					return 0
				fi
			fi
			;;
	esac
	# nothing to open inside the terminal: hand the target to the clipboard
	tui.clipboard.copy "$url"
	tui.notify "Link copied: $url" info 3
}

tui.md.link_open() {
	local pane=$1 f=${_TUI_MD_V[$1.focus]:--1}
	local -n urls=_TUI_MD_U_$pane texts=_TUI_MD_X_$pane
	_tui_md.complete "$pane"
	((f >= 0 && f < ${#urls[@]})) || return 1
	_tui_md.follow "$pane" "${urls[f]}" "${texts[f]}"
}

tui.md.back() {
	local pane=$1 hist=${_TUI_MD_HIST[$1]:-} last file off
	[[ -n "$hist" ]] || return 1
	_TUI_MD_FWD[$pane]+="${_TUI_MD_V[$pane.file]:-}|${_TUI_P_SOFF_V[$pane]:-0}"$'\n'
	hist=${hist%$'\n'}
	last=${hist##*$'\n'}
	[[ "$hist" == *$'\n'* ]] && _TUI_MD_HIST[$pane]="${hist%$'\n'*}"$'\n' || _TUI_MD_HIST[$pane]=""
	file=${last%|*}
	off=${last##*|}
	if [[ -n "$file" && "$file" != "${_TUI_MD_V[$pane.file]:-}" ]]; then
		tui.md.show_file "$pane" "$file"
		[[ -n "$TUI_MD_ON_NAVIGATE" ]] && "$TUI_MD_ON_NAVIGATE" "$file" "$pane"
	fi
	_TUI_P_SOFF_V[$pane]=$off
	((${_TUI_RUNNING:-0})) && _tui._queue_render "$pane"
	return 0
}

# tui.md.forward PANE - goes forward again after tui.md.back; rc 1 when there is nothing to go forward to.
tui.md.forward() {
	local pane=$1 fwd=${_TUI_MD_FWD[$1]:-} last file off
	[[ -n "$fwd" ]] || return 1
	fwd=${fwd%$'\n'}
	last=${fwd##*$'\n'}
	[[ "$fwd" == *$'\n'* ]] && _TUI_MD_FWD[$pane]="${fwd%$'\n'*}"$'\n' || _TUI_MD_FWD[$pane]=""
	_TUI_MD_HIST[$pane]+="${_TUI_MD_V[$pane.file]:-}|${_TUI_P_SOFF_V[$pane]:-0}"$'\n'
	file=${last%|*}
	off=${last##*|}
	if [[ -n "$file" && "$file" != "${_TUI_MD_V[$pane.file]:-}" ]]; then
		tui.md.show_file "$pane" "$file"
		[[ -n "$TUI_MD_ON_NAVIGATE" ]] && "$TUI_MD_ON_NAVIGATE" "$file" "$pane"
	fi
	_TUI_P_SOFF_V[$pane]=$off
	((${_TUI_RUNNING:-0})) && _tui._queue_render "$pane"
	return 0
}

# ── search ───────────────────────────────────────────────────────────────

tui.md.search() {
	local pane=$1 q=${2:-} r plain matches=""
	local -n base=_TUI_MD_B_$pane
	_tui_md.complete "$pane"
	_TUI_MD_V[$pane.query]=$q
	_TUI_MD_V[$pane.match]=0
	if [[ -n "$q" ]]; then
		for r in "${!base[@]}"; do
			tui.md.strip "${base[r]}" plain
			[[ "${plain,,}" == *"${q,,}"* ]] && matches+="$r "
		done
	fi
	_TUI_MD_V[$pane.matches]=$matches
	_tui_md.compose "$pane"
	if [[ -n "$matches" ]]; then
		_tui_md.scroll_row "$pane" "${matches%% *}"
	fi
	[[ -z "$q" || -n "$matches" ]]
}

# tui.md.search_prompt PANE - asks for the text, then searches it ("" clears); tells which match is shown.
tui.md.search_prompt() {
	_TUI_MD_SEARCH_PANE=$1
	tui.prompt "Search this document (empty clears)" _tui_md.search_submit --title "Search"
}

_tui_md.search_submit() { # TEXT
	local pane=$_TUI_MD_SEARCH_PANE info
	tui.md.search "$pane" "$1" || tui.notify "No match for '$1'" warn 2
	tui.md.search_info "$pane" info
	[[ -n "$info" ]] && tui.notify "Match $info" info 3
	return 0
}

_tui_md.search_step() { # PANE DELTA
	local -a m
	_tui_md.complete "$1"
	read -ra m <<<"${_TUI_MD_V[$1.matches]:-}"
	((${#m[@]})) || return 1
	local i=$((${_TUI_MD_V[$1.match]:-0} + $2))
	i=$(((i % ${#m[@]} + ${#m[@]}) % ${#m[@]}))
	_TUI_MD_V[$1.match]=$i
	_tui_md.scroll_row "$1" "${m[i]}"
}
tui.md.search_next() { _tui_md.search_step "$1" 1; }
tui.md.search_prev() { _tui_md.search_step "$1" -1; }

tui.md.search_info() {
	local -a m
	read -ra m <<<"${_TUI_MD_V[$1.matches]:-}"
	if [[ -z "${_TUI_MD_V[$1.query]:-}" ]]; then printf -v "$2" %s ""
	elif ((${#m[@]} == 0)); then printf -v "$2" %s "no match"
	else printf -v "$2" '%d/%d' $((${_TUI_MD_V[$1.match]:-0} + 1)) "${#m[@]}"; fi
}

# ── outline, fold, copy ──────────────────────────────────────────────────

_tui_md.outline_picked() { # INDEX ITEM
	local pane=$_TUI_MD_OUTLINE_PANE
	local -n heads=_TUI_MD_H_$pane
	local lvl title first
	_tui_md.complete "$pane"
	IFS='|' read -r lvl title first _ _ <<<"${heads[$1]}"
	_tui_md.scroll_row "$pane" "$first" top
}

tui.md.outline_choose() {
	local pane=$1 lvl title first i indent
	local -n heads=_TUI_MD_H_$pane
	local -a items=()
	_tui_md.complete "$pane"
	((${#heads[@]})) || return 1
	for i in "${!heads[@]}"; do
		IFS='|' read -r lvl title first _ _ <<<"${heads[i]}"
		printf -v indent '%*s' $(((lvl - 1) * 2)) ''
		items+=("${indent}${title}")
	done
	_TUI_MD_OUTLINE_PANE=$pane
	tui.choose "Outline" _tui_md.outline_picked "${items[@]}"
}

# _tui_md.head_at_top PANE -> _HI - index of the last heading at or above the top of the view (-1 none)
_tui_md.head_at_top() {
	local pane=$1 off=${_TUI_P_SOFF_V[$1]:-0} k first r=0
	local -n heads=_TUI_MD_H_$pane disp=_TUI_MD_D_$pane
	_tui_md.complete "$pane"
	_HI=-1
	for k in "${!heads[@]}"; do
		IFS='|' read -r _ _ first _ _ <<<"${heads[k]}"
		((${disp[$first]:-0} <= off)) && _HI=$k
	done
}

tui.md.fold_toggle() {
	local pane=$1 k=${2:-} folded
	[[ -n "$k" ]] || {
		_tui_md.head_at_top "$pane"
		k=$_HI
	}
	((k >= 0)) || return 1
	folded=" ${_TUI_MD_V[$pane.folded]:-} "
	if [[ "$folded" == *" $k "* ]]; then folded=${folded/" $k "/ }; else folded+="$k "; fi
	folded=${folded# }
	_TUI_MD_V[$pane.folded]=${folded% }
	_tui_md.compose "$pane"
}

tui.md.copy() {
	local pane=$1 what=${2:-section} text="" k lvl first last ln lvl2 ln2 r label
	local -n heads=_TUI_MD_H_$pane base=_TUI_MD_B_$pane
	local src=${_TUI_MD_SHOWN[$pane]:-}
	_tui_md.complete "$pane"
	case "$what" in
		doc)
			text=$src
			label="document"
			;;
		rendered)
			for r in "${!base[@]}"; do
				tui.md.strip "${base[r]}" lvl
				text+=$lvl$'\n'
			done
			label="rendered text"
			;;
		section)
			local -a lines
			mapfile -t lines <<<"$src"
			_tui_md.head_at_top "$pane"
			if ((_HI < 0)); then
				text=$src
			else
				IFS='|' read -r lvl _ first last ln <<<"${heads[_HI]}"
				local endln=${#lines[@]}
				for ((k = _HI + 1; k < ${#heads[@]}; k++)); do
					IFS='|' read -r lvl2 _ _ _ ln2 <<<"${heads[k]}"
					if ((lvl2 <= lvl)); then
						endln=$((ln2 - 1))
						break
					fi
				done
				printf -v text '%s\n' "${lines[@]:ln-1:endln-ln+1}"
			fi
			label="section"
			;;
		*) return 1 ;;
	esac
	tui.clipboard.copy "$text"
	tui.notify "Copied the $label" info 2
}

# ── keys: which pane a Markdown key acts on ───────────────────────────────

declare -gA _TUI_MD_KEYMODE=() # PANE -> reader | chords | none (default chords)

# tui.md.keys PANE reader|chords|none - which default keys act on PANE: "reader" adds plain keys (j k n N enter ...) while the
# pane has the keyboard, "chords" (the default) only the alt chords, "none" nothing. rc 1 for another mode.
tui.md.keys() {
	case "${2:-}" in
		reader | chords | none) _TUI_MD_KEYMODE[$1]=$2 ;;
		*) return 1 ;;
	esac
}

# _tui_md.key_target [reader] -> _MT - the pane a Markdown key acts on; rc 1 when there is none. A key resolves, in order, to
# the keyboard pane, the pane under the pointer, the pane of the focused widget, then the only (or the last shown) Markdown
# pane. With "reader" only the keyboard pane qualifies and it must be in reader mode, so plain keys never act on a pane
# the user is not in.
_tui_md.key_target() {
	local c mode n=0 only=""
	_MT=""
	if [[ "${1:-}" == reader ]]; then
		c=$_TUI_PANE_FOCUS
		[[ -n "$c" && -n "${_TUI_MD_SHOWN[$c]+x}" && "${_TUI_MD_KEYMODE[$c]:-chords}" == reader ]] || return 1
		_MT=$c
		return 0
	fi
	local wp=""
	[[ -n "${_TUI_FOCUS_ID:-}" ]] && wp=${_TUI_W_PANE[$_TUI_FOCUS_ID]:-}
	for c in "$_TUI_PANE_FOCUS" "${_TUI_HOVERED_PANE:-}" "$wp"; do
		[[ "${TUI_EVENT_TYPE:-}" == mouse && "$c" == "$_TUI_PANE_FOCUS" && -n "${TUI_EVENT_PANE:-}" ]] && c=$TUI_EVENT_PANE
		[[ -n "$c" && -n "${_TUI_MD_SHOWN[$c]+x}" && "${_TUI_MD_KEYMODE[$c]:-chords}" != none ]] || continue
		_MT=$c
		return 0
	done
	for c in "${!_TUI_MD_SHOWN[@]}"; do
		[[ "${_TUI_MD_KEYMODE[$c]:-chords}" == none ]] && continue
		((n++))
		only=$c
	done
	if ((n == 1)); then _MT=$only; return 0; fi
	if ((n > 1)) && [[ -n "$_TUI_MD_LAST" && -n "${_TUI_MD_SHOWN[$_TUI_MD_LAST]+x}" ]]; then
		_MT=$_TUI_MD_LAST
		return 0
	fi
	return 1
}

# _tui_md.act MODE FN [ARG...] - runs FN PANE ARG... on the pane the key resolves to; rc 1 when it resolves to none, which
# lets a plain key reach a focused widget.
_tui_md.act() {
	local mode=$1 fn=$2
	shift 2
	_tui_md.key_target "$mode" || return 1
	"$fn" "$_MT" "$@"
}

_tui_md.key_link_next() { _tui_md.act any tui.md.link_next; }
_tui_md.key_link_prev() { _tui_md.act any tui.md.link_prev; }
_tui_md.key_link_open() { _tui_md.act any tui.md.link_open; }
_tui_md.key_back() { _tui_md.act any tui.md.back; }
_tui_md.key_forward() { _tui_md.act any tui.md.forward; }

# _tui_md.key_hist left|right - alt+left / alt+right: back / forward in the Markdown pane that has the keyboard. rc 1 when
# the keys are not for a document (another pane, keys="none", the markdown group off): the pane keys then run.
_tui_md.key_hist() {
	local p=$_TUI_PANE_FOCUS
	[[ -z "${_TUI_DEF_OFF[markdown]:-}" ]] || return 1
	[[ -n "$p" && -n "${_TUI_MD_SHOWN[$p]+x}" && "${_TUI_MD_KEYMODE[$p]:-chords}" != none ]] || return 1
	case "$1" in
		left) tui.md.back "$p" ;;
		right) tui.md.forward "$p" ;;
	esac
	return 0 # also at either end of the history: the key was meant for the document
}
_tui_md.key_search() { _tui_md.act any tui.md.search_prompt; }
_tui_md.key_search_next() { _tui_md.act any tui.md.search_next; }
_tui_md.key_search_prev() { _tui_md.act any tui.md.search_prev; }
_tui_md.key_outline() { _tui_md.act any tui.md.outline_choose; }
_tui_md.key_fold() { _tui_md.act any tui.md.fold_toggle; }
_tui_md.key_copy_section() { _tui_md.act any tui.md.copy section; }
_tui_md.key_copy_doc() { _tui_md.act any tui.md.copy doc; }
# the reader keys: plain keys that act only while the pane has the keyboard and is in reader mode
_tui_md.key_r_link_next() { _tui_md.act reader tui.md.link_next; }
_tui_md.key_r_link_prev() { _tui_md.act reader tui.md.link_prev; }
_tui_md.key_r_link_open() { _tui_md.act reader tui.md.link_open; }
_tui_md.key_r_back() { _tui_md.act reader tui.md.back; }
_tui_md.key_r_search() { _tui_md.act reader tui.md.search_prompt; }
_tui_md.key_r_search_next() { _tui_md.act reader tui.md.search_next; }
_tui_md.key_r_search_prev() { _tui_md.act reader tui.md.search_prev; }
_tui_md.key_r_outline() { _tui_md.act reader tui.md.outline_choose; }
_tui_md.key_r_fold() { _tui_md.act reader tui.md.fold_toggle; }
_tui_md.key_r_copy_section() { _tui_md.act reader tui.md.copy section; }
_tui_md.key_r_copy_doc() { _tui_md.act reader tui.md.copy doc; }
_tui_md.key_r_top() { _tui_md.act reader _tui_md.scroll_by -999999; }
_tui_md.key_r_bottom() { _tui_md.act reader _tui_md.scroll_by 999999; }

# _tui_md.scroll_by PANE N - scrolls the pane N lines (clamped by the scroll code).
_tui_md.scroll_by() {
	_SC_OLD="${_TUI_P_SOFF_V[$1]:-0}"
	((_TUI_P_SOFF_V[$1] = _SC_OLD + $2 < 0 ? 0 : _SC_OLD + $2))
	_tui_scroll.apply "$1"
}

# tui.md.click PANE X Y - a click on the pane's content: follows the link under the pointer. rc 1 when there is none (the
# caller then treats it as a click on the pane).
tui.md.click() {
	local pane=$1 mx=$2 my=$3 r col row disp=-1 k idx
	[[ -n "${_TUI_MD_SHOWN[$pane]+x}" ]] || return 1
	_tui_md.complete "$pane"
	local -n d=_TUI_MD_D_$pane
	_tui._content_rect "$pane"
	row=$((my - _CR_R + ${_TUI_P_SOFF_V[$pane]:-0}))
	col=$((mx - _CR_C + ${_TUI_P_SOFF_H[$pane]:-0}))
	((row >= 0 && col >= 0)) || return 1
	for k in "${!d[@]}"; do
		((d[k] == row)) && {
			r=$k
			disp=1
			break
		}
	done
	((disp == 1)) || return 1
	_tui_md.link_at "$pane" "$r" "$col" || return 1
	idx=$_LI
	_TUI_MD_V[$pane.focus]=$idx
	tui.pane.focus "$pane"
	tui.md.link_open "$pane"
}

# _tui_md.row_spans PANE ROW -> _RSP - the links drawn in base row ROW: "START:END:INDEX" per run in the link style (cells,
# END exclusive), left to right. A link is a run in the link style; a row that starts inside one continues the link of the
# row above (a link that wraps). Two touching links in one style count as one run.
_tui_md.row_spans() {
	local pane=$1 r=$2 row t act="" ch cp w cnt=0 inl prev=0 start=0 first=-1 k n=0 cont i
	local -n base=_TUI_MD_B_$pane lr=_TUI_MD_LR_$pane
	local ls=${_TUI_MD_SGR[link]} lf=${_TUI_MD_SGR[link_focus]:-} seq
	local -a runs=()
	_RSP=()
	[[ -n "$ls" ]] || return 1
	row=${base[r]:-}
	[[ "$row" == *"$ls"* || (-n "$lf" && "$row" == *"$lf"*) ]] || return 1
	t=$row
	while [[ -n "$t" ]]; do
		if [[ "${t:0:2}" == $'\e[' ]]; then
			seq=${t%%m*}m
			t=${t:${#seq}}
			_tui_md.track "$seq"
			continue
		fi
		ch=${t:0:1}
		w=1
		if [[ "$ch" != [\ -~] ]]; then
			printf -v cp '%d' "'$ch"
			_tui_md.charw "$cp"
			w=$_CW
		fi
		t=${t:1}
		((w == 0)) && continue
		inl=0
		[[ "$act" == *"$ls"* || (-n "$lf" && "$act" == *"$lf"*) ]] && inl=1
		if ((inl && !prev)); then
			start=$cnt
		elif ((!inl && prev)); then
			runs+=("$start:$cnt")
		fi
		prev=$inl
		((cnt += w))
	done
	((prev)) && runs+=("$start:$cnt")
	((${#runs[@]})) || return 1
	for k in "${!lr[@]}"; do
		((lr[k] == r)) && {
			((first < 0)) && first=$k
			((n++))
		}
	done
	if ((first < 0)); then # no link starts here: the row continues the last link of an earlier row
		for k in "${!lr[@]}"; do ((lr[k] < r)) && first=$((k + 1)); done
		((first > 0)) || return 1
	fi
	cont=$((${#runs[@]} - n)) # 1 when the row starts inside a link of the row above
	((cont < 0)) && cont=0
	for i in "${!runs[@]}"; do
		k=$((first - cont + i))
		((k >= 0 && k < ${#lr[@]})) && _RSP+=("${runs[i]}:$k")
	done
	((${#_RSP[@]}))
}

# _tui_md.link_at PANE BASEROW COL -> _LI - index of the link drawn under cell COL of base row BASEROW (rc 1: none).
_tui_md.link_at() {
	local span s e idx
	_tui_md.row_spans "$1" "$2" || return 1
	for span in "${_RSP[@]}"; do
		IFS=: read -r s e idx <<<"$span"
		if (($3 >= s && $3 < e)); then
			_LI=$idx
			return 0
		fi
	done
	return 1
}

# _tui_md.focus_rows PANE ARRAY - ARRAY[row] = the base row with the focused link drawn in the focus style. The rows hold
# the plain link style whatever the focus (they are cached that way); only the rows of the focused link are rewritten.
_tui_md.focus_rows() {
	local pane=$1 f=${_TUI_MD_V[$1.focus]:--1} r s e idx span head tail mid rest act="" n=0
	local -n out=$2 base=_TUI_MD_B_$pane lr=_TUI_MD_LR_$pane
	local ls=${_TUI_MD_SGR[link]} lf=${_TUI_MD_SGR[link_focus]:-}
	((f >= 0 && f < ${#lr[@]})) && [[ -n "$lf" && "$lf" != "$ls" ]] || return 0
	_tui_md.complete "$pane"
	r=${lr[f]}
	while ((n++ < 40 && r < ${#base[@]})); do
		_tui_md.row_spans "$pane" "$r" || break
		local hit=0
		for span in "${_RSP[@]}"; do
			IFS=: read -r s e idx <<<"$span"
			((idx == f)) || continue
			hit=1
			act=""
			_tui_md.cut "${base[r]}" "$s"
			head=$_CH tail=$_CT
			_tui_md.cut "$tail" $((e - s))
			mid=$_CH rest=$_CT
			out[$r]="$head${mid//"$ls"/"$lf"}$rest"
			break
		done
		((hit)) || break
		((r++))
	done
}


# ── help ─────────────────────────────────────────────────────────────────

# the commands the help lists: "ACTION|what it does"; the keys come from the bindings (defaults and the app's own)
declare -ga TUI_MD_COMMANDS=(
	"link_next|Next link"
	"link_prev|Previous link"
	"link_open|Follow the focused link (a click follows the link under the pointer)"
	"back|Back to the previous document or position (also alt+left, side mouse button)"
	"forward|Forward again after a back (also alt+right, side mouse button)"
	"search|Search the document"
	"search_next|Next match"
	"search_prev|Previous match"
	"outline|Heading outline: jump to a heading"
	"fold|Fold or unfold the section at the top"
	"copy_section|Copy the section at the top (source)"
	"copy_doc|Copy the whole document (source)"
)

# _tui_md.help_name COMMAND -> _HN - the command row an action or an app's own tui.md.* binding belongs to ("" none).
_tui_md.help_name() {
	_HN=""
	case "$1" in
		_tui_md.key_r_*) _HN=${1#_tui_md.key_r_} ;;
		_tui_md.key_*) _HN=${1#_tui_md.key_} ;;
		"tui.md.copy "*) [[ "$1" == *" doc" ]] && _HN=copy_doc || _HN=copy_section ;;
		tui.md.link_open*) _HN=link_open ;;
		tui.md.outline_choose*) _HN=outline ;;
		tui.md.fold_toggle*) _HN=fold ;;
		tui.md.search_prompt*) _HN=search ;;
		tui.md.*) _HN=${1#tui.md.} _HN=${_HN%% *} ;;
	esac
}

# tui.action.md_keys - a scrollable list of the Markdown reading commands with the keys bound to them right now: the
# defaults (alt chords, and plain keys in a pane set to reader mode) and the app's own binds. "-" = no key.
tui.action.md_keys() {
	local id cmd key row what text="" name
	local -A keys=()
	for key in "${!_TUI_BIND_DEF[@]}"; do
		_tui_input.default_active "$key" || continue
		_tui_md.help_name "${_TUI_BIND_DEF[$key]}"
		[[ -n "$_HN" ]] && keys[$_HN]+="${keys[$_HN]:+  }$key"
	done
	for id in "${!_TUI_BIND[@]}"; do
		_tui_md.help_name "${_TUI_BIND[$id]}"
		[[ -n "$_HN" ]] && keys[$_HN]+="${keys[$_HN]:+  }${id#*|}"
	done
	for row in "${TUI_MD_COMMANDS[@]}"; do
		name=${row%%|*} what=${row#*|}
		printf -v row '  %-30s %s' "${keys[$name]:--}" "$what"
		text+="$row"$'\n'
	done
	text+=$'\n'"Plain keys (n N enter b / ] [ o z y Y g G) act on a pane set to reader mode while it has the keyboard:"
	text+=$'\n'"click it or press f6.   <markdown keys=\"reader\"/> or tui.md.keys PANE reader."
	tui.view "Markdown reading keys" "$text"
}
