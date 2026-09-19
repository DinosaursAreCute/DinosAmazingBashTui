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
