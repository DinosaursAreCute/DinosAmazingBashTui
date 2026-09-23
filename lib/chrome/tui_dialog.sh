#!/usr/bin/env bash
# tui_dialog.sh - dialogs, prompts, choosers and toast notifications, built on the overlay/modal layer (tui_modal.sh).
#
# CALLBACK STYLE: bash cannot block the UI loop, so a dialog returns at once and calls YOUR function when the user
# answers (after the dialog is gone and the screen repainted, so the callback may open the next dialog, change page...).
# A CMD below is a function name plus optional fixed args ("do_delete file1"); it may chain with ';' for confirm.
#
#   tui.confirm  MESSAGE [ON_YES [ON_NO]] [flags]      Yes / No.      Esc, n = No.  y = Yes.  Enter = the selected button
#   tui.message  MESSAGE [ON_CLOSE] [flags]            OK only.
#   tui.prompt   MESSAGE ON_SUBMIT [flags]             one-line editor. ON_SUBMIT gets the text as its last arg.
#   tui.choose   TITLE ON_CHOOSE ITEM... [flags]       list picker.     ON_CHOOSE gets INDEX (0-based) and ITEM.
#   flags (any dialog):  --title T   --width N   --ok L   --yes L   --no L   --danger (red primary)   --default yes|no
#   flags (prompt):      --value TEXT   --placeholder TEXT   --validate FN   --cancel CMD
#                        FN VALUE returns non-zero to reject; it may set TUI_DIALOG_ERROR to say why (shown, dialog stays)
#   flags (choose):      --message TEXT   --cancel CMD   --selected N
#   tui.view     TITLE TEXT [flags]                   scrollable read-only text (help screens). Up/Down/PgUp/PgDn/Home/End,
#                                                     wheel; Esc / q / Enter close. flags: --width N  --close CMD
#   tui.dialog.close                                   dismiss the open dialog without calling anything
#   tui.dialog.active                                  rc 0 while a dialog is open
#   TUI_DIALOG_RESULT                                  yes | no | ok | submit | cancel | choose  (set before the callback runs)
#
#   tui.notify MESSAGE [LEVEL] [SECONDS]               toast (bottom-right above the footer unless moved). LEVEL info|success|warn|error
#                                                      (default info), SECONDS default 4, 0 = stays until cleared. -> TUI_NOTIFY_ID
#   tui.notify.clear [ID]                              dismiss one toast, or all
#   tui.notify.position [POS]                          where toasts appear: bottom-right (default) bottom-left bottom-center
#                                                      top-right top-left top-center. No argument prints it. Persist with
#                                                      tui.config.set notify.position POS (the default Settings page does)
#   tui.notify.seconds [N]                             default lifetime (default 5); persisted as notify.seconds
#   tui.notify.count                                   number of toasts showing
#
# Theme classes (fall back to built-in colours): .dialog .dialog_title .dialog_btn .dialog_btn_sel .dialog_danger
#   .dialog_dim .dialog_error   and for toasts  .toast .toast_success .toast_warn .toast_error
# One dialog at a time: opening a dialog while another is open replaces it. Toasts and dialogs never survive a page
# change except toasts, which keep their remaining time.

declare -g TUI_DIALOG_RESULT="" TUI_DIALOG_ERROR="" TUI_NOTIFY_ID=0
declare -g TUI_TOAST_MAX=5 TUI_TOAST_WIDTH=46 TUI_TOAST_SECONDS=5 TUI_TOAST_POSITION=bottom-right

# ── shared helpers ───────────────────────────────────────────────────────

# _tui_dialog.pad TEXT WIDTH -> _PADS (cut / padded to exactly WIDTH chars)
_tui_dialog.pad() {
	local s="${1:0:$2}" sp
	printf -v sp '%*s' "$(($2 - ${#s}))" ''
	_PADS="$s$sp"
}

