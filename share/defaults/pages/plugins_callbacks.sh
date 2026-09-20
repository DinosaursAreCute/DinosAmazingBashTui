#!/usr/bin/env bash
# plugins_callbacks.sh - DABT default Settings > Plugins tab. Only public tui.* calls.

tui.require terminal_renderer

declare -ga _PLG_PATH=() _PLG_DIR=() _PLG_LABELS=()      # file tree row -> path, and whether it is a directory
declare -gA _PLG_CLOSED=()                # directories the user collapsed
declare -g  _PLG_ROOT="" _PLG_NAME=""

_plg_human() { local b=$1; if (( b >= 1048576 )); then _H="$(( b / 1048576 )).$(( b % 1048576 * 10 / 1048576 )) MB"; elif (( b >= 1024 )); then _H="$(( b / 1024 )).$(( b % 1024 * 10 / 1024 )) KB"; else _H="$b B"; fi; }

_plg_fill() {
    local keep="${1:-0}" n st v src title
    local -a rows=()
    while IFS=$'\t' read -r n st v src title; do rows+=("$n|$st|$v|$(tui.plugin.get "$n" author)|$src"); done < <(tui.plugin.list)
    tui.table.set plg_table "Plugin|State|Ver|Author|From" "${rows[@]}"
    tui.table.select plg_table "$keep"
    tui.update plg_h2 "${#rows[@]} detected, $(tui.plugin.list | grep -c $'\tenabled\t') enabled   yours go in ${TUI_PLUGINS_DIR/#$HOME/~}"
}
_plg_name() { local r; r="$(tui.table.row plg_table)"; printf '%s' "${r%%|*}"; }

plg_visit() { tui.hook.on resize plg_rewrap; _PLG_CLOSED=(); _plg_fill 0; plg_selected; tui.focus plg_table; }
plg_tab_here() { :; }
plg_goto_settings() { tui.action.goto_default settings; }

# ── details: the kv renderer, one block per category ─────────────────────
_plg_nl() { _NL="${1//\\n/$'\n'}"; }                 # renderers join lines with a literal \n; panes want real newlines

