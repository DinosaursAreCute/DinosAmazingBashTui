#!/usr/bin/env bash
# settings_callbacks.sh - DABT default Settings page. Only public tui.* calls.

declare -gA _DSET_THEME=() # theme button id -> theme name from tui.theme.list ("" = page default)

_dset_status() { tui.update lbl_h2 "$1"; }

dset_visit() {
	tui.factory.clear dset
	_DSET_THEME=()
	local f name row=2 cur mark id
	cur="${_TUI_THEME_OVERLAY:-}"

	# theme buttons: "page default" + every theme tui.theme.list finds (DABT's themes directory + the app's)
	mark="  "
	[[ -z "$cur" ]] && mark="● "
	tui.factory.button dset col_theme 1 "${mark}Page default" dset_theme_pick
	id="$_TUI_FACTORY_LAST_ID"
	_DSET_THEME[$id]=""
	tui.class "$id" nav_link
	tui.align "$id" left
	while IFS=$'\t' read -r name f; do
		[[ -n "$name" ]] || continue
		mark="  "
		[[ "$cur" == "$f" ]] && mark="● "
		f="${name//_/ }" # hello_kitty -> Hello kitty
		tui.factory.button dset col_theme "$row" "${mark}${f^}" dset_theme_pick
		id="$_TUI_FACTORY_LAST_ID"
		_DSET_THEME[$id]="$name"
		tui.class "$id" nav_link
		tui.align "$id" left
		((row++))
	done < <(tui.theme.list)

	# one checkbox per default keybind group
	local -A seen=()
	local k g r=2 fn
	for k in "${!_TUI_BIND_DEF_GROUP[@]}"; do seen[${_TUI_BIND_DEF_GROUP[$k]}]=1; done
	_tui_input.sorted_ids seen
	for g in "${_SIDS[@]}"; do
		fn="_dset_grp_${g//[^A-Za-z0-9_]/_}"
		eval "$fn() { dset_group_toggle '$g' \"\$2\"; }" # a checkbox action gets ID VALUE
		tui.factory.checkbox dset col_keys "$r" "$g" "$([[ -n "${_TUI_DEF_OFF[$g]:-}" ]] && echo false || echo true)" "$fn"
		((r++))
	done

	tui.update chk_retain "$TUI_INPUT_RETAIN_ON_SUBMIT"
	tui.update chk_coalesce "$TUI_INPUT_COALESCE"
	tui.update chk_confirmq "$(tui.config.get confirm.quit 0)"
	_dset_notify_labels
	tui.update chk_tsfree "$(tui.plugin.config terminal_shortcuts auto_free 0)"
	tui.update lbl_c1 "  palette          ctrl+p   :"
	tui.update lbl_c2 "  keybinds off     $TUI_KEYS_SUSPEND_KEY"
	tui.update lbl_c3 "  terminal mode    $TUI_PASSTHROUGH_KEY"
	tui.update lbl_c4 "  back             alt+backspace"
	_dset_status "config: ${TUI_CONFIG_FILE/#$HOME/~}"
}

dset_theme_pick() {
	local name="${_DSET_THEME[$1]-}"
	tui.theme.pick "$name"                                # applies, remembers and reloads this page: dset_visit redraws the marks
	tui.notify "Theme: ${name:-page default}" success 2.5 # the toast outlives the reload
}

dset_group_toggle() {
	local g="$1" on="$2" off=""
	if [[ "$on" == 1 ]]; then tui.defaults.on "$g"; else tui.defaults.off "$g"; fi
	for g in "${!_TUI_DEF_OFF[@]}"; do off+="${off:+ }$g"; done
	if [[ -n "$off" ]]; then tui.config.set defaults.off "$off"; else tui.config.unset defaults.off; fi
	_dset_status "default keybind groups off: ${off:-none}"
}

dset_retain() {
	TUI_INPUT_RETAIN_ON_SUBMIT="$2"
	tui.config.set input.retain "$2"
	_dset_status "inputs keep focus after Enter: $([[ $2 == 1 ]] && echo yes || echo no)"
}
dset_coalesce() {
	TUI_INPUT_COALESCE="$2"
	tui.config.set input.coalesce "$2"
	_dset_status "merge repeated scroll events: $([[ $2 == 1 ]] && echo yes || echo no)"
}
dset_goto_keybinds() { tui.action.goto_default keybinds; }
dset_confirm_quit() {
	tui.config.set confirm.quit "$2"
	_dset_status "ask before quitting: $([[ $2 == 1 ]] && echo yes || echo no)"
	tui.notify "Ask before quitting: $([[ $2 == 1 ]] && echo on || echo off)" info 2
}

_DSET_POS=(bottom-right bottom-center bottom-left top-right top-center top-left)
_DSET_SECS=(3 5 8 12 0)

_dset_notify_labels() {
	local s="$(tui.notify.seconds)"
	tui.set_label btn_npos "[ Position: $(tui.notify.position) ]"
	tui.set_label btn_nsec "[ Stay for: $([[ "$s" == 0 ]] && echo "until dismissed" || echo "${s} s") ]"
}
_dset_next() { # ARRAY_NAME CURRENT -> _DSET_N: the entry after CURRENT (wraps)
	local -n arr="$1"
	local i
	for i in "${!arr[@]}"; do [[ "${arr[i]}" == "$2" ]] && {
		_DSET_N="${arr[(i + 1) % ${#arr[@]}]}"
		return
	}; done
	_DSET_N="${arr[0]}"
}
dset_notify_pos() {
	_dset_next _DSET_POS "$(tui.notify.position)"
	tui.notify.position "$_DSET_N"
	tui.config.set notify.position "$_DSET_N"
	_dset_notify_labels
	tui.notify "Notifications now appear $_DSET_N" info
}
dset_notify_sec() {
	_dset_next _DSET_SECS "$(tui.notify.seconds)"
	tui.notify.seconds "$_DSET_N"
	tui.config.set notify.seconds "$_DSET_N"
	_dset_notify_labels
	tui.notify "Notifications stay $([[ "$_DSET_N" == 0 ]] && echo "until dismissed" || echo "for ${_DSET_N} s")" success "$_DSET_N"
}
dset_goto_plugins() { tui.action.goto_default plugins; }
dset_ts_auto() {
	if ! tui.plugin.enabled terminal_shortcuts; then
		tui.notify "Enable the 'Terminal shortcuts' plugin first (DABT: Plugins)" warn 5
		tui.update chk_tsfree 0
		return
	fi
	tui.plugin.config terminal_shortcuts auto_free "$2"
	if [[ "$2" == 1 ]]; then tui.cmd.run ts.free; else tui.cmd.run ts.restore; fi
}
dset_tab_here() { :; }