# _tui_dialog.wrap TEXT WIDTH -> _WRAP (array). Newlines kept, words never split unless longer than WIDTH.
_tui_dialog.wrap() {
	local text="$1" w="$2" para word line
	_WRAP=()
	((w < 4)) && w=4
	while IFS= read -r para || [[ -n "$para" ]]; do
		line=""
		for word in $para; do
			while ((${#word} > w)); do
				[[ -n "$line" ]] && {
					_WRAP+=("$line")
					line=""
				}
				_WRAP+=("${word:0:w}")
				word="${word:w}"
			done
			if [[ -z "$line" ]]; then
				line="$word"
			elif ((${#line} + 1 + ${#word} <= w)); then
				line+=" $word"
			else
				_WRAP+=("$line")
				line="$word"
			fi
		done
		_WRAP+=("$line")
	done <<<"$text"
}

# _tui_dialog.call CMD [ARG...]: CMD is "fn fixed args"; extra ARGs are appended
_tui_dialog.call() {
	local cmd="$1"
	shift
	[[ -n "$cmd" ]] || return 0
	local -a words
	read -ra words <<<"$cmd"
	((${#words[@]})) || return 0
	if declare -F "${words[0]}" >/dev/null; then
		"${words[@]}" "$@"
	else TUI_LAST_BIND_ERROR="no such command: ${words[0]}"; fi
}

# resolve a theme class to an SGR string with a built-in fallback: _tui_dialog.sgr CLASS FALLBACK -> _SG
_tui_dialog.sgr() {
	tui.class.sgr "$1"
	_SG="${TUI_SGR:-$2}"
}

declare -g _DLG_SGR_BOX="" _DLG_SGR_TITLE="" _DLG_SGR_BTN="" _DLG_SGR_SEL="" _DLG_SGR_DANGER="" _DLG_SGR_DIM="" _DLG_SGR_ERR=""
_tui_dialog.styles() {
	_tui_dialog.sgr dialog $'\e[0;97;48;2;30;34;52m'
	_DLG_SGR_BOX="$_SG"
	_tui_dialog.sgr dialog_title $'\e[1;97;48;2;30;34;52m'
	_DLG_SGR_TITLE="$_SG"
	_tui_dialog.sgr dialog_btn $'\e[0;97;48;2;62;68;92m'
	_DLG_SGR_BTN="$_SG"
	_tui_dialog.sgr dialog_btn_sel $'\e[1;30;48;2;97;175;239m'
	_DLG_SGR_SEL="$_SG"
	_tui_dialog.sgr dialog_danger $'\e[1;97;48;2;176;0;32m'
	_DLG_SGR_DANGER="$_SG"
	_tui_dialog.sgr dialog_dim $'\e[2;37;48;2;30;34;52m'
	_DLG_SGR_DIM="$_SG"
	_tui_dialog.sgr dialog_error $'\e[1;91;48;2;30;34;52m'
	_DLG_SGR_ERR="$_SG"
}

# ── dialog state ─────────────────────────────────────────────────────────
declare -g _DLG_KIND="" _DLG_TITLE="" _DLG_MSG="" _DLG_WIDTH=0 _DLG_DANGER=0 _DLG_DEFAULT=""
declare -ga _DLG_BTN=() _DLG_BTN_ID=() # button labels / result ids
declare -g _DLG_SEL=0                  # selected button (confirm/message) or list row (choose)
declare -g _DLG_ON_YES="" _DLG_ON_NO="" _DLG_ON_SUBMIT="" _DLG_ON_CANCEL="" _DLG_VALIDATE=""
declare -g _DLG_VAL="" _DLG_CUR=0 _DLG_OFF=0 _DLG_PH="" _DLG_ERR=""
declare -ga _DLG_ITEMS=()
declare -g _DLG_TOP=0 _DLG_ROWS=0
declare -g _DLG_X=0 _DLG_Y=0 _DLG_W=0 _DLG_H=0 _DLG_BROW=0 _DLG_LROW=0
declare -ga _DLG_BLO=() _DLG_BHI=() # button x ranges from the last draw

tui.view() {
	_tui_dialog.parse "$@"
	_DLG_KIND=view
	_DLG_TITLE="${_POS[0]:-View}"
	_DLG_ON_CANCEL="${_DLG_ON_CANCEL:-}"
	_DLG_ITEMS=()
	local l
	while IFS= read -r l || [[ -n "$l" ]]; do _DLG_ITEMS+=("$l"); done <<<"${_POS[1]:-}"
	_DLG_BTN=()
	_DLG_BTN_ID=()
	_DLG_SEL=0
	_DLG_TOP=0
	_tui_dialog.open
}

tui.dialog.active() { tui.modal.active dialog; }
tui.dialog.close() {
	tui.modal.active dialog && tui.modal.close
	return 0
}

# _tui_dialog.parse ARGS... : flags into _DLG_*, positionals into _POS
_tui_dialog.parse() {
	_POS=()
	_DLG_TITLE=""
	_DLG_WIDTH=0
	_DLG_DANGER=0
	_DLG_DEFAULT=""
	_DLG_VAL=""
	_DLG_PH=""
	_DLG_VALIDATE=""
	_DLG_ON_CANCEL=""
	_DLG_MSG=""
	_DLG_YES_L="Yes"
	_DLG_NO_L="No"
	_DLG_OK_L="OK"
	_DLG_SEL0=0
	while (($#)); do
		case "$1" in
			--title)
				_DLG_TITLE="$2"
				shift
				;;
			--width)
				_DLG_WIDTH="$2"
				shift
				;;
			--ok)
				_DLG_OK_L="$2"
				shift
				;;
			--yes)
				_DLG_YES_L="$2"
				shift
				;;
			--no)
				_DLG_NO_L="$2"
				shift
				;;
			--danger) _DLG_DANGER=1 ;;
			--default)
				_DLG_DEFAULT="$2"
				shift
				;;
			--value)
				_DLG_VAL="$2"
				shift
				;;
			--placeholder)
				_DLG_PH="$2"
				shift
				;;
			--validate)
				_DLG_VALIDATE="$2"
				shift
				;;
			--cancel)
				_DLG_ON_CANCEL="$2"
				shift
				;;
			--message)
				_DLG_MSG="$2"
				shift
				;;
			--selected)
				_DLG_SEL0="$2"
				shift
				;;
			*) _POS+=("$1") ;;
		esac
		shift
	done
}