_plg_details() {
    local n="$1" k v id
    local -A st=()
    while IFS='=' read -r k v; do st[$k]="$v"; done < <(tui.plugin.stats "$n")
    local title ver auth req desc state src file root err
    title="$(tui.plugin.get "$n" title)"; ver="$(tui.plugin.get "$n" version)"; auth="$(tui.plugin.get "$n" author)"
    req="$(tui.plugin.get "$n" requires)"; desc="$(tui.plugin.get "$n" description)"; state="$(tui.plugin.get "$n" state)"
    src="$(tui.plugin.get "$n" source)"; file="$(tui.plugin.get "$n" file)"; root="$(tui.plugin.root "$n")"; err="$(tui.plugin.get "$n" error)"
    _plg_human "${st[bytes]:-0}"
    tui.pane_size plg_details; export TR_WIDTH=$(( TUI_PANE_COLS > 12 ? TUI_PANE_COLS - 1 : 12 ))
    local out="" blk
    out+="$title  v$ver"$'\n'
    _plg_wrap "$desc" "$TR_WIDTH" 0; out+="$(printf '%s\n' "${_WRAP[@]}")"$'\n'

    blk="$(kv_string "State: $state${err:+ ($err)}" "Source: $src$([[ $src == builtin ]] && echo ' (ships with DABT)')" "Version: $ver" "Author: ${auth:--}" "Requires: ${req:--}" -t dots)"
    _plg_nl "$(divider_string Overview)\n$blk"; out+="$_NL"$'\n'
    blk="$(kv_string "Files: ${st[files]:-0}" "Folders: ${st[dirs]:-0}" "Size: $_H" "Lines: ${st[lines]:-0}" "Functions: ${st[functions]:-0}" -t dots)"
    _plg_nl "$(divider_string Contents)\n$blk"; out+="$_NL"$'\n'
    if [[ "$state" == enabled ]]; then
        blk="$(kv_string "Commands: ${st[commands]:-0}" "Keybinds: ${st[binds]:-0}" "Hooks: ${st[hooks]:-0}" "Timers: ${st[timers]:-0}" "Overlays: ${st[overlays]:-0}" -t dots)"
    else blk="(nothing while disabled)"; fi
    _plg_nl "$(divider_string Registered)\n$blk"; out+="$_NL"$'\n'
    blk="$(kv_string "Folder: ${root/#$HOME/~}" "Main file: ${file##*/}" "Id: $n" -t dots)"
    _plg_nl "$(divider_string Location)\n$blk"; out+="$_NL"$'\n'
    local -a cfg=()
    for k in $(tui.config.keys 2>/dev/null); do [[ "$k" == plugin.$n.* ]] && cfg+=("${k#plugin.$n.}: $(tui.config.get "$k")"); done
    if (( ${#cfg[@]} )); then blk="$(kv_string "${cfg[@]}" -t dots)"; _plg_nl "$(divider_string 'Saved settings')\n$blk"; out+="$_NL"$'\n'; fi
    local -a cmds=()
    for id in "${!_TUI_CMD_PLUGIN[@]}"; do [[ "${_TUI_CMD_PLUGIN[$id]}" == "$n" ]] && cmds+=("${_TUI_CMD_TITLE[$id]}: $id"); done
    if (( ${#cmds[@]} )); then blk="$(kv_string "${cmds[@]}" -t dots)"; _plg_nl "$(divider_string 'Command bar')\n$blk"; out+="$_NL"$'\n'; fi
    unset TR_WIDTH
    tui.set_text plg_details "${out%$'\n'}"
}

# soft wrap at word boundaries (a word longer than the width is cut): _plg_wrap TEXT WIDTH INDENT -> _WRAP
_plg_wrap() {
    local t="$1" w="$2" ind="$3" pad chunk head cw first=1
    printf -v pad '%*s' "$ind" ''
    _WRAP=()
    (( w < 8 )) && w=8
    if [[ -z "$t" ]]; then _WRAP=(""); return; fi
    while [[ -n "$t" ]]; do
        (( first )) && cw=$w || cw=$(( w - ind ))
        chunk="${t:0:cw}"
        if (( ${#t} > cw )) && [[ "$chunk" == *" "* ]]; then
            head="${chunk% *}"; (( ${#head} > cw / 3 )) && chunk="$head"
        fi
        t="${t:${#chunk}}"; t="${t# }"
        (( first )) || chunk="$pad$chunk"
        first=0
        _WRAP+=("$chunk")
    done
}

# ── the file tree ───────────────────────────────────────────────────────
_plg_walk() {   # DIR DEPTH
    local d="$1" depth="$2" f name pad="" i
    for (( i = 0; i < depth; i++ )); do pad+="  "; done
    for f in "$d"/*; do
        [[ -d "$f" ]] || continue
        name="${f##*/}"; _PLG_PATH+=("$f"); _PLG_DIR+=(1)
        if [[ -n "${_PLG_CLOSED[$f]:-}" ]]; then _PLG_LABELS+=("$pad▸ $name/")
        else _PLG_LABELS+=("$pad▾ $name/"); _plg_walk "$f" $(( depth + 1 )); fi
    done
    for f in "$d"/*; do
        [[ -f "$f" ]] || continue
        local c; c="$(<"$f")"; _plg_human $(( ${#c} + 1 ))
        _PLG_PATH+=("$f"); _PLG_DIR+=(0); _PLG_LABELS+=("$pad  ${f##*/}   ($_H)")
    done
}
_plg_tree() {
    local root="$1" keep="${2:-0}"
    _PLG_PATH=(); _PLG_DIR=(); _PLG_LABELS=()
    if [[ -d "$root" ]]; then _plg_walk "$root" 0
    elif [[ -f "$root" ]]; then local c; c="$(<"$root")"; _plg_human $(( ${#c} + 1 )); _PLG_PATH+=("$root"); _PLG_DIR+=(0); _PLG_LABELS+=("${root##*/}   ($_H)"); fi
    tui.list.set plg_files "${_PLG_LABELS[@]}"
    tui.list.select plg_files "$keep"
    tui.pane_title plg_tree "Files  ${root/#$HOME/~}"
}

plg_selected() {
    local n; n="$(_plg_name)"
    [[ -n "$n" ]] || return 0
    [[ "$n" == "$_PLG_NAME" ]] && return 0
    _PLG_NAME="$n"; _PLG_CLOSED=()
    _PLG_ROOT="$(tui.plugin.root "$n")"
    _plg_details "$n"
    _plg_tree "$_PLG_ROOT" 0
    # show the plugin's main file straight away
    local i f main; main="$(tui.plugin.get "$n" file)"
    for i in "${!_PLG_PATH[@]}"; do [[ "${_PLG_PATH[i]}" == "$main" ]] && { tui.list.select plg_files "$i"; break; }; done
    _plg_show "$main"
}
# Enter / double-click on a plugin: its menu (what you can do with THAT plugin)
declare -g _PLG_MENU=""
plg_enter() {
    local n st desc info toggle; n="$(_plg_name)"
    [[ -n "$n" ]] || return 0
    _PLG_MENU="$n"; st="$(tui.plugin.get "$n" state)"; desc="$(tui.plugin.get "$n" description)"
    local -A stt=(); local k v
    while IFS='=' read -r k v; do stt[$k]="$v"; done < <(tui.plugin.stats "$n")
    info="$desc"$'\n\n'"$st, v$(tui.plugin.get "$n" version), from $(tui.plugin.get "$n" source)"$'\n'"${stt[files]} files, ${stt[lines]} lines, ${stt[functions]} functions"
    [[ "$st" == enabled ]] && info+=$'\n'"registered: ${stt[commands]} commands, ${stt[binds]} keybinds, ${stt[hooks]} hooks, ${stt[timers]} timers"
    [[ "$st" == enabled ]] && toggle="Disable" || toggle="Enable"
    tui.choose "$(tui.plugin.get "$n" title)" plg_menu_pick "$toggle" "Reload" "Browse its files" "Show its main file" "Remove" --message "$info" --width 60
}
plg_menu_pick() {
    case "$2" in
        Enable|Disable) plg_toggle ;;
        Reload) plg_reload ;;
        "Browse its files") tui.focus plg_files ;;
        "Show its main file") _plg_show "$(tui.plugin.get "$_PLG_MENU" file)" ;;
        Remove) plg_remove ;;
    esac
}
plg_rescan() { tui.plugin.scan; _PLG_NAME=""; _plg_fill "$(tui.table.selected plg_table)"; plg_selected; tui.notify "Scanned: $(tui.plugin.list | wc -l) plugins" info 2; }

declare -g _PLG_SHOWN=""
_plg_show() {
    local f="$1" n=0 line w gw
    [[ -f "$f" ]] || { tui.output plg_content ""; return; }
    _PLG_SHOWN="$f"
    tui.pane_title plg_content "${f/#$HOME/~}"
    local -a lines=() out=()
    mapfile -t -n 600 lines < "$f"
    w=${#lines[@]}; gw=${#w}
    tui.pane_size plg_content; local avail=$(( TUI_PANE_COLS - 1 ))          # one column for the scroll indicator
    for line in "${lines[@]}"; do
        (( n++ ))
        _plg_wrap "$line" "$(( avail - gw - 2 ))" 0                            # soft wrap at the end of the pane
        local i
        for i in "${!_WRAP[@]}"; do
            if (( i == 0 )); then printf -v line '%*d  %s' "$gw" "$n" "${_WRAP[i]}"
            else printf -v line '%*s  %s' "$gw" "" "${_WRAP[i]}"; fi          # continuation: blank gutter
            out+=("$line")
        done
    done
    (( n >= 600 )) && out+=("" "... (first 600 lines)")
    tui.output plg_content "$(printf '%s\n' "${out[@]}")"
    tui.relayout plg_content
}
# the pane got a different width: wrap again
plg_rewrap() { [[ -n "$(tui.get.type plg_content 2>/dev/null)" && -n "$_PLG_SHOWN" ]] && _plg_show "$_PLG_SHOWN"; return 1; }
plg_file_selected() {
    local i; i="$(tui.list.selected plg_files)"
    (( i >= 0 )) || return 0
    [[ "${_PLG_DIR[i]}" == 0 ]] && _plg_show "${_PLG_PATH[i]}"
}
plg_toggle_dir() {                                   # Enter / double-click on a row: collapse or expand a folder
    local i; i="$(tui.list.selected plg_files)"
    (( i >= 0 )) || return 0
    [[ "${_PLG_DIR[i]}" == 1 ]] || return 0
    local p="${_PLG_PATH[i]}"
    if [[ -n "${_PLG_CLOSED[$p]:-}" ]]; then unset '_PLG_CLOSED[$p]'; else _PLG_CLOSED[$p]=1; fi
    _plg_tree "$_PLG_ROOT" "$i"
}

# ── actions ─────────────────────────────────────────────────────────────
plg_toggle() {
    local n sel; n="$(_plg_name)"; sel="$(tui.table.selected plg_table)"
    [[ -n "$n" ]] || return 0
    if tui.plugin.toggle "$n"; then tui.notify "$n: $(tui.plugin.get "$n" state)" info 2
    else tui.notify "$n: ${TUI_PLUGIN_ERROR:-failed}" error 6; fi
    _PLG_NAME=""; _plg_fill "$sel"; plg_selected
}
plg_reload() { local n sel; n="$(_plg_name)"; sel="$(tui.table.selected plg_table)"; [[ -n "$n" ]] || return 0; tui.plugin.reload "$n"; tui.notify "$n reloaded" success 2; _PLG_NAME=""; _plg_fill "$sel"; plg_selected; }
plg_remove() {
    local n; n="$(_plg_name)"; [[ -n "$n" ]] || return 0
    tui.confirm "Remove plugin '$n'?"$'\n'"A plugin you installed is deleted from disk; a built-in or app plugin is only unregistered." plg_do_remove --danger --yes Remove --no Keep --title "Remove plugin"
}
plg_do_remove() { local n; n="$(_plg_name)"; tui.plugin.remove "$n"; tui.notify "Removed $n" warn 3; _PLG_NAME=""; _plg_fill 0; plg_selected; }
plg_install() { tui.prompt "Path to a .plugin.sh file or a plugin folder:" plg_do_install --placeholder "~/plugins/my.plugin.sh" --title "Install plugin"; }
plg_do_install() {
    local p="${1/#\~/$HOME}"
    if tui.plugin.install "$p"; then tui.notify "Installed $TUI_PLUGIN_NAME (not enabled yet)" success 4; _PLG_NAME=""; _plg_fill 0; plg_selected
    else tui.notify "Install failed: $TUI_PLUGIN_ERROR" error 6; fi
}
