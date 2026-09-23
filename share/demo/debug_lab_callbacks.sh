#!/usr/bin/env bash
# debug_lab_callbacks.sh - Debug > Feature lab: a button for every command-bar / overlay / mode feature, a live
# readout of their state, and a log of what fired. Uses only the public tui.* API.

declare -a _LAB_LOG=()
declare -g _LAB_OVERLAY=0 _LAB_M_LAST="" _LAB_M_COUNT=0

_lab_log() {
	local ts
	printf -v ts '%(%H:%M:%S)T' -1
	_LAB_LOG=("$ts  $1" "${_LAB_LOG[@]:0:99}") # newest first
	tui.set_text lab_log "$(printf '%s\n' "${_LAB_LOG[@]}")"
}

_lab_state() {
	local off="" g rc
	for g in "${!_TUI_DEF_OFF[@]}"; do off+="${off:+ }$g"; done
	tui.bind.dirty && rc=" (unsaved changes)" || rc=""
	local -a u=("${!_TUI_UBIND[@]}")
	tui.set_text lab_state "modal            ${_TUI_MODAL:-none}"$'\n'"\
overlay box      $([[ $_LAB_OVERLAY == 1 ]] && echo on || echo off)"$'\n'"\
keybinds off     $([[ $_TUI_KEYS_SUSPENDED == 1 ]] && echo YES || echo no)   (chord $TUI_KEYS_SUSPEND_KEY)"$'\n'"\
terminal mode    $([[ $_TUI_PASSTHROUGH == 1 ]] && echo YES || echo no)   (chord $TUI_PASSTHROUGH_KEY)"$'\n'"\
keyboard pane    ${_TUI_PANE_FOCUS:--}"$'\n'"\
focused widget   ${_TUI_FOCUS_ID:--}"$'\n'"\
your keybinds    ${#u[@]}${rc}"$'\n'"\
default groups   off: ${off:-none}"$'\n'"\
commands         ${#_TUI_CMD_IDS[@]} registered ($((${#_TUI_CMD_DYN[@]})) from providers)"$'\n'"\
page history     ${#_TUI_PAGE_HISTORY[@]} back-steps"$'\n'"\
last input       $(tui.get.event)"$'\n'"\
last paste       ${TUI_LAST_PASTE:0:40}$([[ ${#TUI_LAST_PASTE} -gt 40 ]] && echo …)"
}

lab_visit() {
	_LAB_LOG=()
	_LAB_OVERLAY=0
	tui.every 0.25 _lab_state lab_state_job
	_lab_log "Feature lab ready. Try ctrl+p, or press the buttons on the left."
	_lab_state
}

# ── command bar ──
lab_palette() {
	_lab_log "opening the palette"
	tui.palette.open
}
lab_palette_q() {
	_lab_log "opening the palette with a query"
	tui.palette.open "theme "
}
lab_hello() { _lab_log "the 'Lab: hello' command ran (from the palette or tui.cmd.run)"; }
lab_cmd_add() {
	tui.cmd.add lab.hello "Lab: hello" "lab_hello" --group Lab --desc "Added at runtime with tui.cmd.add" --key ctrl+alt+h
	_lab_log "tui.cmd.add lab.hello ... --key ctrl+alt+h  -> open the palette and type 'hello' (or press ctrl+alt+h)"
}
lab_cmd_remove() {
	tui.cmd.remove lab.hello
	tui.unbind ctrl+alt+h
	_lab_log "tui.cmd.remove lab.hello"
}

# ── a custom modal built on tui.modal / tui.overlay.box ──
lab_modal_open() {
	_LAB_M_LAST="(none yet)"
	_LAB_M_COUNT=0
	tui.modal.open lab _lab_modal_key _lab_modal_draw _lab_modal_mouse
	_lab_log "tui.modal.open lab - it owns the keyboard and mouse now"
}
_lab_modal_key() {
	case "$1" in
		esc | enter)
			tui.modal.close
			_lab_log "modal closed after $_LAB_M_COUNT key(s); last was: $_LAB_M_LAST"
			return
			;;
	esac
	_LAB_M_LAST="$1"
	((_LAB_M_COUNT++))
	tui.modal.redraw
}
_lab_modal_mouse() { [[ "$1" == mouse:* ]] && {
	_LAB_M_LAST="$1 at $2,$3"
	((_LAB_M_COUNT++))
	tui.modal.redraw
}; }
_lab_modal_draw() {
	tui.modal.active lab || return 0
	tui.overlay.box $((_TUI_ROWS / 2 - 3)) $((_TUI_COLS / 2 - 24)) 48 "1;97;45" "Custom modal" \
		"" "Every key and click comes here, nothing else" "reacts (try q, tab, the wheel)." "" \
		"last:  ${_LAB_M_LAST}" "count: ${_LAB_M_COUNT}" "" "Enter or Esc closes it"
}

# ── an overlay that just stays drawn over everything ──
_lab_overlay_draw() {
	tui.overlay.box 2 $((_TUI_COLS - 32)) 30 "1;30;43" "overlay" "drawn by tui.overlay.add" "redrawn over every repaint"
}
lab_overlay_toggle() {
	if ((_LAB_OVERLAY)); then
		_LAB_OVERLAY=0
		tui.overlay.remove _lab_overlay_draw
		tui.relayout
		_lab_log "tui.overlay.remove"
	else
		_LAB_OVERLAY=1
		tui.overlay.add _lab_overlay_draw
		_lab_log "tui.overlay.add - it survives repaints (resize, clocks, scrolling)"
	fi
}