_tui_dialog.open() {
	((_TUI_RUNNING)) || return 0
	_tui_dialog.styles
	_DLG_ERR=""
	_DLG_TOP=0
	tui.modal.open dialog _tui_dialog.key _tui_dialog.draw _tui_dialog.mouse
}

# finish: close (repaints the screen), then run the callback
_tui_dialog.finish() { # RESULT CMD [ARG...]
	local result="$1" cmd="$2"
	shift 2
	tui.modal.close
	TUI_DIALOG_RESULT="$result"
	_tui_dialog.call "$cmd" "$@"
}

# ── public constructors ──────────────────────────────────────────────────

tui.confirm() {
	_tui_dialog.parse "$@"
	_DLG_KIND=confirm
	_DLG_MSG="${_POS[0]:-Are you sure?}"
	_DLG_ON_YES="${_POS[1]:-}"
	_DLG_ON_NO="${_POS[2]:-}"
	[[ -n "$_DLG_TITLE" ]] || { ((_DLG_DANGER)) && _DLG_TITLE="Warning" || _DLG_TITLE="Confirm"; }
	_DLG_BTN=("$_DLG_YES_L" "$_DLG_NO_L")
	_DLG_BTN_ID=(yes no)
	_DLG_SEL=0
	[[ "$_DLG_DEFAULT" == no ]] && _DLG_SEL=1
	((_DLG_DANGER)) && [[ -z "$_DLG_DEFAULT" ]] && _DLG_SEL=1 # a destructive action defaults to the safe answer
	_tui_dialog.open
}

tui.message() {
	_tui_dialog.parse "$@"
	_DLG_KIND=message
	_DLG_MSG="${_POS[0]:-}"
	_DLG_ON_YES="${_POS[1]:-}"
	_DLG_ON_NO=""
	[[ -n "$_DLG_TITLE" ]] || _DLG_TITLE="Message"
	_DLG_BTN=("$_DLG_OK_L")
	_DLG_BTN_ID=(ok)
	_DLG_SEL=0
	_tui_dialog.open
}

