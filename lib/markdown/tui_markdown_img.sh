#!/usr/bin/env bash
# tui_markdown_img.sh - pictures in rendered Markdown through the kitty graphics protocol (kitty, Ghostty).
#
# A paragraph made only of images - ![alt](file) or [![alt](file)](link), one or several - becomes a strip of rows: every
# image is sent to the terminal once, by file path, with a virtual placement, and its rows hold Unicode placeholder cells
# (U+10EEEE plus a row and column diacritic, the image id in the foreground color). Because a picture is ordinary text to
# everything else, wrapping, scrolling, clipping, folding and the row cache keep working with no placement layer. Several
# images share rows left to right and wrap like words.
#
# Formats: PNG goes as it is. SVG (rsvg-convert) and GIF, JPEG, WebP ... (ImageMagick, else ffmpeg: the first frame) are
# converted once to a PNG in the cache folder, when one of those tools is installed. Remote images are fetched in the
# background with curl or wget only when TUI_MD_IMAGE_FETCH=1; until they arrive they show as placeholders.
#
#   tui.md.images graphics         turns it on (needs a terminal where tui.md.image_protocol says kitty)
#   TUI_MD_IMAGE_MAX_COLS / TUI_MD_IMAGE_MAX_ROWS     size limits in cells (default 60 x 20)
#   TUI_MD_IMAGE_FETCH             1: fetch http(s) images (default 0)
#   TUI_MD_BASE_DIR                relative image paths resolve against it (tui.md.show_file sets it to the file's folder)
# requires: tui_markdown

declare -ga _TUI_MD_DIA=(
	0305 030D 030E 0310 0312 033D 033E 033F 0346 034A 034B 034C 0350 0351 0352 0357
	035B 0363 0364 0365 0366 0367 0368 0369 036A 036B 036C 036D 036E 036F 0483 0484
	0485 0486 0487 0592 0593 0594 0595 0597 0598 0599 059C 059D 059E 059F 05A0 05A1
	05A8 05A9 05AB 05AC 05AF 05C4 0610 0611 0612 0613 0614 0615 0616 0617 0657 0658
	0659 065A 065B 065D 065E 06D6 06D7 06D8 06D9 06DA 06DB 06DC 06DF 06E0 06E1 06E2
	06E4 06E7 06E8 06EB 06EC 0730 0732 0733 0735 0736 073A 073D 073F 0740 0741 0743
	0745 0747 0749 074A 07EB 07EC 07ED 07EE 07EF 07F0 07F1 07F3 0816 0817 0818 0819
	081B 081C 081D 081E 081F 0820 0821 0822 0823 0825 0826 0827 0829 082A 082B 082C
)
declare -ga _TUI_MD_DIAC=()          # the diacritics as UTF-8 characters, index = row or column number
declare -gA _TUI_MD_ZW=()            # code point (decimal) of a diacritic -> 1: zero cells wide
declare -gA _TUI_MD_IMG_ID=()        # "PATH|COLS|ROWS" -> kitty image id
declare -gA _TUI_MD_IMG_SENT=()      # image id -> 1 once its commands went to the terminal
declare -gA TUI_MD_IMAGE_CMD=()      # image id -> the APC command of the last render that creates it
declare -ga TUI_MD_IMAGE_IDS=()      # ids the last render shows
declare -gA _TUI_MD_PNG=()           # path -> "WIDTHxHEIGHT"
declare -gi _TUI_MD_IMG_NEXT=0 TUI_MD_IMAGE_MAX_COLS="${TUI_MD_IMAGE_MAX_COLS:-60}" TUI_MD_IMAGE_MAX_ROWS="${TUI_MD_IMAGE_MAX_ROWS:-20}"
declare -g TUI_MD_BASE_DIR="${TUI_MD_BASE_DIR:-}" _TUI_MD_PLACEHOLDER=""
_TUI_MD_RE_IMG_LINKED='^\[!\[([^]]*)\]\(<?([^) >]+)>?([[:space:]]+("[^"]*"|'"'"'[^'"'"']*'"'"'))?\)\]\(([^)]*)\)'
_TUI_MD_RE_IMG_PLAIN='^!\[([^]]*)\]\(<?([^) >]+)>?([[:space:]]+("[^"]*"|'"'"'[^'"'"']*'"'"'))?\)'
declare -gA _TUI_MD_IMGPNG=()       # source (path or URL) -> the PNG to show ("" = not convertible)
declare -gA _TUI_MD_FETCH_PENDING=() # URL -> cache file the background fetch will create
declare -gi TUI_MD_IMAGE_FETCH="${TUI_MD_IMAGE_FETCH:-0}" _TUI_MD_FETCH_POLLS=0
declare -gi _TUI_MD_IMG_BASE=8388608 # 0x800000: image ids start here, away from the small ids other tools use

