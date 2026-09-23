#!/usr/bin/env bash
# tui_config.sh - small persistent key/value store for FRAMEWORK settings (the default Settings page uses it).
#   tui.config.get KEY [DEFAULT]      tui.config.set KEY VALUE (saved at once)      tui.config.unset KEY
#   tui.config.load | tui.config.save | tui.config.apply
# File: $TUI_APP_CONF/dabt.conf = ~/.config/DABT/apps/<app>/dabt.conf  (key=value lines; see tui_home.sh). tui.init applies:
#   theme=/path/to/overlay.css      defaults.off="scroll quit"      input.retain=1|0      input.coalesce=1|0
# Apps can keep their own keys here too - anything is stored; only those four mean something to the framework.
declare -gA _TUI_CFG=()
declare -g  TUI_CONFIG_FILE="${TUI_CONFIG_FILE:-$TUI_APP_CONF/dabt.conf}"

tui.config.get()   { printf '%s' "${_TUI_CFG[$1]-${2:-}}"; }
tui.config.set()   { _TUI_CFG[$1]="$2"; tui.config.save; }
tui.config.keys()  { printf '%s\n' "${!_TUI_CFG[@]}" | sort; }
tui.config.unset() { unset '_TUI_CFG[$1]'; tui.config.save; }

tui.config.load() {
    local line k v
    _TUI_CFG=()
    [[ -r "$TUI_CONFIG_FILE" ]] || return 0
    while IFS= read -r line; do
        [[ "$line" == \#* || "$line" != *=* ]] && continue
        k="${line%%=*}"; v="${line#*=}"
        _TUI_CFG[$k]="$v"
    done < "$TUI_CONFIG_FILE"
}

tui.config.save() {
    local dir="${TUI_CONFIG_FILE%/*}" k out=""
    _tui_input.sorted_ids _TUI_CFG
    for k in "${_SIDS[@]}"; do out+="$k=${_TUI_CFG[$k]}"$'\n'; done
    if [[ -z "$out" ]]; then rm -f "$TUI_CONFIG_FILE"; return 0; fi
    mkdir -p "$dir" 2>/dev/null || return 1
    { printf '# DABT settings (written by the Settings page / tui.config.set)\n%s' "$out"; } > "$TUI_CONFIG_FILE.tmp" && mv -f "$TUI_CONFIG_FILE.tmp" "$TUI_CONFIG_FILE"
}

tui.config.apply() {
    local g
    [[ -n "${_TUI_CFG[theme]:-}" && -r "${_TUI_CFG[theme]}" ]] && _TUI_THEME_OVERLAY="${_TUI_CFG[theme]}"
    for g in ${_TUI_CFG[defaults.off]:-}; do _TUI_DEF_OFF[$g]=1; done
    [[ -n "${_TUI_CFG[notify.position]:-}" ]] && tui.notify.position "${_TUI_CFG[notify.position]}" 2>/dev/null
    [[ -n "${_TUI_CFG[notify.seconds]:-}" ]]  && tui.notify.seconds "${_TUI_CFG[notify.seconds]}"
    [[ -n "${_TUI_CFG[input.retain]:-}" ]]   && TUI_INPUT_RETAIN_ON_SUBMIT="${_TUI_CFG[input.retain]}"
    [[ -n "${_TUI_CFG[input.coalesce]:-}" ]] && TUI_INPUT_COALESCE="${_TUI_CFG[input.coalesce]}"
    return 0
}

tui.config.load