# ── modes ──
lab_kill() {
	_lab_log "keybinds off - press $TUI_KEYS_SUSPEND_KEY to turn them back on"
	tui.keys.suspend on
}
lab_term() {
	_lab_log "terminal mode - press $TUI_PASSTHROUGH_KEY to return"
	tui.passthrough on
}

# ── focus / pages ──
lab_pane_next() {
	tui.action.pane_next
	_lab_log "keyboard pane -> ${_TUI_PANE_FOCUS:--}"
}
lab_pane_prev() {
	tui.action.pane_prev
	_lab_log "keyboard pane -> ${_TUI_PANE_FOCUS:--}"
}
lab_pane_nav() {
	tui.action.focus_pane nav
	_lab_log "tui.action.focus_pane nav"
}
lab_default_settings() {
	_lab_log "going to DABT's shipped Settings page (Back returns here)"
	tui.action.goto_default settings
}
lab_default_keybinds() {
	_lab_log "going to DABT's shipped Keybinds page (Back returns here)"
	tui.action.goto_default keybinds
}

# ── clipboard / input ──
lab_copy() {
	local t="$1"
	[[ -z "$t" ]] && {
		_lab_log "nothing to copy"
		return
	}
	tui.clipboard.copy "$t"
	_lab_log "tui.clipboard.copy (OSC 52): '${t:0:40}'"
}
lab_submit_keep() {
	_lab_log "submitted '$1' - focus stayed (retain_input_on_submit)"
	tui.set inp_keep ""
}
lab_submit_form() { _lab_log "submitted '$1' - focus left (retain_input_on_submit=false)"; }

# ── dialogs and toasts (tui_dialog.sh) ───────────────────────────────────
lab_dlg_yes() { _lab_log "confirm -> ${TUI_DIALOG_RESULT}: yes_fn ran"; }
lab_dlg_no() { _lab_log "confirm -> ${TUI_DIALOG_RESULT}: no_fn ran"; }
lab_dlg_confirm() {
	_lab_log "tui.confirm"
	tui.confirm "Log a line to the panel on the right?" lab_dlg_yes lab_dlg_no --title "Log it?"
}
lab_dlg_danger() {
	_lab_log "tui.confirm --danger"
	tui.confirm "Wipe the log? This cannot be undone." lab_dlg_wipe lab_dlg_no --danger --yes Wipe --no Keep
}
lab_dlg_wipe() {
	_LAB_LOG=()
	tui.notify "Log wiped" warn 2
	_lab_log "log wiped"
}
lab_dlg_message() { tui.message "Dialogs call your function AFTER they are gone, so the callback can open the next one." lab_dlg_closed --title "How it works"; }
lab_dlg_closed() { _lab_log "message closed (result: $TUI_DIALOG_RESULT)"; }
lab_dlg_digits() { [[ "$1" =~ ^[0-9]+$ ]] || {
	TUI_DIALOG_ERROR="numbers only, please"
	return 1
}; }
lab_dlg_port() {
	_lab_log "prompt submitted: '$1'"
	tui.notify "Port set to $1" success
}
lab_dlg_prompt() { tui.prompt "Port number:" lab_dlg_port --title "Port" --value 8080 --validate lab_dlg_digits --cancel lab_dlg_cancelled; }
lab_dlg_cancelled() {
	_lab_log "prompt cancelled"
	tui.notify "Cancelled" info 2
}
lab_dlg_picked() {
	_lab_log "chose #$1: $2"
	local f="${TUI_THEMES_DIR:-}/$2.css"
	if [[ "$2" == default ]]; then tui.theme.clear; elif [[ -r "$f" ]]; then tui.theme.set "$f"; fi
	tui.notify "Theme: $2" success 2
}
lab_dlg_choose() {
	local -a names=(default)
	local f
	for f in "${TUI_THEMES_DIR:-/nonexistent}"/*.css; do [[ -e "$f" ]] && {
		f="${f##*/}"
		names+=("${f%.css}")
	}; done
	tui.choose "Pick a theme" lab_dlg_picked "${names[@]}" --message "Applies to every page"
}
lab_dlg_chain() { tui.prompt "Name of the thing to delete:" lab_dlg_chain2 --placeholder "anything"; }
lab_dlg_chain2() { tui.confirm "Really delete '$1'?" "lab_dlg_deleted $1" lab_dlg_no --danger --yes Delete --no Keep; }
lab_dlg_deleted() {
	_lab_log "deleted '$1' (confirm inside a prompt callback)"
	tui.notify "Deleted $1" success
}
lab_toast_info() { tui.notify "Something happened you might like to know." info; }
lab_toast_success() { tui.notify "Saved successfully" success; }
lab_toast_warn() { tui.notify "Disk almost full (92%)" warn 6; }
lab_toast_error() { tui.notify "Could not reach the server: connection refused after 3 retries. Check the address and try again." error 8; }
lab_toast_sticky() { tui.notify "Sticky toast - stays until you press [ clear all ]" info 0; }
lab_toast_clear() {
	tui.notify.clear
	_lab_log "tui.notify.clear"
}
lab_toast_page() {
	tui.notify "This toast follows you to the next page" success 6
	tui.action.goto debug.xml
}