# _tui_md.utf8 CODEPOINT -> _U8 - the character as UTF-8 bytes, whatever the locale.
_tui_md.utf8() {
	local cp=$1
	if ((cp < 0x80)); then
		printf -v _U8 '\\x%02x' "$cp"
	elif ((cp < 0x800)); then
		printf -v _U8 '\\x%02x\\x%02x' $((0xC0 | cp >> 6)) $((0x80 | cp & 0x3F))
	elif ((cp < 0x10000)); then
		printf -v _U8 '\\x%02x\\x%02x\\x%02x' $((0xE0 | cp >> 12)) $((0x80 | cp >> 6 & 0x3F)) $((0x80 | cp & 0x3F))
	else
		printf -v _U8 '\\x%02x\\x%02x\\x%02x\\x%02x' $((0xF0 | cp >> 18)) $((0x80 | cp >> 12 & 0x3F)) $((0x80 | cp >> 6 & 0x3F)) $((0x80 | cp & 0x3F))
	fi
	printf -v _U8 "$_U8"
}

_tui_md.img_init() {
	local h
	for h in "${_TUI_MD_DIA[@]}"; do
		_tui_md.utf8 $((16#$h))
		_TUI_MD_DIAC+=("$_U8")
		_TUI_MD_ZW[$((16#$h))]=1
	done
	_tui_md.utf8 $((0x10EEEE))
	_TUI_MD_PLACEHOLDER=$_U8
}
_tui_md.img_init

# _tui_md.b64 STRING -> _B64 - base64 of the bytes of STRING (no fork, no base64 tool)
_tui_md.b64() {
	local LC_ALL=C s=$1 out="" i n=${#1} a b c v
	local chars=ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/
	for ((i = 0; i < n; i += 3)); do
		printf -v a '%d' "'${s:i:1}"
		b=0 c=0
		((i + 1 < n)) && printf -v b '%d' "'${s:i+1:1}"
		((i + 2 < n)) && printf -v c '%d' "'${s:i+2:1}"
		v=$((a << 16 | b << 8 | c))
		out+=${chars:v >> 18 & 63:1}${chars:v >> 12 & 63:1}
		if ((i + 1 < n)); then out+=${chars:v >> 6 & 63:1}; else out+="="; fi
		if ((i + 2 < n)); then out+=${chars:v & 63:1}; else out+="="; fi
	done
	_B64=$out
}

# _tui_md.png_size PATH -> _PW _PH - pixel size from the PNG header; rc 1 when it is not a readable PNG
_tui_md.png_size() {
	local info
	if [[ -z "${_TUI_MD_PNG[$1]+x}" ]]; then
		[[ -f "$1" && -r "$1" ]] || return 1
		# the IHDR chunk: 8-byte signature, 4 length, 4 type, then width and height as big-endian 32-bit numbers
		info=$(od -An -tu1 -N24 -- "$1" 2>/dev/null) || return 1
		local -a b
		read -ra b <<<"${info//$'\n'/ }" # od prints 16 bytes a line
		((${#b[@]} == 24 && b[0] == 137 && b[1] == 80 && b[2] == 78 && b[3] == 71)) || return 1
		_TUI_MD_PNG[$1]="$((b[16] << 24 | b[17] << 16 | b[18] << 8 | b[19]))x$((b[20] << 24 | b[21] << 16 | b[22] << 8 | b[23]))"
	fi
	_PW=${_TUI_MD_PNG[$1]%%x*}
	_PH=${_TUI_MD_PNG[$1]##*x}
	((_PW > 0 && _PH > 0))
}

# _tui_md.cache_dir -> _CD - the folder of converted and fetched images (created)
_tui_md.cache_dir() {
	_CD="${XDG_CACHE_HOME:-$HOME/.cache}/DABT/md-images"
	[[ -d "$_CD" ]] || mkdir -p "$_CD"
}

# _tui_md.is_png FILE - rc 0 when the file starts with the PNG signature
_tui_md.is_png() {
	local LC_ALL=C sig
	IFS= read -r -N 4 sig <"$1" 2>/dev/null || true
	[[ "$sig" == $'\x89PNG' ]]
}

# _tui_md.convert FILE -> _IMGP - FILE as a PNG in the cache (SVG with rsvg-convert, other formats with ImageMagick or ffmpeg,
# first frame of an animation); rc 1 when no installed tool can read it.
_tui_md.convert() {
	local f=$1 sum size name out head
	_tui_md.cache_dir
	read -r sum size name < <(cksum <"$f") || return 1
	out="$_CD/${sum}_${size}.png"
	if [[ ! -f "$out" ]]; then
		IFS= read -r -N 300 head <"$f" 2>/dev/null || true
		if [[ "$head" == *"<svg"* ]]; then
			command -v rsvg-convert >/dev/null 2>&1 || return 1
			rsvg-convert -o "$out" -- "$f" >/dev/null 2>&1 || {
				rm -f "$out"
				return 1
			}
		elif command -v magick >/dev/null 2>&1; then
			magick "${f}[0]" -background none -resize '800x800>' "png:$out" >/dev/null 2>&1 || {
				rm -f "$out"
				return 1
			}
		elif command -v convert >/dev/null 2>&1; then
			convert "${f}[0]" -background none -resize '800x800>' "png:$out" >/dev/null 2>&1 || {
				rm -f "$out"
				return 1
			}
		elif command -v ffmpeg >/dev/null 2>&1; then
			ffmpeg -v error -y -i "$f" -frames:v 1 "$out" >/dev/null 2>&1 || {
				rm -f "$out"
				return 1
			}
		else
			return 1
		fi
	fi
	_IMGP=$out
}

# _tui_md.fetch URL - starts a background download of URL into the cache (once); the image shows after the next re-render.
_tui_md.fetch() {
	local url=$1 sum size name file
	[[ -n "${_TUI_MD_FETCH_PENDING[$url]+x}" ]] && return 0
	_tui_md.cache_dir
	read -r sum size name < <(cksum <<<"$url")
	file="$_CD/url_${sum}_${size}.src"
	_TUI_MD_FETCH_PENDING[$url]=$file
	if command -v curl >/dev/null 2>&1; then
		(curl -fsSL --max-time 15 --max-filesize 8000000 -o "$file.part" -- "$url" && mv -f "$file.part" "$file") >/dev/null 2>&1 &
	elif command -v wget >/dev/null 2>&1; then
		(wget -q -T 15 -O "$file.part" -- "$url" && mv -f "$file.part" "$file") >/dev/null 2>&1 &
	else
		return 1
	fi
	_TUI_MD_FETCH_POLLS=0
	tui.after 0.7 _tui_md.fetch_poll md_fetch 2>/dev/null
}

# _tui_md.fetch_poll - a finished download makes the shown panes render again; polls for about 40 s
_tui_md.fetch_poll() {
	local url done=0 pane
	for url in "${!_TUI_MD_FETCH_PENDING[@]}"; do
		if [[ -f "${_TUI_MD_FETCH_PENDING[$url]}" ]]; then
			unset '_TUI_MD_IMGPNG[$url]' '_TUI_MD_FETCH_PENDING[$url]'
			_TUI_MD_FETCHED[$url]=1
			done=1
		elif [[ ! -e "${_TUI_MD_FETCH_PENDING[$url]}.part" ]] && ((_TUI_MD_FETCH_POLLS > 2)); then
			unset '_TUI_MD_FETCH_PENDING[$url]' # the download failed: placeholders stay
		fi
	done
	if ((done)); then
		for pane in "${!_TUI_MD_SHOWN[@]}"; do unset '_TUI_MD_SHOWN_W[$pane]'; done
		_tui_md.refit
	fi
	((++_TUI_MD_FETCH_POLLS < 60 && ${#_TUI_MD_FETCH_PENDING[@]} > 0)) && tui.after 0.7 _tui_md.fetch_poll md_fetch 2>/dev/null
	return 0
}
declare -gA _TUI_MD_FETCHED=() # URL -> 1 once its file is in the cache

# _tui_md.image_png SRC -> _IMGP - a PNG file for SRC (a path relative to TUI_MD_BASE_DIR, or a URL); rc 1 when there is none yet
_tui_md.image_png() {
	local src=$1 file key
	if [[ "$src" == http://* || "$src" == https://* ]]; then
		((TUI_MD_IMAGE_FETCH)) || return 1
		if [[ -n "${_TUI_MD_IMGPNG[$src]+x}" ]]; then
			_IMGP=${_TUI_MD_IMGPNG[$src]}
			[[ -n "$_IMGP" ]]
			return
		fi
		_tui_md.cache_dir
		read -r key _ < <(cksum <<<"$src")
		local f
		for f in "$_CD"/url_${key}_*.src; do [[ -f "$f" ]] && file=$f; done
		if [[ -z "${file:-}" ]]; then
			_tui_md.fetch "$src"
			return 1
		fi
	else
		file=$src
		[[ "$file" == /* || -z "$TUI_MD_BASE_DIR" ]] || file="$TUI_MD_BASE_DIR/$file"
		if [[ -n "${_TUI_MD_IMGPNG[$file]+x}" ]]; then
			_IMGP=${_TUI_MD_IMGPNG[$file]}
			[[ -n "$_IMGP" ]]
			return
		fi
		[[ -f "$file" && -r "$file" ]] || return 1
	fi
	if _tui_md.is_png "$file"; then
		_IMGP=$file
	elif ! _tui_md.convert "$file"; then
		_IMGP=""
	fi
	_TUI_MD_IMGPNG[${file}]=$_IMGP
	[[ "$src" == http* ]] && _TUI_MD_IMGPNG[$src]=$_IMGP
	[[ -n "$_IMGP" ]]
}

# _tui_md.image_segment ALT SRC WIDTH -> _SEG_COLS _SEG_ROWS (rows in _SEG_LINES) - one picture as placeholder rows, or the
# placeholder text when it cannot be shown
_tui_md.image_segment() {
	local alt=$1 src=$2 width=$3 path cols rows key id r c line fg txt
	_SEG_LINES=()
	if _tui_md.image_png "$src" && _tui_md.png_size "$_IMGP"; then
		path=$_IMGP
		# about 9 x 18 pixels per cell: the width in cells from the pixels, the height keeping the aspect
		cols=$(((_PW + 8) / 9))
		((cols > TUI_MD_IMAGE_MAX_COLS)) && cols=$TUI_MD_IMAGE_MAX_COLS
		((cols > width)) && cols=$width
		((cols > ${#_TUI_MD_DIAC[@]})) && cols=${#_TUI_MD_DIAC[@]}
		((cols < 1)) && cols=1
		rows=$(((_PH * cols + 2 * _PW - 1) / (2 * _PW)))
		if ((rows > TUI_MD_IMAGE_MAX_ROWS)); then
			rows=$TUI_MD_IMAGE_MAX_ROWS
			cols=$(((2 * _PW * rows + _PH - 1) / _PH))
			((cols > width)) && cols=$width
			((cols > ${#_TUI_MD_DIAC[@]})) && cols=${#_TUI_MD_DIAC[@]}
			((cols < 1)) && cols=1
		fi
		((rows < 1)) && rows=1
		((rows > ${#_TUI_MD_DIAC[@]})) && rows=${#_TUI_MD_DIAC[@]}
		key="$path|$cols|$rows"
		if [[ -z "${_TUI_MD_IMG_ID[$key]+x}" ]]; then
			_TUI_MD_IMG_ID[$key]=$((_TUI_MD_IMG_BASE + ++_TUI_MD_IMG_NEXT))
		fi
		id=${_TUI_MD_IMG_ID[$key]}
		_tui_md.b64 "$path"
		# transmit by path (t=f), PNG (f=100), with a virtual placement (U=1, a=T) of cols x rows cells; quiet (q=2)
		TUI_MD_IMAGE_CMD[$id]=$'\e_Ga=T,U=1,f=100,t=f,i='"$id,c=$cols,r=$rows,q=2;$_B64"$'\e\\'
		TUI_MD_IMAGE_IDS+=("$id")
		fg=$'\e[38;2;'"$((id >> 16 & 255));$((id >> 8 & 255));$((id & 255))m"
		for ((r = 0; r < rows; r++)); do
			# the first cell of a row names row and column, the others continue from the cell on their left
			line="${fg}${_TUI_MD_PLACEHOLDER}${_TUI_MD_DIAC[r]}${_TUI_MD_DIAC[0]}"
			for ((c = 1; c < cols; c++)); do line+=$_TUI_MD_PLACEHOLDER; done
			_SEG_LINES+=("${line}${_TUI_MD_RESET}")
		done
		_SEG_COLS=$cols _SEG_ROWS=$rows
		return 0
	fi
	txt="[img${alt:+: $alt}]"
	_tui_md.cells "$txt"
	_SEG_COLS=$_VL _SEG_ROWS=1
	((_SEG_COLS > width)) && {
		txt=${txt:0:width}
		_SEG_COLS=${#txt}
	}
	_SEG_LINES=("${_TUI_MD_SGR[marker]}${txt}${_TUI_MD_RESET}")
	return 1
}

# _tui_md.image_only TEXT -> _ALT - rc 0 when TEXT holds nothing but pictures ([![alt](src)](link) or ![alt](src)); _ALT is
# their alt texts joined by a space. A heading or a table cell like that is a picture, not text.
_tui_md.image_only() {
	local rest=$1 n=0 sp=$'[[:space:]\x01]'
	_ALT=""
	while [[ -n "${rest//$sp/}" ]]; do
		rest=${rest#"${rest%%[![:space:]$'\x01']*}"}
		if [[ "$rest" =~ $_TUI_MD_RE_IMG_LINKED || "$rest" =~ $_TUI_MD_RE_IMG_PLAIN ]]; then
			_ALT+="${_ALT:+ }${BASH_REMATCH[1]}"
			((n++))
			rest=${rest:${#BASH_REMATCH[0]}}
		else
			return 1
		fi
	done
	((n > 0))
}

# _tui_md.image_strip TEXT WIDTH LINENO - when TEXT (a paragraph) holds only images, appends them left to right, wrapping like
# words; rc 1 (nothing appended) when graphics are off, the terminal cannot show them, TEXT holds anything else, or no image
# could be shown (then the paragraph renders as text with placeholders).
_tui_md.image_strip() {
	local rest=$1 width=$2 ln=$3 proto n i k r h used line pad shown=0
	[[ "$TUI_MD_IMAGES" == graphics ]] || return 1
	tui.md.image_protocol proto
	[[ "$proto" == kitty ]] || return 1
	local -a alts=() srcs=() urls=()
	local sp=$'[[:space:]\x01]'
	while [[ -n "${rest//$sp/}" ]]; do
		rest=${rest#"${rest%%[![:space:]$'\x01']*}"}
		if [[ "$rest" =~ $_TUI_MD_RE_IMG_LINKED ]]; then
			alts+=("${BASH_REMATCH[1]}")
			srcs+=("${BASH_REMATCH[2]}")
			urls+=("${BASH_REMATCH[5]}")
		elif [[ "$rest" =~ $_TUI_MD_RE_IMG_PLAIN ]]; then
			alts+=("${BASH_REMATCH[1]}")
			srcs+=("${BASH_REMATCH[2]}")
			urls+=("")
		else
			return 1
		fi
		rest=${rest:${#BASH_REMATCH[0]}}
	done
	n=${#srcs[@]}
	((n > 0)) || return 1
	# all segments first: a strip with no picture at all is left to the text renderer
	local -a scols=() srows=() smap=()
	local -A slines=()
	local nids=${#TUI_MD_IMAGE_IDS[@]}
	for ((i = 0; i < n; i++)); do
		_tui_md.image_segment "${alts[i]}" "${srcs[i]}" "$width" && shown=1
		scols[i]=$_SEG_COLS
		srows[i]=$_SEG_ROWS
		for ((r = 0; r < _SEG_ROWS; r++)); do slines[$i.$r]=${_SEG_LINES[r]}; done
	done
	if ((!shown)); then
		TUI_MD_IMAGE_IDS=("${TUI_MD_IMAGE_IDS[@]:0:nids}")
		return 1
	fi
	# lay out: images side by side with one cell between, a new strip line when the next does not fit
	local start=0 first
	while ((start < n)); do
		used=0 h=0 k=$start
		while ((k < n)); do
			if ((k > start && used + 1 + scols[k] > width)); then break; fi
			((used += (k > start ? 1 : 0) + scols[k]))
			((srows[k] > h)) && h=${srows[k]}
			((k++))
		done
		first=${#TUI_MD_ROWS[@]}
		for ((r = 0; r < h; r++)); do
			line=""
			for ((i = start; i < k; i++)); do
				((i > start)) && line+=" "
				if ((r < srows[i])); then
					line+=${slines[$i.$r]}
				else
					printf -v pad '%*s' "${scols[i]}" ''
					line+=$pad
				fi
			done
			TUI_MD_ROWS+=("$line")
			TUI_MD_MAP+=("$ln")
		done
		for ((i = start; i < k; i++)); do
			if [[ -n "${urls[i]}" ]]; then
				TUI_MD_LINK_URLS+=("${urls[i]}")
				TUI_MD_LINK_TEXTS+=("${alts[i]}")
				TUI_MD_LINK_ROWS+=("$first")
			fi
		done
		start=$k
	done
	return 0
}

# _tui_md.images_present PANE - after a render: remembers which images the pane shows, deletes the ones it no longer shows
# and sends the new ones (see _tui_md.images_send).
_tui_md.images_present() {
	local pane=$1 id out="" old=" ${_TUI_MD_V[$pane.imgs]:-} " now=" ${TUI_MD_IMAGE_IDS[*]} "
	for id in $old; do
		[[ "$now" == *" $id "* ]] && continue
		if [[ -n "${_TUI_MD_IMG_SENT[$id]+x}" ]]; then
			out+=$'\e_Ga=d,d=I,i='"$id"$',q=2\e\\'
			unset '_TUI_MD_IMG_SENT[$id]'
		fi
	done
	now=${now# }
	_TUI_MD_V[$pane.imgs]=${now% }
	((${_TUI_RUNNING:-0})) && [[ -n "$out" ]] && printf '%s' "$out"
	_tui_md.images_send
	return 0
}

# _tui_md.images_send - writes the transmit-and-place command of every shown image the terminal has not got yet. The output
# goes to the terminal, so it waits until the app runs (the ready hook and every refit call this again).
_tui_md.images_send() {
	local pane id out=""
	((${_TUI_RUNNING:-0})) || return 0
	for pane in "${!_TUI_MD_SHOWN[@]}"; do
		for id in ${_TUI_MD_V[$pane.imgs]:-}; do
			[[ -n "${_TUI_MD_IMG_SENT[$id]+x}" ]] && continue
			out+=${TUI_MD_IMAGE_CMD[$id]}
			_TUI_MD_IMG_SENT[$id]=1
		done
	done
	[[ -n "$out" ]] && printf '%s' "$out"
	return 0
}

# _tui_md.images_clear - the terminal drops every picture this module sent (the exit hook).
_tui_md.images_clear() {
	local id out=""
	for id in "${!_TUI_MD_IMG_SENT[@]}"; do out+=$'\e_Ga=d,d=I,i='"$id"$',q=2\e\\'; done
	_TUI_MD_IMG_SENT=()
	[[ -n "$out" ]] && printf '%s' "$out"
	return 1 # an exit hook that does not claim the event
}
