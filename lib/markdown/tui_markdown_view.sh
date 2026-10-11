#!/usr/bin/env bash
# tui_markdown_view.sh - Markdown documents in scrolling panes: links you can focus and follow, #anchors and relative .md links
# with a back stack, search with highlight, a heading outline, folding and copy. State is kept per pane (tui.md.show).
#
#   tui.md.link_next PANE | tui.md.link_prev PANE      focus the next / previous link (scrolls to it)
#   tui.md.link_open PANE                              follow the focused link: #anchor, a .md file, or copy the URL
#   tui.md.back PANE                                   back to the document / position before the last followed link
#   tui.md.on_link FN                                  FN URL TEXT PANE runs first; rc 0 = handled
#   tui.md.on_navigate FN                              FN FILE PANE runs after a followed link loaded another file
#   tui.md.search PANE TEXT                            highlight every match (case-insensitive) and jump to the first; "" clears
#   tui.md.search_next PANE | tui.md.search_prev PANE  next / previous match
#   tui.md.search_info PANE VAR                        "3/12", "no match" or "" -> VAR
#   tui.md.outline_choose PANE                         pick a heading from a list and scroll to it
#   tui.md.fold_toggle PANE [HEADING]                  fold / unfold a heading's section (default: the heading at the top)
#   tui.md.copy PANE [doc|section|rendered]           the document source, the section at the top, or the rendered text -> clipboard
# requires: tui_markdown

declare -gA _TUI_MD_V=()    # "PANE.field" -> value: file, focus, query, matches, match, folded
declare -gA _TUI_MD_HIST=() # PANE -> history entries "FILE|OFFSET" separated by newlines
declare -g TUI_MD_ON_LINK="" TUI_MD_ON_NAVIGATE="" _TUI_MD_OUTLINE_PANE=""

tui.md.on_link() { TUI_MD_ON_LINK=$1; }
tui.md.on_navigate() { TUI_MD_ON_NAVIGATE=$1; }

# _tui_md.store PANE - keeps the last render's rows, links, headings and anchors for the pane.
_tui_md.store() {
	local pane=$1 k
	declare -ga "_TUI_MD_B_$pane" "_TUI_MD_U_$pane" "_TUI_MD_X_$pane" "_TUI_MD_LR_$pane" "_TUI_MD_H_$pane" "_TUI_MD_M_$pane" "_TUI_MD_D_$pane"
	declare -gA "_TUI_MD_A_$pane"
	local -n b=_TUI_MD_B_$pane u=_TUI_MD_U_$pane x=_TUI_MD_X_$pane lr=_TUI_MD_LR_$pane h=_TUI_MD_H_$pane m=_TUI_MD_M_$pane a=_TUI_MD_A_$pane
	b=("${TUI_MD_ROWS[@]}")
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
	disp=()
	local -A marked_fold=()
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
		if [[ -n "$q" ]]; then
			_tui_md.mark_row "${base[r]}" "$q"
			shown+=("$_MARKED")
		else
			shown+=("${base[r]}")
		fi
	done
	printf -v out '%s\n' "${shown[@]}"
	tui.output "$pane" "${out%$'\n'}"
}

# _tui_md.scroll_row PANE BASEROW [top] - scrolls the pane so the row is in view (at the top with "top", else a third down).
_tui_md.scroll_row() {
	local pane=$1 d off h total max
	local -n disp=_TUI_MD_D_$pane base=_TUI_MD_B_$pane
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
	n=${#urls[@]}
	((n > 0)) || return 1
	f=${_TUI_MD_V[$pane.focus]:--1}
	if ((f < 0)); then
		((($2) > 0)) && f=0 || f=$((n - 1))
	else
		f=$(((f + $2 + n) % n))
	fi
	_TUI_MD_V[$pane.focus]=$f
	_tui_md.paint_pane "$pane"
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
	_TUI_MD_HIST[$pane]+="${_TUI_MD_V[$pane.file]:-}|${_TUI_P_SOFF_V[$pane]:-0}"$'\n'
}

# _tui_md.goto_anchor PANE SLUG - rc 1 when the document has no such heading
_tui_md.goto_anchor() {
	local pane=$1
	local -n anch=_TUI_MD_A_$pane
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
	((f >= 0 && f < ${#urls[@]})) || return 1
	_tui_md.follow "$pane" "${urls[f]}" "${texts[f]}"
}

tui.md.back() {
	local pane=$1 hist=${_TUI_MD_HIST[$1]:-} last file off
	[[ -n "$hist" ]] || return 1
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

# ── search ───────────────────────────────────────────────────────────────

tui.md.search() {
	local pane=$1 q=${2:-} r plain matches=""
	local -n base=_TUI_MD_B_$pane
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

_tui_md.search_step() { # PANE DELTA
	local -a m
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
	IFS='|' read -r lvl title first _ _ <<<"${heads[$1]}"
	_tui_md.scroll_row "$pane" "$first" top
}

tui.md.outline_choose() {
	local pane=$1 lvl title first i indent
	local -n heads=_TUI_MD_H_$pane
	local -a items=()
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
