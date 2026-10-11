#!/usr/bin/env bash
# home_callbacks.sh - the Home demo page (share/demo/home.xml). The hero is one pane with two painters (the rain is off unless
# TUI_HOME_RAIN=1 is set: it is disabled, not removed):
#
#   the text   the DABT banner, its name typed out underneath, the tagline and the news. The main loop paints it with
#              tui.set_canvas, and only when it changes (a character typed, the glint moved, the news turned). Cells the text
#              does not use are "skip" cells (cursor right), so painting it never wipes what is behind it.
#   the rain   dim matrix rain over the whole pane, painted by a process of its own (tui.async.start) straight to the
#              terminal, 25 frames a second, changes only. It never draws on a cell the text covers (the main loop publishes
#              their indices) and it stops while a modal or a layer is open. The main loop pays nothing for it, so a hover or
#              a focus highlight is never queued behind a frame.
# The timers (typing, cursor and glint, news) belong to the page and end with it, and so does the rain process.
tui.require terminal_renderer

# the four pastels of the start-up splash, one per letter of DABT, and the words each letter stands for
declare -ga _HOME_RGB=("255;140;191" "168;216;255" "255;243;168" "255;158;158")
declare -ga _HOME_WORDS=(Dinos Amazing Bash Tui)
declare -gi _HOME_TYPED=0 _HOME_WAIT=0 _HOME_CURSOR=1 _HOME_LEN=0 _HOME_GLINT=4 _HOME_RAIN=${TUI_HOME_RAIN:-0} _HOME_DT=0 _HOME_SEED=7 _HOME_VER=0
declare -gi _HOME_DIRTY=1 _HOME_W=0 _HOME_H=0 _HOME_STRIDE=1 # the size the grid was built for; a row is _HOME_W cells and one more that ends the line
for _hw in "${_HOME_WORDS[@]}"; do _HOME_LEN=$((_HOME_LEN + ${#_hw})); done
unset _hw
declare -g _HOME_SKIP=$'\e[C' # a cell of the grid the text does not use: the cursor moves over it and what is there stays
declare -ga _HOME_BLANK=() _HOME_CELL=() _HOME_TXT_I=() _HOME_TXT_V=() _HOME_TXTPREV=() _HOME_FADE=()
declare -gA _HOME_CACHED=()      # which banner / pills parts of the text layer are built (b0..b5, p0..)
declare -ga _HR_SP=() _HR_LEN=() # rain columns (in the painter), index = column
declare -g _HR_TEXT="" _HR_R=0

# _home_rand MOD -> _HR_R: a number below MOD (a small generator, so the rain is the same on every run)
_home_rand() {
	_HOME_SEED=$(((_HOME_SEED * 1103515245 + 12345) & 0x7fffffff))
	_HR_R=$(((_HOME_SEED >> 12) % $1))
}

# the rain's colours: one column in each banner pastel (pink, blue, yellow, red in turn), fading from head to tail and all
# dim, so it stays a backdrop. 256-colour codes: a third of the bytes of a 24-bit one, and the rain is most of what is sent.
declare -ga _HR_PAL=() # index: colour * 6 + step
_home_rain_palette() {
	local c k r g b
	local -a fade=(46 32 22 15 10 7) # percent of the pastel, head first
	for c in 0 1 2 3; do
		IFS=';' read -r r g b <<<"${_HOME_RGB[c]}"
		for k in 0 1 2 3 4 5; do
			_HR_PAL[c * 6 + k]=$'\e[38;5;'"$((16 + 36 * ((r * fade[k] / 100 * 5 + 127) / 255) + 6 * ((g * fade[k] / 100 * 5 + 127) / 255) + (b * fade[k] / 100 * 5 + 127) / 255))m"
		done
	done
}
_home_rain_palette
declare -ga _HR_CH=() _HR_STEP=() # the rain's letters one by one; the palette step of tail cell K of a tail LEN long, at LEN * 10 + K
_home_rain_tables() {
	local chars='0123456789abcdefghijklmnopqrstuvwxyz$+-*/=%#&<>[]{}|~^:;' i len k
	for ((i = 0; i < ${#chars}; i++)); do _HR_CH[i]="${chars:i:1}"; done
	for ((len = 4; len <= 8; len++)); do for ((k = 0; k < len; k++)); do _HR_STEP[len * 10 + k]=$((k * 6 / len)); done; done
}
_home_rain_tables

# _home_inner PANE -> _HI_W _HI_H: the cells the pane's text may use (inside its border and padding)
_home_inner() {
	_tui._content_rect "$1"
	_HI_W=$_CR_W
	_HI_H=$_CR_H
}

# _home_size - the grid for the hero's present size; a new size starts everything over. rc 1 when the pane is too small
_home_size() {
	local i
	_home_inner home_hero
	((_HI_W >= 30 && _HI_H >= 12)) || return 1
	if ((_HI_W != _HOME_W || _HI_H != _HOME_H)); then
		_HOME_W=$_HI_W _HOME_H=$_HI_H _HOME_STRIDE=$((_HI_W + 1))
		_HOME_BLANK=()
		for ((i = 0; i < _HOME_STRIDE * _HOME_H; i++)); do _HOME_BLANK[i]="$_HOME_SKIP"; done
		for ((i = _HOME_W; i < _HOME_STRIDE * _HOME_H; i += _HOME_STRIDE)); do _HOME_BLANK[i]=$'\e[0m\n'; done # the cell that ends a row: the frame is then one join
		_HOME_CELL=("${_HOME_BLANK[@]}")
		_HOME_TXTPREV=() _HOME_FADE=() _HOME_CACHED=()
		_HOME_DIRTY=1 # the text has to be laid on the new grid
		((_HOME_RAIN)) && _home_mask_cells
	fi
}

# ── the text on top ───────────────────────────────────────────────────────

# _home_put X Y SGR TEXT - TEXT as cells of the text layer at column X, row Y; spaces are left transparent. Every cell ends in a
# reset: the cursor and the pills set reverse video and a background, which must not run on into the blanks after them.
_home_put() {
	local LC_ALL=C.UTF-8 # TEXT is cut into characters: in the C locale a block would be cut into bytes
	local c ch
	(($2 >= 0 && $2 < _HOME_H)) || return 0
	for ((c = 0; c < ${#4}; c++)); do
		ch="${4:c:1}"
		[[ "$ch" == " " ]] && continue
		(($1 + c >= 0 && $1 + c < _HOME_W)) && {
			_HOME_TXT_I+=($(($2 * _HOME_STRIDE + $1 + c)))
			_HOME_TXT_V+=("$3$ch"$'\e[0m')
		}
	done
}

# _home_pill X Y SGR TEXT - TEXT on a background: every cell, spaces included
_home_pill() {
	local LC_ALL=C.UTF-8
	local c
	(($2 >= 0 && $2 < _HOME_H)) || return 0
	for ((c = 0; c < ${#4}; c++)); do
		(($1 + c >= 0 && $1 + c < _HOME_W)) && {
			_HOME_TXT_I+=($(($2 * _HOME_STRIDE + $1 + c)))
			_HOME_TXT_V+=("$3${4:c:1}"$'\e[0m')
		}
	done
}

# _home_clear X Y CW CH - blanks the rain under a rectangle, so it never runs through a letter or a pill
_home_clear() {
	local r c
	for ((r = $2; r < $2 + $4; r++)); do
		((r >= 0 && r < _HOME_H)) || continue
		for ((c = $1; c < $1 + $3; c++)); do
			((c >= 0 && c < _HOME_W)) && {
				_HOME_TXT_I+=($((r * _HOME_STRIDE + c)))
				_HOME_TXT_V+=(" ")
			}
		done
	done
}

declare -ga _HOME_TIPS=(
	"Shells keep the menu while pages swap"
	"Layers: drag windows, open a modal, a toast"
	"Detach a log with ⇱, dock it back with ⇲"
	"Fuse panes, drag dividers, collapse to a rail"
	"alt+c folds the menu, alt+r resizes it"
	"Pages are data: templates, loops, addons"
)
declare -gi _HOME_TIP=0 _HOME_BLINK=0

# _home_cache_part NAME - the cells being built (_HOME_TXT_I / _HOME_TXT_V) kept as arrays _HC_I_NAME / _HC_V_NAME
_home_cache_part() {
	local -n _ci="_HC_I_$1" _cv="_HC_V_$1"
	declare -ga "_HC_I_$1" "_HC_V_$1"
	_ci=("${_HOME_TXT_I[@]}")
	_cv=("${_HOME_TXT_V[@]}")
	_HOME_CACHED[$1]=1
}

# _home_banner_part GLINT - the blank margin and D A B T in five rows (one pastel each; letter GLINT in white): built once per
# glint position and size, then reused
_home_banner_part() {
	local LC_ALL=C.UTF-8
	local -a glyph
	local i r x top ch
	[[ -n "${_HOME_CACHED[b$1]:-}" ]] && return 0
	_HOME_TXT_I=() _HOME_TXT_V=()
	_banner_font_init
	top=$(((_HOME_H - 11) / 2))
	x=$(((_HOME_W - 19) / 2))
	((_HOME_RAIN)) && _home_clear $((x - 3)) $((top - 1)) 25 8
	for ((i = 0; i < 4; i++)); do
		ch="DABT"
		IFS='|' read -ra glyph <<<"${_BANNER_FONT[${ch:i:1}]}"
		for ((r = 0; r < 5; r++)); do
			if ((i == $1)); then
				_home_put $((x + i * 5)) $((top + r)) $'\e[1;38;2;255;255;255m' "${glyph[r]}"
			else _home_put $((x + i * 5)) $((top + r)) $'\e[38;2;'"${_HOME_RGB[i]}m" "${glyph[r]}"; fi
		done
	done
	_home_cache_part "b$1"
}

# _home_class_sgr CLASS FALLBACK -> _HS: the SGR of theme class CLASS (foreground, background, modifiers), FALLBACK when the
# loaded theme does not define it. Read when a part of the text layer is built, which is once per page visit: a theme switch
# reloads the page.
_home_class_sgr() {
	local fg="${_TUI_CLASS_FG[$1]:-}" bg="${_TUI_CLASS_BG[$1]:-}" mo="${_TUI_CLASS_MOD[$1]:-}"
	if [[ -n "$fg$bg$mo" ]]; then
		_tui._sgr_from "$fg" "$bg" "$mo"
		_HS="$_SGR"
	else _HS="$2"; fi
}

# _home_tagline WIDTH -> _HT_TAG: the longest tagline that fits a pane WIDTH cells wide
_home_tagline() {
	_HT_TAG="A declarative, file-based terminal UI framework in pure bash  -  bash + POSIX utils + awk"
	((${#_HT_TAG} + 20 > $1)) && _HT_TAG="A declarative, file-based terminal UI framework in pure bash"
	((${#_HT_TAG} + 20 > $1)) && _HT_TAG="Terminal UIs in pure bash"
	return 0
}

# _home_mask_cells -> _HOME_MASKSTR: the indices of the cells the rain never draws on: the rectangles of the banner and its name,
# the tagline and the widest news line. They depend on the size only, not on what is typed or shown, so the rain is baked once.
declare -g _HOME_MASKSTR=""
_home_mask_cells() {
	local LC_ALL=C.UTF-8
	local w=$_HOME_W h=$_HOME_H top x tip widest=0 r c i
	local -a rect
	top=$(((h - 11) / 2))
	x=$(((w - 19) / 2))
	for tip in "${_HOME_TIPS[@]}"; do ((${#tip} > widest)) && widest=${#tip}; done
	_home_tagline "$w"
	rect=("$((x - 3))" "$((top - 1))" 25 8
		"$(((w - ${#_HT_TAG} - 15) / 2 - 2))" "$((top + 8))" "$((${#_HT_TAG} + 19))" 1
		"$(((w - widest - 9) / 2 - 2))" "$((top + 9))" "$((widest + 13))" 1)
	_HOME_MASKSTR=""
	for ((i = 0; i < ${#rect[@]}; i += 4)); do
		for ((r = rect[i + 1]; r < rect[i + 1] + rect[i + 3]; r++)); do
			((r >= 0 && r < h)) || continue
			for ((c = rect[i]; c < rect[i] + rect[i + 2]; c++)); do
				((c >= 0 && c < w)) && _HOME_MASKSTR+="$((r * _HOME_STRIDE + c)) "
			done
		done
	done
}

# _home_pills_part TIP - the tagline, the badge and the news line TIP, each on a background from the theme (.home_tag,
# .home_badge, .home_new, .home_news), with a blank margin: built once per news line and size
_home_pills_part() {
	local LC_ALL=C.UTF-8
	local w=$_HOME_W top tag news a tag_sgr badge_sgr new_sgr news_sgr
	[[ -n "${_HOME_CACHED[p$1]:-}" ]] && return 0
	_HOME_TXT_I=() _HOME_TXT_V=()
	top=$(((_HOME_H - 11) / 2))
	_home_class_sgr home_tag $'\e[38;2;225;232;245;48;2;38;44;66m'
	tag_sgr="$_HS"
	_home_class_sgr home_badge $'\e[30;48;2;255;243;168m'
	badge_sgr="$_HS"
	_home_class_sgr home_new $'\e[1;30;48;2;255;140;191m'
	new_sgr="$_HS"
	_home_class_sgr home_news $'\e[38;2;168;216;255;48;2;38;44;66m'
	news_sgr="$_HS"
	_home_tagline "$w"
	tag="$_HT_TAG"
	news="${_HOME_TIPS[$1]}"
	((_HOME_RAIN)) && {
		_home_clear $(((w - ${#tag} - 15) / 2 - 2)) $((top + 8)) $((${#tag} + 19)) 1
		_home_clear $(((w - ${#news} - 9) / 2 - 2)) $((top + 9)) $((${#news} + 13)) 1
	}
	a=$(((w - ${#tag} - 15) / 2)) # the tagline and the badge, as pills
	_home_pill "$a" $((top + 8)) "$tag_sgr" " $tag "
	_home_pill $((a + ${#tag} + 3)) $((top + 8)) "$badge_sgr" " experimental "
	a=$(((w - ${#news} - 9) / 2)) # the news: a badge and a line
	_home_pill "$a" $((top + 9)) "$new_sgr" " NEW "
	_home_pill $((a + 5)) $((top + 9)) "$news_sgr" " $news "
	_home_cache_part "p$1"
}

# _home_text_layer - the cells over the rain: the cached banner for the present glint, the cached pills for the present news
# line, and the typed name (each word in its letter's colour; 19 cells wide like the banner, starting under the D) with its
# cursor, which is the only part built every time
_home_text_layer() {
	local LC_ALL=C.UTF-8
	local i j x top typed=$_HOME_TYPED take word
	_home_banner_part "$_HOME_GLINT"
	_home_pills_part "$_HOME_TIP"
	local -n _bi="_HC_I_b$_HOME_GLINT" _bv="_HC_V_b$_HOME_GLINT" _pi="_HC_I_p$_HOME_TIP" _pv="_HC_V_p$_HOME_TIP"
	_HOME_TXT_I=("${_bi[@]}" "${_pi[@]}")
	_HOME_TXT_V=("${_bv[@]}" "${_pv[@]}")
	_HOME_NB=${#_bi[@]} _HOME_NP=${#_pi[@]} # the banner cells come first, then the pills: _home_text_apply skips the pills when the news did not turn
	top=$(((_HOME_H - 11) / 2))
	x=$(((_HOME_W - 19) / 2))
	j=$x
	for i in "${!_HOME_WORDS[@]}"; do
		word="${_HOME_WORDS[i]}"
		take=${#word}
		((take > typed)) && take=$typed
		((take > 0)) && _home_put "$j" $((top + 6)) $'\e[1;38;2;'"${_HOME_RGB[i]}m" "${word:0:take}"
		typed=$((typed - take))
		j=$((j + ${#word}))
	done
	((_HOME_CURSOR)) && _home_put "$((x + _HOME_TYPED))" $((top + 6)) $'\e[7m' "▌"
}

# _home_text_apply - the text layer onto the grid: the cells of the last one are blanked (for one paint, then they are skip cells
# again), the new ones drawn. Only when the text changed. While the frame on screen is the grid as it stands (tui.canvas.fresh),
# the cells that differ are also listed in _HOME_CHG, which _home_paint sends instead of the whole canvas.
declare -gA _HOME_CHG=()
declare -gi _HOME_PATCH=0 _HOME_NB=0 _HOME_NP=0 _HOME_PNB=0 _HOME_PNP=0 _HOME_PTIP=-1 # the banner / pill counts and the news line of the last text layer
_home_text_apply() {
	local i s n pn=${#_HOME_TXTPREV[@]} fresh=$_HOME_DIRTY
	local -a seg=() pseg=() # [from, to) ranges of the new and the last cells that are looked at
	local -A nv=()
	_home_text_layer
	n=${#_HOME_TXT_I[@]}
	_HOME_CHG=()
	_HOME_PATCH=0
	seg=(0 "$n") pseg=(0 "$pn")
	if ((! fresh)) && tui.canvas.fresh; then
		_HOME_PATCH=1
		# the pills (tagline, badge, news) are most of the cells and change only when the news turns: left out of everything below
		((_HOME_TIP == _HOME_PTIP && _HOME_NP == _HOME_PNP)) && {
			seg=(0 "$_HOME_NB" "$((_HOME_NB + _HOME_NP))" "$n")
			pseg=(0 "$_HOME_PNB" "$((_HOME_PNB + _HOME_PNP))" "$pn")
		}
		for ((s = 0; s < ${#seg[@]}; s += 2)); do
			for ((i = seg[s]; i < seg[s + 1]; i++)); do nv[${_HOME_TXT_I[i]}]="${_HOME_TXT_V[i]}"; done
		done
		for ((s = 0; s < ${#pseg[@]}; s += 2)); do
			for ((i = pseg[s]; i < pseg[s + 1]; i++)); do
				[[ -n "${nv[${_HOME_TXTPREV[i]}]+x}" ]] || _HOME_CHG[${_HOME_TXTPREV[i]}]=" " # a cell the text left
			done
		done
		for i in "${!nv[@]}"; do [[ "${_HOME_CELL[i]}" == "${nv[$i]}" ]] || _HOME_CHG[$i]="${nv[$i]}"; done
	fi
	_HOME_PNB=$_HOME_NB _HOME_PNP=$_HOME_NP _HOME_PTIP=$_HOME_TIP
	for ((s = 0; s < ${#pseg[@]}; s += 2)); do
		for ((i = pseg[s]; i < pseg[s + 1]; i++)); do
			_HOME_CELL[_HOME_TXTPREV[i]]=" "
			_HOME_FADE+=("${_HOME_TXTPREV[i]}")
		done
	done
	for ((s = 0; s < ${#seg[@]}; s += 2)); do
		for ((i = seg[s]; i < seg[s + 1]; i++)); do _HOME_CELL[_HOME_TXT_I[i]]="${_HOME_TXT_V[i]}"; done
	done
	_HOME_TXTPREV=("${_HOME_TXT_I[@]}")
	_HOME_DIRTY=0
	((fresh)) && _home_publish
}

# _home_patch_bytes -> _HP: the cells in _HOME_CHG as cursor moves, a run of neighbours under one move, each in the pane's style
_home_patch_bytes() {
	local i r c lo hi start v seg sty res=$'\e[0m' run
	local -A cell=() rmin=() rmax=()
	_HP=""
	((${#_HOME_CHG[@]})) || return 0
	_tui._content_rect home_hero
	_tui._style_v home_hero_normal
	sty="$_SGR"
	for i in "${!_HOME_CHG[@]}"; do
		r=$((i / _HOME_STRIDE)) c=$((i % _HOME_STRIDE))
		cell[$r,$c]="${_HOME_CHG[$i]}"
		((${rmin[$r]:-9999} <= c)) || rmin[$r]=$c
		((${rmax[$r]:--1} >= c)) || rmax[$r]=$c
	done
	for r in "${!rmin[@]}"; do
		start=-1 run="" lo=${rmin[$r]} hi=${rmax[$r]}
		for ((c = lo; c <= hi + 1; c++)); do
			if ((c <= hi)) && [[ -n "${cell[$r,$c]+x}" ]]; then
				((start >= 0)) || start=$c
				v="${cell[$r,$c]}"
				run+="${v//"$res"/"$res$sty"}"
			elif ((start >= 0)); then
				printf -v seg '\e[%d;%dH%s%s%s' $((_CR_R + r)) $((_CR_C + start)) "$sty" "$run" "$res"
				_HP+="$seg"
				start=-1 run=""
			fi
		done
	done
}

# _home_raw PANE - the whole frame from the grid (tui.canvas.source: a page render, a resize or a layer closing paints it all)
_home_raw() {
	local text
	printf -v text '%s' "${_HOME_CELL[@]}"
	_TUI_PANE_RAW[$1]="${text%$'\n'}"
}

# _home_paint - the cells that changed as one small write while the screen still shows the grid, else the grid as one frame (every
# row ends in its own reset and newline, so it is a single join)
_home_paint() {
	local i
	if ((_HOME_PATCH)) && tui.canvas.fresh; then
		_home_patch_bytes
		tui.canvas.patch home_hero "$_HP"
	else
		printf -v _HR_TEXT '%s' "${_HOME_CELL[@]}"
		tui.set_canvas home_hero "${_HR_TEXT%$'\n'}"
	fi
	_HOME_PATCH=0
	for i in "${_HOME_FADE[@]}"; do [[ "${_HOME_CELL[i]}" == " " ]] && _HOME_CELL[i]="$_HOME_SKIP"; done
	_HOME_FADE=()
}

# _home_publish - tells the rain painter where the hero is, which cells it must leave alone and the pane's style: a new size, which
# makes it bake the rain again
_home_publish() {
	tui.async.active home_rain || return 0
	_tui._content_rect home_hero
	_tui._style_v home_hero_normal
	tui.async.put home_rain rect "$_CR_R $_CR_C $_HOME_W $_HOME_H $_HOME_STRIDE"
	tui.async.put home_rain mask "$_HOME_MASKSTR"
	tui.async.put home_rain style "$_SGR"
	tui.async.put home_rain ver "$((++_HOME_VER))"
}

# ── the timers (main loop) ────────────────────────────────────────────────

# _home_type_tick - one character per tick, fast like someone who knows the prompt: now and then a hesitation of a tick, a
# short stop between words. When the name is complete this timer gives way to the slow one (cursor and glint).
_home_type_tick() {
	local w acc=0
	_home_size || return 0
	if ((_HOME_WAIT > 0)); then
		((_HOME_WAIT--))
		return 0
	fi
	_HOME_TYPED=$((_HOME_TYPED + 1))
	_HOME_CURSOR=1
	_HOME_WAIT=$(((_HOME_TYPED * 7) % 5 == 0 ? 1 : 0)) # an occasional hesitation
	for w in "${_HOME_WORDS[@]}"; do
		acc=$((acc + ${#w}))
		((_HOME_TYPED == acc)) && _HOME_WAIT=2 # a word is done
	done
	_home_text_apply
	_home_paint
	if ((_HOME_TYPED >= _HOME_LEN)); then
		tui.every.cancel home_type_job
		tui.every 0.35 _home_idle_tick home_idle_job
	fi
	return 0
}

# _home_idle_tick - the finished name: the cursor blinks (one change every two ticks) and a white glint travels over the letters
_home_idle_tick() {
	_home_size || return 0
	((++_HOME_BLINK % 2)) || _HOME_CURSOR=$((1 - _HOME_CURSOR)) # the cursor changes every other tick: half the speed of the glint
	_HOME_GLINT=$(((_HOME_GLINT + 1) % 6))                      # 0-3 a letter, 4-5 none
	_home_text_apply
	_home_paint
}

# _home_tip_tick - the next line of news (every 4 s)
_home_tip_tick() {
	_home_size || return 0
	_HOME_TIP=$(((_HOME_TIP + 1) % ${#_HOME_TIPS[@]}))
	_home_text_apply
	_home_paint
}

# _home_on_resize - after a resize the pane has a new size: the grid and the painter's rectangle follow at once, and the rain
# painter starts if the pane was too small for it before
_home_on_resize() {
	_home_size || return 0
	((_HOME_DIRTY)) && {
		_home_text_apply
		_home_paint
	}
	tui.async.active home_rain || { ((_HOME_RAIN)) && _home_rain_start; }
}

_home_rain_start() {
	_home_publish_first
	tui.async.start home_rain _home_rain_child
}

# the first publication happens before the painter exists: the files must be there when it starts
_home_publish_first() {
	_tui._content_rect home_hero
	_tui._style_v home_hero_normal
	tui.async.put home_rain rect "$_CR_R $_CR_C $_HOME_W $_HOME_H $_HOME_STRIDE"
	tui.async.put home_rain mask "$_HOME_MASKSTR"
	tui.async.put home_rain style "$_SGR"
	tui.async.put home_rain ver "$((++_HOME_VER))"
}

# ── the rain painter (a process of its own) ───────────────────────────────
#
# The rain is a pure function of the tick T and repeats exactly every _HR_L ticks, so it is baked: the first pass draws and keeps
# each frame (the changes since the one before) as it plays, and every pass after that sends the kept string and calculates
# nothing. A column has a start row, a speed (1-3 ticks a row) and a tail length for good; its head is at (start + T / speed)
# mod _HR_ROWS, and the letters shimmer with T / 3 mod 12. _HR_ROWS is a multiple of 6 and _HR_L = 6 * _HR_ROWS, so every speed, and the
# shimmer, come round together at _HR_L. The text covers fixed rectangles (_home_mask_cells), so what is baked never depends on
# the text: it is baked again only for a new size.

declare -gi _HR_ROWS=0 _HR_L=0
declare -ga _HR_Y0=() _HR_FR=()
declare -gA _HR_NOW=()

# _home_rain_init - the columns of a grid of _HOME_W x _HOME_H, the loop length and an empty bake (the same every run)
_home_rain_init() {
	local c
	_HOME_SEED=7
	_HR_Y0=() _HR_SP=() _HR_LEN=() _HR_FR=() _HR_PREV=() _HR_NOW=()
	_HR_ROWS=$((((2 * _HOME_H + 8 + 5) / 6) * 6)) # a column is idle for about a screen between two drops
	_HR_L=$((6 * _HR_ROWS))
	for ((c = 0; c < _HOME_W; c += 2)); do
		_home_rand "$_HR_ROWS"
		_HR_Y0[c]=$_HR_R
		_home_rand 3
		_HR_SP[c]=$((_HR_R + 1))
		_home_rand 5
		_HR_LEN[c]=$((_HR_R + 4))
	done
}

# _home_rain_state T -> _HR_NOW: the cell index -> the cell the rain has at tick T, outside the mask (_HR_MASK)
_home_rain_state() {
	local w=$_HOME_W h=$_HOME_H st=$_HOME_STRIDE c y len k kmax r idx pb base n=${#_HR_CH[@]} sh=$(($1 / 3 % 12))
	_HR_NOW=()
	for ((c = 0; c < w; c += 2)); do
		y=$(((_HR_Y0[c] + $1 / _HR_SP[c]) % _HR_ROWS))
		len=${_HR_LEN[c]} pb=$((c / 2 % 4 * 6)) base=$((c * 7 + sh))
		for ((k = y >= h ? y - h + 1 : 0, kmax = y < len ? y : len - 1; k <= kmax; k++)); do # only the cells of the tail that are on screen
			r=$((y - k))
			idx=$((r * st + c))
			[[ -n "${_HR_MASK[$idx]:-}" ]] && continue
			_HR_NOW[$idx]="${_HR_PAL[pb + _HR_STEP[len * 10 + k]]}${_HR_CH[(base + r * 13) % n]}"
		done
	done
}

# _home_rain_frame ROW0 COL0 STYLE - the frame for tick _HOME_DT as a string of cursor moves and cells -> _HR_OUT: only what
# changed since the last call (_HR_PREV), a cell the rain left blanked. STYLE comes first.
declare -g _HR_OUT=""
declare -gA _HR_MASK=() _HR_PREV=()
_home_rain_frame() {
	local st=$_HOME_STRIDE idx
	_home_rain_state "$_HOME_DT"
	_HR_OUT=""
	for idx in "${!_HR_NOW[@]}"; do
		[[ "${_HR_PREV[$idx]:-}" == "${_HR_NOW[$idx]}" ]] || _HR_OUT+=$'\e['$(($1 + idx / st))';'$(($2 + idx % st))'H'"${_HR_NOW[$idx]}"
	done
	for idx in "${!_HR_PREV[@]}"; do # what the last frame drew and this one does not
		[[ -n "${_HR_NOW[$idx]:-}" ]] || _HR_OUT+=$'\e['$(($1 + idx / st))';'$(($2 + idx % st))'H '
	done
	_HR_PREV=()
	for idx in "${!_HR_NOW[@]}"; do _HR_PREV[$idx]="${_HR_NOW[$idx]}"; done
	[[ -n "$_HR_OUT" ]] && _HR_OUT="$3$_HR_OUT"
	return 0
}

# _home_rain_full ROW0 COL0 STYLE - every cell of _HR_NOW as one frame -> _HR_OUT: for the first frame after something covered
# the page, when what is on screen is not known
_home_rain_full() {
	local st=$_HOME_STRIDE idx
	_HR_OUT="$3"
	for idx in "${!_HR_NOW[@]}"; do _HR_OUT+=$'\e['$(($1 + idx / st))';'$(($2 + idx % st))'H'"${_HR_NOW[$idx]}"; done
	return 0
}

# _home_rain_child - the painter's loop. It reads what the main loop published when the version changes, stops drawing while
# something is open over the page (and starts again from a full frame), and ends when the main process does. Per tick: while
# the first pass is on, the frame is made and kept (_home_rain_frame); after it, the kept one is sent.
_home_rain_child() {
	local ver="" cur rect mask sty r0 c0 st i t=0 k synced=0 baked=0 wrapped=0 out gen lastgen=""
	local -a m
	while kill -0 "$_TUI_ASYNC_PARENT" 2>/dev/null; do
		tui.async.get home_rain.ver cur
		if [[ "$cur" != "$ver" ]]; then # a new size: start from a clean frame and bake again
			ver="$cur"
			tui.async.get home_rain.rect rect
			tui.async.get home_rain.mask mask
			tui.async.get home_rain.style sty
			read -r r0 c0 _HOME_W _HOME_H st <<<"$rect"
			_HOME_STRIDE=${st:-1}
			_HR_MASK=()
			read -ra m <<<"$mask"
			for i in "${m[@]}"; do _HR_MASK[$i]=1; done
			_home_rain_init
			t=0 synced=0 baked=0 wrapped=0
		fi
		if tui.async.covered; then
			synced=0 # whatever was drawn is under the overlay or gone: a full frame when it closes
			tui.async.wait 0.1
			continue
		fi
		tui.async.get gen gen
		if [[ "$gen" != "$lastgen" ]]; then # the main loop wrote since the last tick (a highlight, a repaint): the tick is its
			lastgen="$gen"                     # own. The rain holds where it is, so the next frame still follows the one on screen.
			tui.async.wait 0.03
			continue
		fi
		if [[ -n "$rect" ]]; then
			k=$((t % _HR_L))
			if ((baked < _HR_L)); then # the first pass: make this frame and keep it
				_HOME_DT=$t
				_home_rain_frame "$r0" "$c0" "$sty"
				_HR_FR[k]="$_HR_OUT"
				((++baked))
				out="$_HR_OUT"
				((synced)) || {
					_home_rain_full "$r0" "$c0" "$sty"
					out="$_HR_OUT"
				}
			else
				if ((! wrapped && k == 0)); then # frame 0 as it follows the last one (the first pass drew it from an empty screen)
					_HOME_DT=$_HR_L
					_home_rain_frame "$r0" "$c0" "$sty"
					_HR_FR[0]="$_HR_OUT"
					wrapped=1
				fi
				out="${_HR_FR[k]}"
				((synced)) || {
					_home_rain_state "$k"
					_home_rain_full "$r0" "$c0" "$sty"
					out="$_HR_OUT"
				}
			fi
			synced=1
			[[ -n "$out" ]] && tui.async.emit "$out" "$sty"
			((t++))
		fi
		tui.async.wait 0.03
	done
}

on_home_visit() {
	_HOME_TYPED=0 _HOME_WAIT=12 _HOME_CURSOR=1 _HOME_GLINT=4 _HOME_DT=0 _HOME_BLINK=0 _HOME_TIP=0 _HOME_SEED=7 _HOME_W=0 _HOME_H=0 _HOME_VER=0 # DABT stands alone for a moment
	_TUI_ON_RESIZE_FN=_home_on_resize
	tui.canvas.source home_hero _home_raw
	if _home_size; then
		_home_text_apply
		_home_paint
		((_HOME_RAIN)) && _home_rain_start
	fi
	tui.every 0.04 _home_type_tick home_type_job
	tui.every 4 _home_tip_tick home_tip_job
	tui.set_label lbl_footer "DinosAmazingBashTui v${TUI_VERSION}"
}
