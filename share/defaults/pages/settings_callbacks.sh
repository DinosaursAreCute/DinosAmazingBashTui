#!/usr/bin/env bash
# settings_callbacks.sh - DABT default Settings page. Only public tui.* calls.

declare -gA _DSET_THEME=()        # theme button id -> overlay file ("" = page default)

_dset_status() { tui.update lbl_h2 "$1"; }

dset_visit() {
    tui.factory.clear dset
    _DSET_THEME=()
    local dir="${TUI_THEMES_DIR:-}" f name row=2 cur mark id       # the app sets TUI_THEMES_DIR (tui.start does when <app dir>/themes exists)
    cur="${_TUI_THEME_OVERLAY:-}"

    # theme buttons: "page default" + every *.css found
    mark="  "; [[ -z "$cur" ]] && mark="● "
    tui.factory.button dset col_theme 1 "${mark}Page default" dset_theme_pick; id="$_TUI_FACTORY_LAST_ID"
    _DSET_THEME[$id]=""; tui.class "$id" nav_link; tui.align "$id" left
    if [[ -d "$dir" ]]; then
        for f in "$dir"/*.css; do
            [[ -e "$f" ]] || continue
            name="${f##*/}"; name="${name%.css}"
            mark="  "; [[ "$cur" == "$f" ]] && mark="● "
            tui.factory.button dset col_theme "$row" "${mark}${name^}" dset_theme_pick; id="$_TUI_FACTORY_LAST_ID"
            _DSET_THEME[$id]="$f"; tui.class "$id" nav_link; tui.align "$id" left
            (( row++ ))
        done
    fi

    # one checkbox per default keybind group
    local -A seen=(); local k g r=2 fn
    for k in "${!_TUI_BIND_DEF_GROUP[@]}"; do seen[${_TUI_BIND_DEF_GROUP[$k]}]=1; done
    _tui_input.sorted_ids seen
    for g in "${_SIDS[@]}"; do
        fn="_dset_grp_${g//[^A-Za-z0-9_]/_}"
        eval "$fn() { dset_group_toggle '$g' \"\$1\"; }"
        tui.factory.checkbox dset col_keys "$r" "$g" "$([[ -n "${_TUI_DEF_OFF[$g]:-}" ]] && echo false || echo true)" "$fn"
        (( r++ ))
    done

    tui.update chk_retain   "$TUI_INPUT_RETAIN_ON_SUBMIT"
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
    local f="${_DSET_THEME[$1]-}"
    if [[ -z "$f" ]]; then tui.config.unset theme; tui.theme.clear
    else tui.config.set theme "$f"; tui.theme.set "$f"; fi        # both reload this page: dset_visit redraws the marks
    tui.notify "Theme: ${f:+$(basename "$f" .css)}${f:-page default}" success 2.5   # the toast outlives the reload
}

dset_group_toggle() {
    local g="$1" on="$2" off=""
    if [[ "$on" == 1 ]]; then tui.defaults.on "$g"; else tui.defaults.off "$g"; fi
    for g in "${!_TUI_DEF_OFF[@]}"; do off+="${off:+ }$g"; done
    if [[ -n "$off" ]]; then tui.config.set defaults.off "$off"; else tui.config.unset defaults.off; fi
    _dset_status "default keybind groups off: ${off:-none}"
}

dset_retain()   { TUI_INPUT_RETAIN_ON_SUBMIT="$1"; tui.config.set input.retain "$1";   _dset_status "inputs keep focus after Enter: $([[ $1 == 1 ]] && echo yes || echo no)"; }
dset_coalesce() { TUI_INPUT_COALESCE="$1";         tui.config.set input.coalesce "$1"; _dset_status "merge repeated scroll events: $([[ $1 == 1 ]] && echo yes || echo no)"; }
dset_goto_keybinds() { tui.action.goto_default keybinds; }
dset_confirm_quit() { tui.config.set confirm.quit "$1"; _dset_status "ask before quitting: $([[ $1 == 1 ]] && echo yes || echo no)"; tui.notify "Ask before quitting: $([[ $1 == 1 ]] && echo on || echo off)" info 2; }

_DSET_POS=(bottom-right bottom-center bottom-left top-right top-center top-left)
_DSET_SECS=(3 5 8 12 0)

_dset_notify_labels() {
    local s="$(tui.notify.seconds)"
    tui.set_label btn_npos "[ Position: $(tui.notify.position) ]"
    tui.set_label btn_nsec "[ Stay for: $([[ "$s" == 0 ]] && echo "until dismissed" || echo "${s} s") ]"
}
_dset_next() {   # ARRAY_NAME CURRENT -> _DSET_N: the entry after CURRENT (wraps)
    local -n arr="$1"; local i
    for i in "${!arr[@]}"; do [[ "${arr[i]}" == "$2" ]] && { _DSET_N="${arr[(i + 1) % ${#arr[@]}]}"; return; }; done
    _DSET_N="${arr[0]}"
}
dset_notify_pos() {
    _dset_next _DSET_POS "$(tui.notify.position)"
    tui.notify.position "$_DSET_N"; tui.config.set notify.position "$_DSET_N"
    _dset_notify_labels
    tui.notify "Notifications now appear $_DSET_N" info
}
dset_notify_sec() {
    _dset_next _DSET_SECS "$(tui.notify.seconds)"
    tui.notify.seconds "$_DSET_N"; tui.config.set notify.seconds "$_DSET_N"
    _dset_notify_labels
    tui.notify "Notifications stay $([[ "$_DSET_N" == 0 ]] && echo "until dismissed" || echo "for ${_DSET_N} s")" success "$_DSET_N"
}
dset_goto_plugins() { tui.action.goto_default plugins; }
dset_ts_auto() {
    if ! tui.plugin.enabled terminal_shortcuts; then tui.notify "Enable the 'Terminal shortcuts' plugin first (DABT: Plugins)" warn 5; tui.update chk_tsfree 0; return; fi
    tui.plugin.config terminal_shortcuts auto_free "$1"
    if [[ "$1" == 1 ]]; then tui.cmd.run ts.free; else tui.cmd.run ts.restore; fi
}
dset_tab_here() { :; }