tui.prompt() {
	_tui_dialog.parse "$@"
	_DLG_KIND=prompt
	_DLG_MSG="${_POS[0]:-}"
	_DLG_ON_SUBMIT="${_POS[1]:-}"
	[[ -n "$_DLG_TITLE" ]] || _DLG_TITLE="Input"
	_DLG_BTN=("$_DLG_OK_L" "Cancel")
	_DLG_BTN_ID=(submit cancel)
	_DLG_SEL=0
	_TUI_W_TYPE[__dlg]=input
	_TUI_W_VALUE[__dlg]="$_DLG_VAL"
	_TXC[__dlg]=${#_DLG_VAL}
	_TXA[__dlg]=-1
	_TXS[__dlg]=0
	_tui_dialog.open
}

tui.choose() {
	_tui_dialog.parse "$@"
	_DLG_KIND=choose
	_DLG_TITLE="${_POS[0]:-Choose}"
	_DLG_ON_SUBMIT="${_POS[1]:-}"
	_DLG_ITEMS=("${_POS[@]:2}")
	((${#_DLG_ITEMS[@]})) || return 1
	_DLG_BTN=()
	_DLG_BTN_ID=()
	_DLG_SEL=$_DLG_SEL0
	((_DLG_SEL >= ${#_DLG_ITEMS[@]})) && _DLG_SEL=0
	_tui_dialog.open
}

# ── keys ─────────────────────────────────────────────────────────────────

_tui_dialog.press() { # button index
	local id="${_DLG_BTN_ID[$1]}"
	case "$_DLG_KIND:$id" in
		confirm:yes) _tui_dialog.finish yes "$_DLG_ON_YES" ;;
		confirm:no) _tui_dialog.finish no "$_DLG_ON_NO" ;;
		message:ok) _tui_dialog.finish ok "$_DLG_ON_YES" ;;
		prompt:submit) _tui_dialog.submit ;;
		prompt:cancel) _tui_dialog.finish cancel "$_DLG_ON_CANCEL" ;;
	esac
}

_tui_dialog.submit() {
	if [[ -n "$_DLG_VALIDATE" ]]; then
		TUI_DIALOG_ERROR=""
		if ! _tui_dialog.call "$_DLG_VALIDATE" "$_DLG_VAL"; then
			_DLG_ERR="${TUI_DIALOG_ERROR:-Invalid input}"
			tui.modal.redraw
			return
		fi
	fi
	local v="$_DLG_VAL"
	_tui_dialog.finish submit "$_DLG_ON_SUBMIT" "$v"
}

_tui_dialog.key() {
	local k="$1" n
	case "$_DLG_KIND" in
		confirm | message)
			case "$k" in
				y) [[ "$_DLG_KIND" == confirm ]] && {
					_tui_dialog.press 0
					return
				} ;;
				n) [[ "$_DLG_KIND" == confirm ]] && {
					_tui_dialog.press 1
					return
				} ;;
				esc | ctrl+g)
					if [[ "$_DLG_KIND" == confirm ]]; then _tui_dialog.press 1; else _tui_dialog.press 0; fi
					return
					;;
				enter | space)
					_tui_dialog.press "$_DLG_SEL"
					return
					;;
				left | shift+tab | up | h) ((_DLG_SEL > 0)) && ((_DLG_SEL--)) ;;
				right | tab | down | l) ((_DLG_SEL < ${#_DLG_BTN[@]} - 1)) && ((_DLG_SEL++)) ;;
			esac
			;;
		prompt)
			case "$k" in
				esc | ctrl+g)
					_tui_dialog.press 1
					return
					;;
				enter)
					_DLG_VAL="${_TUI_W_VALUE[__dlg]}"
					_tui_dialog.submit
					return
					;;
				paste)
					tui.text.insert __dlg "$TUI_EVENT_PASTE" paste
					_DLG_ERR=""
					;;
				*) _tui_text.consumes __dlg "$k" && {
					_tui_text.key __dlg "$k"
					_DLG_ERR=""
				} ;;
			esac
			_DLG_VAL="${_TUI_W_VALUE[__dlg]}"
			;;
		view)
			n=${#_DLG_ITEMS[@]}
			case "$k" in
				esc | q | enter | ctrl+g)
					_tui_dialog.finish cancel "$_DLG_ON_CANCEL"
					return
					;;
				up | k) ((_DLG_TOP > 0)) && ((_DLG_TOP--)) ;;
				down | j) ((_DLG_TOP++)) ;;
				pgup) ((_DLG_TOP -= _DLG_ROWS)) ;;
				pgdn | space) ((_DLG_TOP += _DLG_ROWS)) ;;
				home) _DLG_TOP=0 ;;
				end) _DLG_TOP=$n ;;
			esac
			((_DLG_TOP < 0)) && _DLG_TOP=0
			((_DLG_TOP > n - _DLG_ROWS)) && _DLG_TOP=$((n - _DLG_ROWS))
			((_DLG_TOP < 0)) && _DLG_TOP=0
			;;
		choose)
			n=${#_DLG_ITEMS[@]}
			case "$k" in
				esc | ctrl+g | q)
					_tui_dialog.finish cancel "$_DLG_ON_CANCEL"
					return
					;;
				enter | space)
					_tui_dialog.finish choose "$_DLG_ON_SUBMIT" "$_DLG_SEL" "${_DLG_ITEMS[_DLG_SEL]}"
					return
					;;
				up | k | ctrl+p) ((_DLG_SEL > 0)) && ((_DLG_SEL--)) ;;
				down | j | ctrl+n) ((_DLG_SEL < n - 1)) && ((_DLG_SEL++)) ;;
				pgup)
					((_DLG_SEL -= _DLG_ROWS))
					((_DLG_SEL < 0)) && _DLG_SEL=0
					;;
				pgdn)
					((_DLG_SEL += _DLG_ROWS))
					((_DLG_SEL >= n)) && _DLG_SEL=$((n - 1))
					;;
				home) _DLG_SEL=0 ;;
				end) _DLG_SEL=$((n - 1)) ;;
				[1-9]) if ((k <= n)); then
					_tui_dialog.finish choose "$_DLG_ON_SUBMIT" "$((k - 1))" "${_DLG_ITEMS[k - 1]}"
					return
				fi ;;
			esac
			;;
	esac
	tui.modal.redraw
}

# ── mouse: EVENT X Y ─────────────────────────────────────────────────────

