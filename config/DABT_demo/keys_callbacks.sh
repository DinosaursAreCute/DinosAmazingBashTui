#!/usr/bin/env bash
# keys_callbacks.sh - Keys page: live view of the binding table, a tape of the
# decoded input, and a form that adds/removes bindings at runtime (tui_input.sh).

tui.require terminal_renderer

declare -a _KEYS_TAPE=()

_keys_refresh() {
    tui.bind.table; tui.set_text bindings "$_TBL"; return 0
    local -a rows=("Scope|Key|Command|Note")
    local scope key cmd note
    while IFS=$'\t' read -r scope key cmd note; do
        rows+=("${scope}|${key}|${cmd}|${note:- }")
    done < <(tui.bind.list)
    tui.output bindings "$(printf '%b' "$(table_string -r "${rows[@]}")")"
}

_keys_on_event() {
    _KEYS_TAPE+=("$1")
    (( ${#_KEYS_TAPE[@]} > 200 )) && _KEYS_TAPE=("${_KEYS_TAPE[@]: -200}")
    local -a rev=() i
    for (( i = ${#_KEYS_TAPE[@]} - 1; i >= 0; i-- )); do rev+=("${_KEYS_TAPE[i]}"); done   # newest first
    tui.set_text events "$(printf '%s\n' "${rev[@]}")"
}

keys_visit() {
    _KEYS_TAPE=()
    _TUI_ON_INPUT_EVENT="_keys_on_event"
    _keys_refresh
    _keys_dirty_label
}

# Sample action for the form: shows what the handler can learn about the event.
keys_flash() {
    tui.update lbl_k_status "fired: key=$TUI_EVENT_KEY type=$TUI_EVENT_TYPE pane=${TUI_EVENT_PANE:--} widget=${TUI_EVENT_WIDGET:--} at ${TUI_EVENT_X},${TUI_EVENT_Y}"
}

_keys_dirty_label() {
    if tui.bind.dirty; then
        tui.update lbl_k_dirty " ● unsaved changes - Save to keep them, or Discard "
        tui.set_label btn_k_save "[ Save changes ]"
    else
        tui.update lbl_k_dirty ""
        tui.set_label btn_k_save "[ Save ]"
    fi
}

on_key_bind() {
    local k a; k="$(tui.get inp_key)"; a="$(tui.get inp_action)"
    if [[ -z "$k" || -z "$a" ]]; then tui.update lbl_k_status "need both a key and an action"; return; fi
    if [[ "${a%% *}" != tui.action.* ]] && ! declare -F "${a%% *}" >/dev/null; then
        tui.update lbl_k_status "no such function: ${a%% *}"; return
    fi
    tui.bind "$k" "$a" --user --desc "you"          # yours: global, survives page changes, saved with Save
    _keys_refresh
    tui.update lbl_k_status "bound  $k  ->  $a   (not saved yet)"
    _keys_dirty_label
}

on_key_unbind() {
    local k; k="$(tui.get inp_key)"
    [[ -z "$k" ]] && { tui.update lbl_k_status "type the key to unbind first"; return; }
    tui.unbind "$k" --user
    _keys_refresh
    tui.update lbl_k_status "removed your bind on  $k  (its default, if any, is back)"
    _keys_dirty_label
}

on_key_reset() { tui.bind.reset --user; _keys_refresh; tui.update lbl_k_status "all your binds removed (not saved yet)"; _keys_dirty_label; }

on_key_save() {
    if tui.bind.save; then tui.update lbl_k_status "saved to ${TUI_USER_KEYBINDS/#$HOME/~}"
    else tui.update lbl_k_status "could not save - see the terminal"; fi
    _keys_refresh; _keys_dirty_label
}

on_key_discard() { tui.bind.discard; _keys_refresh; tui.update lbl_k_status "unsaved changes discarded"; _keys_dirty_label; }
