#!/usr/bin/env bash
# tui_markdown_table.sh - pipe tables: header row, a |---|:-:|--:| delimiter row, body rows. Columns take their natural width and
# shrink (widest first, cells wrap) to fit; when even the minimum does not fit the rows are stacked as "Header: value" lines.
# requires: tui_markdown

_TUI_MD_RE_TBLDELIM='^[[:space:]]*\|?[[:space:]]*:?-+:?[[:space:]]*(\|[[:space:]]*:?-+:?[[:space:]]*)*\|?[[:space:]]*$'
declare -ga _TB_CELLS=() _TB_ALIGN=()
declare -g _TB_COLS=0

# _tui_md.split_row LINE -> _TB_CELLS - the trimmed cells of a pipe row ("\|" is a literal bar)
_tui_md.split_row() {
	local s=$1 cell="" c i
	_TB_CELLS=()
	s=${s#"${s%%[![:space:]]*}"}
	s=${s%"${s##*[![:space:]]}"}
	[[ "$s" == \|* ]] && s=${s:1}
	[[ "$s" == *\| && "$s" != *'\|' ]] && s=${s%\|}
	if [[ "$s" != *'\'* ]]; then
		IFS='|' read -ra _TB_CELLS <<<"$s"
	else
		for ((i = 0; i < ${#s}; i++)); do
			c=${s:i:1}
			if [[ "$c" == '\' && "${s:i+1:1}" == '|' ]]; then
				cell+='|'
				((i++))
				continue
			fi
			if [[ "$c" == '|' ]]; then
				_TB_CELLS+=("$cell")
				cell=""
				continue
			fi
			cell+=$c
		done
		_TB_CELLS+=("$cell")
	fi
	for i in "${!_TB_CELLS[@]}"; do
		c=${_TB_CELLS[i]}
		c=${c#"${c%%[![:space:]]*}"}
		_TB_CELLS[i]=${c%"${c##*[![:space:]]}"}
	done
}

# _tui_md.table_at - in _tui_md.blocks: rc 0 when line i is a table header followed by a matching delimiter row.
_tui_md.table_at() {
	local d
	((i + 1 < n)) || return 1
	d=${L[i + 1]#*:}
	[[ "$d" == *-* && "$d" =~ $_TUI_MD_RE_TBLDELIM ]] || return 1
	_tui_md.split_row "$d"
	_TB_ALIGN=()
	local c a
	for c in "${_TB_CELLS[@]}"; do
		a=l
		[[ "$c" == :*: ]] && a=c
		[[ "$c" != :* && "$c" == *: ]] && a=r
		_TB_ALIGN+=("$a")
	done
	_TB_COLS=${#_TB_CELLS[@]}
	_tui_md.split_row "${L[i]#*:}"
	((${#_TB_CELLS[@]} == _TB_COLS))
}

# _tui_md.table_cell RENDERED WIDTH NATURAL -> _TB_LINES - one rendered cell as lines of at most WIDTH cells.
_tui_md.table_cell() {
	local -a TUI_MD_ROWS=() TUI_MD_MAP=() # the wrapper's output goes here, not into the document
	local k l0=${#TUI_MD_LINK_ROWS[@]}
	if (($3 <= $2)) && [[ "$1" != *$'\x02'* ]]; then
		_TB_LINES=("$1")
		return 0
	fi
	if (($3 > $2)) && [[ "$TUI_MD_TABLE_OVERFLOW" == truncate ]]; then
		# cut with an ellipsis; a link in the cut cell keeps its slot in the row list
		local marks=${1//[!$'\x02']/} m
		for ((m = 0; m < ${#marks}; m++)); do TUI_MD_LINK_ROWS+=(-1); done
		_tui_md.cut "${1//$'\x02'/}" $(($2 - 1))
		_TB_LINES=("${_CH}…${_TUI_MD_RESET}")
		return 0
	fi
	_tui_md.wrap "$1" "$2" 0
	_TB_LINES=("${TUI_MD_ROWS[@]}")
	((${#_TB_LINES[@]})) || _TB_LINES=("")
	for ((k = l0; k < ${#TUI_MD_LINK_ROWS[@]}; k++)); do TUI_MD_LINK_ROWS[k]=-1; done # fixed when the table is placed
}

# _tui_md.table_image_cell CELL WIDTH -> _TB_LINES _TB_W - a cell that holds only pictures as placeholder rows of at most WIDTH
# cells; rc 1 (nothing set) when graphics are off or no picture could be shown. The strip is laid out by _tui_md.image_strip
# into scratch arrays, so the cell's links (already registered by the text render) are not registered twice.
_tui_md.table_image_cell() {
	[[ "$TUI_MD_IMAGES" == graphics && "$1" == *"!["* ]] || return 1
	_tui_md.image_only "$1" || return 1
	local -a TUI_MD_ROWS=() TUI_MD_MAP=() TUI_MD_LINK_URLS=() TUI_MD_LINK_TEXTS=() TUI_MD_LINK_ROWS=()
	_tui_md.image_strip "$1" "$2" 0 || return 1
	local l
	_TB_LINES=("${TUI_MD_ROWS[@]}")
	_TB_W=0
	for l in "${_TB_LINES[@]}"; do
		_tui_md.vlen "$l"
		((_VL > _TB_W)) && _TB_W=$_VL
	done
	return 0
}

# _tui_md.table_emit LN CELL_INDEX0 - one table row from the rendered cells (uses _tui_md.table_render's locals)
_tui_md.table_emit() {
	local ln=$1 base=$2 hmax=1 cc kk text pad lw piece left right seg
	local -a col_lines=() ll=()
	for ((cc = 0; cc < cols; cc++)); do
		if [[ -n "${imgl[$((base + cc))]+x}" ]]; then
			IFS=$'\x1e' read -ra _TB_LINES <<<"${imgl[$((base + cc))]}"
			text=${rendered[base + cc]//[!$'\x02']/} # the links of a picture cell keep their slot in the row list
			for ((kk = 0; kk < ${#text}; kk++)); do TUI_MD_LINK_ROWS+=(-1); done
		else
			_tui_md.table_cell "${rendered[base + cc]}" "${cw[cc]}" "${rwidth[base + cc]}"
		fi
		printf -v text '%s\x1e' "${_TB_LINES[@]}"
		col_lines[cc]=$text
		((${#_TB_LINES[@]} > hmax)) && hmax=${#_TB_LINES[@]}
	done
	for ((kk = 0; kk < hmax; kk++)); do
		text="${marker}${vbar}${reset}"
		for ((cc = 0; cc < cols; cc++)); do
			IFS=$'\x1e' read -ra ll <<<"${col_lines[cc]}"
			piece=${ll[kk]:-}
			if ((${#ll[@]} == 1)) && ((kk == 0)); then lw=${rwidth[base + cc]}; else
				_tui_md.vlen "$piece"
				lw=$_VL
			fi
			pad=$((cw[cc] - lw))
			((pad < 0)) && pad=0
			left=0 right=$pad
			case "${align[cc]}" in
				r) left=$pad right=0 ;;
				c) left=$((pad / 2)) right=$((pad - pad / 2)) ;;
			esac
			printf -v seg '%*s' "$left" ''
			text+=" ${seg}${piece}"
			printf -v seg '%*s' "$right" ''
			text+="${seg} ${marker}${vbar}${reset}"
		done
		TUI_MD_ROWS+=("$text")
		TUI_MD_MAP+=("$ln")
	done
}

# _tui_md.table_render WIDTH - in _tui_md.blocks: renders the table starting at line i, sets i past it.
_tui_md.table_render() {
	local width=$1 j k c r first=${#TUI_MD_ROWS[@]} l0=${#TUI_MD_LINK_ROWS[@]} tl seg text
	local -a hdr=("${_TB_CELLS[@]}") rowcells=() rowln=() nw=() mw=() cw=() rendered=() rwidth=()
	local -a align=("${_TB_ALIGN[@]}")
	local cols=$_TB_COLS hln=${L[i]%%:*} dln=${L[i + 1]%%:*}
	local marker=${_TUI_MD_SGR[table]} reset=$_TUI_MD_RESET strong=${_TUI_MD_SGR[table_head]}
	j=$((i + 2))
	while ((j < n)); do
		tl=${L[j]#*:}
		_tui_md.is_blank "$tl" && break
		[[ "$tl" == *"|"* ]] || break
		_tui_md.split_row "$tl"
		while ((${#_TB_CELLS[@]} < cols)); do _TB_CELLS+=(""); done
		rowcells+=("${_TB_CELLS[@]:0:cols}")
		rowln+=("${L[j]%%:*}")
		((j++))
	done
	# every cell rendered once, in document order: its text, natural width, and the longest word for the minimum
	local idx=0 cell word plain nrows=${#rowln[@]}
	for ((c = 0; c < cols; c++)); do nw[c]=1 mw[c]=1; done
	for cell in "${hdr[@]}" "${rowcells[@]}"; do
		c=$((idx % cols))
		if ((idx < cols)); then
			_tui_md.inline_memo "$cell" "$strong"
			rendered+=("${strong}${_MD_OUT}${reset}")
		else
			_tui_md.inline_memo "$cell" ""
			rendered+=("$_MD_OUT")
		fi
		_tui_md.vlen "${rendered[idx]//$'\x02'/}"
		rwidth[idx]=$_VL
		((_VL > nw[c])) && nw[c]=$_VL
		_tui_md.strip_marks "${rendered[idx]}"
		for word in $_PLAIN; do ((${#word} > mw[c])) && mw[c]=${#word}; done
		((idx++))
	done
	# pictures: a cell of nothing but pictures is drawn as pictures, each no wider than an equal share of the table
	local -A imgl=()
	local nids=${#TUI_MD_IMAGE_IDS[@]} share=$(((width - 3 * cols - 1) / cols)) cells_all=("${hdr[@]}" "${rowcells[@]}") pic=0
	if [[ "$TUI_MD_IMAGES" == graphics ]] && ((share >= 4)); then
		for ((idx = 0; idx < ${#cells_all[@]}; idx++)); do
			_tui_md.table_image_cell "${cells_all[idx]}" "$share" || continue
			printf -v text '%s\x1e' "${_TB_LINES[@]}"
			imgl[$idx]=$text
			rwidth[idx]=$_TB_W
			pic=1
		done
		if ((pic)); then # the columns' widths again: a picture cell is as wide as its picture and cannot shrink
			for ((c = 0; c < cols; c++)); do nw[c]=1 mw[c]=1; done
			for ((idx = 0; idx < ${#cells_all[@]}; idx++)); do
				c=$((idx % cols))
				((rwidth[idx] > nw[c])) && nw[c]=${rwidth[idx]}
				if [[ -n "${imgl[$idx]+x}" ]]; then
					((rwidth[idx] > mw[c])) && mw[c]=${rwidth[idx]}
					continue
				fi
				_tui_md.strip_marks "${rendered[idx]}"
				for word in $_PLAIN; do ((${#word} > mw[c])) && mw[c]=${#word}; done
			done
		fi
	fi
	local avail=$((width - 3 * cols - 1)) sum=0 widest
	cw=("${nw[@]}")
	for c in "${cw[@]}"; do ((sum += c)); done
	if ((sum > avail)); then
		# shrink the widest column first, never below its longest word (capped at 12, at least 3 cells)
		for ((c = 0; c < cols; c++)); do
			((mw[c] > 12)) && mw[c]=12
			((mw[c] < 3)) && mw[c]=3
		done
		while ((sum > avail)); do
			widest=-1
			for ((c = 0; c < cols; c++)); do
				((cw[c] > mw[c])) && { ((widest < 0 || cw[c] > cw[widest])) && widest=$c; }
			done
			((widest < 0)) && break
			((cw[widest]--, sum--))
		done
	fi
	if ((sum > avail || avail < cols)) || [[ "$TUI_MD_TABLES" == stacked ]]; then
		# too narrow for a grid (or asked for): each row as "Header: value" lines
		for ((r = 0; r < nrows; r++)); do
			((r > 0)) && {
				TUI_MD_ROWS+=("")
				TUI_MD_MAP+=("${rowln[r]}")
			}
			for ((c = 0; c < cols; c++)); do
				_tui_md.wrap "${strong}${hdr[c]}${reset}: ${rendered[(r + 1) * cols + c]}" "$width" "${rowln[r]}"
			done
		done
		for ((k = l0; k < ${#TUI_MD_LINK_ROWS[@]}; k++)); do ((TUI_MD_LINK_ROWS[k] < 0)) && TUI_MD_LINK_ROWS[k]=$first; done
		TUI_MD_IMAGE_IDS=("${TUI_MD_IMAGE_IDS[@]:0:nids}") # as text: the pictures laid out above are not shown
		i=$j
		return 0
	fi
	local top="┌" sep="├" bot="└" vbar="│" tr="┐" br="┘" sr="┤"
	[[ "$TUI_MD_TABLES" == rounded ]] && top="╭" bot="╰" tr="╮" br="╯"
	for ((c = 0; c < cols; c++)); do
		printf -v seg '%*s' $((cw[c] + 2)) ''
		seg=${seg// /─}
		if ((c < cols - 1)); then
			top+="${seg}┬" sep+="${seg}┼" bot+="${seg}┴"
		else
			top+="${seg}${tr}" sep+="${seg}${sr}" bot+="${seg}${br}"
		fi
	done
	if [[ "$TUI_MD_TABLES" == plain ]]; then
		# no frame: columns separated by spaces, one rule under the header
		vbar=" "
		printf -v seg '%*s' $((sum + 3 * cols + 1)) ''
		sep=${seg// /─}
	else
		TUI_MD_ROWS+=("${marker}${top}${reset}")
		TUI_MD_MAP+=("$hln")
	fi
	_tui_md.table_emit "$hln" 0
	TUI_MD_ROWS+=("${marker}${sep}${reset}")
	TUI_MD_MAP+=("$dln")
	for ((r = 0; r < nrows; r++)); do _tui_md.table_emit "${rowln[r]}" $(((r + 1) * cols)); done
	if [[ "$TUI_MD_TABLES" != plain ]]; then
		TUI_MD_ROWS+=("${marker}${bot}${reset}")
		TUI_MD_MAP+=("${rowln[-1]:-$dln}")
	fi
	for ((k = l0; k < ${#TUI_MD_LINK_ROWS[@]}; k++)); do ((TUI_MD_LINK_ROWS[k] < 0)) && TUI_MD_LINK_ROWS[k]=$first; done
	i=$j
}

# _tui_md.strip_marks STR -> _PLAIN - STR without SGR and link markers
_tui_md.strip_marks() {
	tui.md.strip "$1" _PLAIN
	_PLAIN=${_PLAIN//$'\x02'/}
}
