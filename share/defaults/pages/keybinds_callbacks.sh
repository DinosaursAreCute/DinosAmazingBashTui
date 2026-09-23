#!/usr/bin/env bash
# keybinds_callbacks.sh - DABT default Keybinds page. Only public tui.* calls.
tui.require terminal_renderer

_dkb_refresh() {
	tui.bind.table
	tui.set_text table "$_TBL"
	return 0
	local -a rows=("Scope|Key|Command|Note")
	local scope key cmd note
	while IFS=$'\t' read -r scope key cmd note; do rows+=("${scope}|${key}|${cmd}|${note:- }"); done < <(tui.bind.list)
	tui.output table "$(printf '%b' "$(table_string -r "${rows[@]}")")"
}

_dkb_dirty() {
	if tui.bind.dirty; then
		tui.update lbl_dirty " ● unsaved changes - Save to keep them, or Discard "
		tui.set_label btn_save "[ Save changes ]"
	else
		tui.update lbl_dirty ""
		tui.set_label btn_save "[ Save ]"
	fi
}

dkb_visit() {
	_dkb_refresh
	_dkb_dirty
	tui.update lbl_status "saved keybinds: ${TUI_USER_KEYBINDS/#$HOME/~}"
}

dkb_bind() {
	local k a
	k="$(tui.get inp_key)"
	a="$(tui.get inp_action)"
	if [[ -z "$k" || -z "$a" ]]; then
		tui.update lbl_status "need both a key and an action"
		return
	fi
	if [[ "${a%% *}" != tui.* ]] && ! declare -F "${a%% *}" >/dev/null; then
		tui.update lbl_status "no such function: ${a%% *}"
		return
	fi
	tui.bind "$k" "$a" --user --desc "you"
	_dkb_refresh
	tui.update lbl_status "bound  $k  ->  $a   (not saved yet)"
	_dkb_dirty
}
dkb_unbind() {
	local k
	k="$(tui.get inp_key)"
	[[ -z "$k" ]] && {
		tui.update lbl_status "type the key to unbind first"
		return
	}
	tui.unbind "$k" --user
	_dkb_refresh
	tui.update lbl_status "removed your bind on  $k"
	_dkb_dirty
}
dkb_drop() { tui.confirm "Remove all of your own keybinds? (Nothing is written until you press Save.)" dkb_do_drop --danger --yes Remove --no Keep --title "Remove keybinds"; }
dkb_do_drop() {
	tui.bind.reset --user
	_dkb_refresh
	tui.update lbl_status "all your binds removed (not saved yet)"
	_dkb_dirty
	tui.notify "Your keybinds were removed - Save to keep that" warn
}
dkb_save() {
	if tui.bind.save; then
		tui.update lbl_status "saved to ${TUI_USER_KEYBINDS/#$HOME/~}"
		tui.notify "Keybinds saved" success
	else
		tui.update lbl_status "could not save"
		tui.notify "Could not save ${TUI_USER_KEYBINDS/#$HOME/~}" error 6
	fi
	_dkb_refresh
	_dkb_dirty
}
dkb_discard() {
	if tui.bind.dirty; then
		tui.confirm "Throw away your unsaved keybind changes?" dkb_do_discard --danger --yes Discard --no Keep --title "Discard changes"
	else tui.notify "Nothing to discard" info 2; fi
}
dkb_do_discard() {
	tui.bind.discard
	_dkb_refresh
	tui.update lbl_status "unsaved changes discarded"
	_dkb_dirty
	tui.notify "Changes discarded" info 2
}
dkb_goto_settings() { tui.action.goto_default settings; }