_tui_dialog.mouse() {
	local ev="$1" x="$2" y="$3" i n row
	case "$ev" in
		wheel:up) if [[ "$_DLG_KIND" == view ]]; then
			((_DLG_TOP > 0)) && {
				((_DLG_TOP -= 3))
				((_DLG_TOP < 0)) && _DLG_TOP=0
				tui.modal.redraw
			}
		else [[ "$_DLG_KIND" == choose ]] && ((_DLG_SEL > 0)) && {
			((_DLG_SEL--))
			tui.modal.redraw
		}; fi ;;
		wheel:down) if [[ "$_DLG_KIND" == view ]]; then
			((_DLG_TOP < ${#_DLG_ITEMS[@]} - _DLG_ROWS)) && {
				((_DLG_TOP += 3))
				tui.modal.redraw
			}
		else [[ "$_DLG_KIND" == choose ]] && ((_DLG_SEL < ${#_DLG_ITEMS[@]} - 1)) && {
			((_DLG_SEL++))
			tui.modal.redraw
		}; fi ;;
		mouse:left)
			if [[ "$_DLG_KIND" == view ]]; then
				((x < _DLG_X || x >= _DLG_X + _DLG_W || y < _DLG_Y || y >= _DLG_Y + _DLG_H)) && _tui_dialog.finish cancel "$_DLG_ON_CANCEL"
				return
			fi
			if [[ "$_DLG_KIND" == choose ]]; then
				if ((x >= _DLG_X && x < _DLG_X + _DLG_W && y >= _DLG_LROW && y < _DLG_LROW + _DLG_ROWS)); then
					i=$((_DLG_TOP + y - _DLG_LROW))
					((i < ${#_DLG_ITEMS[@]})) && _tui_dialog.finish choose "$_DLG_ON_SUBMIT" "$i" "${_DLG_ITEMS[i]}"
				fi
				return
			fi
			if ((y == _DLG_BROW)); then
				for ((i = 0; i < ${#_DLG_BTN[@]}; i++)); do
					((x >= _DLG_BLO[i] && x <= _DLG_BHI[i])) && {
						_tui_dialog.press "$i"
						return
					}
				done
			fi
			;;
	esac
}

# ── drawing ──────────────────────────────────────────────────────────────

_tui_dialog.draw_view() {
	local n=${#_DLG_ITEMS[@]} w i x y h out=$'\e7' bar hz inner line title tsg
	w=${_DLG_WIDTH:-0}
	if ((w <= 0)); then
		w=20
		for line in "${_DLG_ITEMS[@]}"; do ((${#line} + 4 > w)) && w=$((${#line} + 4)); done
	fi
	((w > _TUI_COLS - 2)) && w=$((_TUI_COLS - 2))
	((w < 20)) && w=20
	inner=$((w - 2))
	local rows=$n
	((rows > _TUI_ROWS - 6)) && rows=$((_TUI_ROWS - 6))
	((rows < 1)) && rows=1
	_DLG_ROWS=$rows
	((_DLG_TOP > n - rows)) && _DLG_TOP=$((n - rows))
	((_DLG_TOP < 0)) && _DLG_TOP=0
	h=$((rows + 4)) # top, rows, blank footer line, bottom (+ 1 padding)
	x=$(((_TUI_COLS - w) / 2 + 1))
	((x < 1)) && x=1
	y=$(((_TUI_ROWS - h) / 2))
	((y < 1)) && y=1
	_DLG_X=$x
	_DLG_Y=$y
	_DLG_W=$w
	_DLG_H=$h
	printf -v bar '%*s' "$inner" ''
	hz="${bar// /─}"
	title=" $_DLG_TITLE "
	out+="${_DLG_SGR_BOX}"$'\e['"${y};${x}H┌─${_DLG_SGR_TITLE}${title}${_DLG_SGR_BOX}${hz:0:$((inner - ${#title} - 1))}┐"
	local thumb=-1
	((n > rows)) && thumb=$((_DLG_TOP * (rows - 1) / (n - rows)))
	for ((i = 0; i < rows; i++)); do
		_tui_dialog.pad " ${_DLG_ITEMS[_DLG_TOP + i]:-}" "$((inner - 1))"
		local edge=" "
		((i == thumb)) && edge="▐"
		out+=$'\e['"$((y + 1 + i));${x}H${_DLG_SGR_BOX}│${_PADS}${edge}│"
	done
	_tui_dialog.pad " ↑↓ scroll   esc close   ${_DLG_TOP}-$((_DLG_TOP + rows)) of $n" "$inner"
	out+=$'\e['"$((y + rows + 1));${x}H${_DLG_SGR_DIM}│${_PADS}│"
	out+=$'\e['"$((y + rows + 2));${x}H${_DLG_SGR_BOX}└${hz}┘"$'\e[0m\e8'
	printf '%s' "$out"
}

_tui_dialog.draw() {
	tui.modal.active dialog || return 0
	[[ "$_DLG_KIND" == view ]] && {
		_tui_dialog.draw_view
		return 0
	}
	local inner w h i x y out=$'\e7' bar hz line
	local -a body=() # pre-styled, pre-padded inner lines
	w=${_DLG_WIDTH:-0}
	if ((w <= 0)); then
		w=$((${#_DLG_TITLE} + 8))
		((w < 36)) && w=36
		[[ "$_DLG_KIND" == choose ]] && for i in "${_DLG_ITEMS[@]}"; do ((${#i} + 8 > w)) && w=$((${#i} + 8)); done
		if [[ -n "$_DLG_MSG" ]] && ((${#_DLG_MSG} + 6 > w)); then w=$((${#_DLG_MSG} + 6)); fi
		((w > 64)) && w=64
	fi
	((w > _TUI_COLS - 2)) && w=$((_TUI_COLS - 2))
	((w < 20)) && w=20
	inner=$((w - 2))
	printf -v bar '%*s' "$inner" ''
	hz="${bar// /─}"

	_tui_dialog.wrap "$_DLG_MSG" "$((inner - 2))"
	local -a msg=("${_WRAP[@]}")
	[[ -z "$_DLG_MSG" ]] && msg=()

	body+=("${_DLG_SGR_BOX}${bar}") # top padding
	for line in "${msg[@]}"; do
		_tui_dialog.pad " $line" "$inner"
		body+=("${_DLG_SGR_BOX}${_PADS}")
	done

	local prompt_row=-1
	if [[ "$_DLG_KIND" == prompt ]]; then
		((${#msg[@]})) && body+=("${_DLG_SGR_BOX}${bar}")
		local avail=$((inner - 4)) c s
		_tui_text.norm __dlg
		c=${_TXC[__dlg]}
		s=${_TXS[__dlg]:-0}
		((c < s)) && s=$c
		((c >= s + avail)) && s=$((c - avail + 1))
		((s < 0)) && s=0
		_TXS[__dlg]=$s
		if [[ -z "$_DLG_VAL" && -n "$_DLG_PH" ]]; then
			_tui_dialog.pad "$_DLG_PH" "$((avail - 1))"
			line="${_DLG_SGR_BOX} ${_DLG_SGR_BTN} "$'\e[7m'" "$'\e[27m'"${_DLG_SGR_DIM}${_PADS}${_DLG_SGR_BTN} ${_DLG_SGR_BOX} "
		else
			local pa=-1 pb=-1
			if _tui_text.sel __dlg; then
				pa=$((_SA - s))
				pb=$((_SB - s))
				((pa < 0)) && pa=0
				((pb > avail)) && pb=$avail
			fi
			_tui_text.paint_v "${_DLG_VAL:s:avail}" "$pa" "$pb" "$((c - s))" "$avail" "$_DLG_SGR_BTN"
			line="${_DLG_SGR_BOX} ${_DLG_SGR_BTN} ${_PV} ${_DLG_SGR_BOX} "
		fi
		body+=("$line")
		prompt_row=${#body[@]}
		if [[ -n "$_DLG_ERR" ]]; then
			_tui_dialog.pad " $_DLG_ERR" "$inner"
			body+=("${_DLG_SGR_ERR}${_PADS}")
		else body+=("${_DLG_SGR_BOX}${bar}"); fi
	fi

	local list_first=-1
	if [[ "$_DLG_KIND" == choose ]]; then
		((${#msg[@]})) && body+=("${_DLG_SGR_BOX}${bar}")
		local n=${#_DLG_ITEMS[@]} rows=10 sel
		((rows > n)) && rows=$n
		((rows > _TUI_ROWS - 8)) && rows=$((_TUI_ROWS - 8))
		((rows < 1)) && rows=1
		_DLG_ROWS=$rows
		((_DLG_SEL < _DLG_TOP)) && _DLG_TOP=$_DLG_SEL
		((_DLG_SEL >= _DLG_TOP + rows)) && _DLG_TOP=$((_DLG_SEL - rows + 1))
		((_DLG_TOP < 0)) && _DLG_TOP=0
		list_first=${#body[@]}
		for ((i = 0; i < rows; i++)); do
			local idx=$((_DLG_TOP + i))
			if ((idx < n)); then
				local label="  "
				((idx < 9)) && label=" $((idx + 1))"
				_tui_dialog.pad "${label}  ${_DLG_ITEMS[idx]}" "$inner"
				if ((idx == _DLG_SEL)); then body+=("${_DLG_SGR_SEL}${_PADS}"); else body+=("${_DLG_SGR_BOX}${_PADS}"); fi
			fi
		done
		if ((n > rows)); then
			_tui_dialog.pad " ${_DLG_TOP}-$((_DLG_TOP + rows)) of $n   ↑↓ move   ⏎ pick   esc cancel" "$inner"
		else _tui_dialog.pad " ↑↓ move   ⏎ pick   esc cancel" "$inner"; fi
		body+=("${_DLG_SGR_DIM}${_PADS}")
	fi

	# buttons
	local btnrow=-1
	_DLG_BLO=()
	_DLG_BHI=()
	if ((${#_DLG_BTN[@]})); then
		body+=("${_DLG_SGR_BOX}${bar}")
		local total=0 b lbl
		for b in "${_DLG_BTN[@]}"; do ((total += ${#b} + 4 + 2)); done
		((total -= 2))
		local lead=$(((inner - total) / 2))
		((lead < 0)) && lead=0
		printf -v sp '%*s' "$lead" ''
		line="${_DLG_SGR_BOX}${sp}"
		local cx=$lead
		for ((i = 0; i < ${#_DLG_BTN[@]}; i++)); do
			lbl="[ ${_DLG_BTN[i]} ]"
			local sgr="$_DLG_SGR_BTN"
			if ((i == _DLG_SEL)); then
				if ((_DLG_DANGER && i == 0)) && [[ "$_DLG_KIND" == confirm ]]; then sgr="$_DLG_SGR_DANGER"; else sgr="$_DLG_SGR_SEL"; fi
			elif ((_DLG_DANGER && i == 0)) && [[ "$_DLG_KIND" == confirm ]]; then sgr="$_DLG_SGR_DANGER"; fi
			_DLG_BLO[i]=$((cx + 1))
			_DLG_BHI[i]=$((cx + ${#lbl})) # x offsets inside the frame; made absolute below
			line+="${sgr}${lbl}${_DLG_SGR_BOX}  "
			((cx += ${#lbl} + 2))
		done
		printf -v sp '%*s' "$((inner - cx))" ''
		((inner - cx < 0)) && sp=""
		line+="$sp"
		body+=("$line")
		btnrow=${#body[@]}
	fi
	body+=("${_DLG_SGR_BOX}${bar}") # bottom padding

	h=$((${#body[@]} + 2))
	x=$(((_TUI_COLS - w) / 2 + 1))
	((x < 1)) && x=1
	y=$(((_TUI_ROWS - h) / 2))
	((y < 1)) && y=1
	_DLG_X=$x
	_DLG_Y=$y
	_DLG_W=$w
	_DLG_H=$h
	((btnrow > 0)) && {
		_DLG_BROW=$((y + btnrow))
		for ((i = 0; i < ${#_DLG_BLO[@]}; i++)); do
			((_DLG_BLO[i] += x))
			((_DLG_BHI[i] += x))
		done
	}
	((list_first >= 0)) && _DLG_LROW=$((y + 1 + list_first))

	local title=" $_DLG_TITLE "
	local tsg="$_DLG_SGR_TITLE"
	((_DLG_DANGER)) && [[ "$_DLG_KIND" == confirm ]] && tsg=$'\e[1;91;48;2;30;34;52m'
	out+="${_DLG_SGR_BOX}"$'\e['"${y};${x}H┌─${tsg}${title}${_DLG_SGR_BOX}${hz:0:$((inner - ${#title} - 1))}┐"
	for ((i = 0; i < ${#body[@]}; i++)); do
		out+=$'\e['"$((y + 1 + i));${x}H${_DLG_SGR_BOX}│${body[i]}${_DLG_SGR_BOX}│"
	done
	out+=$'\e['"$((y + h - 1));${x}H${_DLG_SGR_BOX}└${hz}┘"$'\e[0m\e8'
	printf '%s' "$out"
}

# ── toasts ───────────────────────────────────────────────────────────────
declare -ga _TST_ID=() _TST_MSG=() _TST_LVL=() _TST_EXP=() # parallel arrays, oldest first; EXP = ms epoch, 0 = sticky
declare -g _TST_SEQ=0 _TST_ON=0
declare -g _TST_SGR_INFO="" _TST_SGR_SUCCESS="" _TST_SGR_WARN="" _TST_SGR_ERROR="" _TST_STYLED=0

_tui_dialog.toast_styles() {
	_tui_dialog.sgr toast $'\e[0;97;48;2;38;56;92m'
	_TST_SGR_INFO="$_SG"
	_tui_dialog.sgr toast_success $'\e[0;30;48;2;51;204;102m'
	_TST_SGR_SUCCESS="$_SG"
	_tui_dialog.sgr toast_warn $'\e[0;30;48;2;236;201;75m'
	_TST_SGR_WARN="$_SG"
	_tui_dialog.sgr toast_error $'\e[1;97;48;2;176;0;32m'
	_TST_SGR_ERROR="$_SG"
	_TST_STYLED=1
}

tui.notify() {
	local msg="$1" level="${2:-info}" secs="${3:-$TUI_TOAST_SECONDS}" n=${#_TST_ID[@]}
	case "$level" in info | success | warn | error) ;; warning) level=warn ;; *) level=info ;; esac
	((_TST_STYLED)) || _tui_dialog.toast_styles
	while ((n >= TUI_TOAST_MAX)); do # drop the oldest
		_TST_ID=("${_TST_ID[@]:1}")
		_TST_MSG=("${_TST_MSG[@]:1}")
		_TST_LVL=("${_TST_LVL[@]:1}")
		_TST_EXP=("${_TST_EXP[@]:1}")
		((n--))
	done
	local id=$((++_TST_SEQ)) exp=0
	if [[ "$secs" != 0 ]]; then
		local ms
		_tui_api._ms "$secs"
		ms=$_TA_MS
		local now=${EPOCHREALTIME//[.,]/}
		exp=$((now / 1000 + ms))
		tui.after "$secs" _tui_dialog.expire "toast_$id"
	fi
	_TST_ID+=("$id")
	_TST_MSG+=("$msg")
	_TST_LVL+=("$level")
	_TST_EXP+=("$exp")
	TUI_NOTIFY_ID=$id
	if ((! _TST_ON)); then
		_TST_ON=1
		tui.overlay.add _tui_dialog.toast_draw
	fi
	((_TUI_RUNNING)) && _tui_overlay.draw_all
	return 0
}

tui.notify.position() {
	[[ -z "${1:-}" ]] && {
		printf '%s\n' "$TUI_TOAST_POSITION"
		return 0
	}
	case "$1" in
		bottom-right | bottom-left | bottom-center | top-right | top-left | top-center) TUI_TOAST_POSITION="$1" ;;
		*)
			echo "tui.notify.position: bottom-right|bottom-left|bottom-center|top-right|top-left|top-center" >&2
			return 1
			;;
	esac
	((_TUI_RUNNING && ${#_TST_ID[@]})) && tui.relayout # wipe the old spot, redraw at the new one
	return 0
}
tui.notify.seconds() {
	[[ -z "${1:-}" ]] && {
		printf '%s\n' "$TUI_TOAST_SECONDS"
		return 0
	}
	[[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]] && TUI_TOAST_SECONDS="$1"
}

tui.notify.count() { printf '%s\n' "${#_TST_ID[@]}"; }

# tui.notify.clear [ID]: repaints so the covered panes come back
tui.notify.clear() {
	local id="${1:-}" i
	local -a nid=() nmsg=() nlvl=() nexp=()
	for ((i = 0; i < ${#_TST_ID[@]}; i++)); do
		if [[ -z "$id" || "${_TST_ID[i]}" == "$id" ]]; then
			tui.every.cancel "toast_${_TST_ID[i]}"
		else
			nid+=("${_TST_ID[i]}")
			nmsg+=("${_TST_MSG[i]}")
			nlvl+=("${_TST_LVL[i]}")
			nexp+=("${_TST_EXP[i]}")
		fi
	done
	_TST_ID=("${nid[@]}")
	_TST_MSG=("${nmsg[@]}")
	_TST_LVL=("${nlvl[@]}")
	_TST_EXP=("${nexp[@]}")
	((${#_TST_ID[@]})) || {
		_TST_ON=0
		tui.overlay.remove _tui_dialog.toast_draw
	}
	((_TUI_RUNNING)) && tui.relayout
	return 0
}

_tui_dialog.expire() { # called by tui.after with the job id ("toast_N")
	tui.notify.clear "${1#toast_}"
}

# tui.reset_ui clears every timer: keep the toasts, re-arm what time they have left
_tui_dialog.reset() {
	local i now=${EPOCHREALTIME//[.,]/} left
	now=$((now / 1000))
	local n=${#_TST_ID[@]}
	for ((i = 0; i < n; i++)); do
		((_TST_EXP[i] == 0)) && continue
		left=$((_TST_EXP[i] - now))
		((left < 100)) && left=100
		tui.after "$((left / 1000)).$((left % 1000 / 100))" _tui_dialog.expire "toast_${_TST_ID[i]}"
	done
}

_tui_dialog.toast_draw() {
	local n=${#_TST_ID[@]}
	((n)) || return 0
	local w=$TUI_TOAST_WIDTH inner i j x y bottom out=$'\e7' sgr icon line
	((w > _TUI_COLS - 2)) && w=$((_TUI_COLS - 2))
	inner=$((w - 4)) # frame + a space each side
	local pos="$TUI_TOAST_POSITION" atbottom=1
	[[ "$pos" == top-* ]] && atbottom=0
	case "$pos" in
		*-left) x=1 ;;
		*-center) x=$(((_TUI_COLS - w) / 2 + 1)) ;;
		*) x=$((_TUI_COLS - w + 1)) ;;
	esac
	((x < 1)) && x=1
	if ((atbottom)); then y=$((_TUI_ROWS - _TUI_FOOTER_ON)); else y=1; fi
	for ((i = n - 1; i >= 0; i--)); do # newest at the edge, older ones stack inward
		case "${_TST_LVL[i]}" in
			success)
				sgr="$_TST_SGR_SUCCESS"
				icon="✔"
				;;
			warn)
				sgr="$_TST_SGR_WARN"
				icon="▲"
				;;
			error)
				sgr="$_TST_SGR_ERROR"
				icon="✖"
				;;
			*)
				sgr="$_TST_SGR_INFO"
				icon="●"
				;;
		esac
		_tui_dialog.wrap "${_TST_MSG[i]}" "$((inner - 2))"
		local -a lines=("${_WRAP[@]:0:3}")
		local h=$((${#lines[@]} + 2)) top
		if ((atbottom)); then
			top=$((y - h + 1))
			((top < 1)) && break
		else
			top=$y
			((top + h - 1 > _TUI_ROWS - _TUI_FOOTER_ON)) && break
		fi
		printf -v line '%*s' "$((w - 2))" ''
		out+="${sgr}"$'\e['"${top};${x}H┌${line// /─}┐"
		for ((j = 0; j < ${#lines[@]}; j++)); do
			_tui_dialog.pad " ${lines[j]}" "$inner"
			if ((j == 0)); then
				out+=$'\e['"$((top + 1 + j));${x}H│ ${icon}${_PADS:0:$((inner - 1))} │"
			else out+=$'\e['"$((top + 1 + j));${x}H│  ${_PADS:0:$((inner - 1))} │"; fi
		done
		out+=$'\e['"$((top + h - 1));${x}H└${line// /─}┘"
		if ((atbottom)); then y=$((top - 1)); else y=$((top + h)); fi
	done
	out+=$'\e[0m\e8'
	printf '%s' "$out"
}
