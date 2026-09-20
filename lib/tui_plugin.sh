#!/usr/bin/env bash
# tui_plugin.sh - plugins: drop-in bash files that add commands, keybinds, hooks, timers and overlays to DABT and can be
# listed, enabled, disabled, reloaded, installed and removed while the app runs.
#
# A PLUGIN is either one file  NAME.plugin.sh  or a directory  NAME/plugin.sh  (with whatever assets it needs; ask
# tui.plugin.dir NAME where it lives). The first 40 lines carry its metadata as comments:
#     # plugin: my_plugin            id (a-z 0-9 _), defaults to the file name
#     # title: My plugin             shown in lists
#     # version: 1.0
#     # description: what it does
#     # author: you
#     # requires: other_plugin ...   enabled first, disabled last
#     # default: on|off              state on first run (default off)
# and it defines these functions (all optional, none run until the plugin is enabled - the file is only SOURCED then):
#     plugin.NAME.on_enable        register things here: tui.cmd.add, tui.bind, tui.hook.on, tui.every ...
#     plugin.NAME.on_disable       give things back (terminal settings, files, ...)
#     plugin.NAME.on_remove        the plugin is being uninstalled (delete state it created)
# Everything registered from inside on_enable with the calls listed under OWNERSHIP is undone automatically when the
# plugin is disabled, so most plugins need no on_disable at all.
#
# WHERE PLUGINS LIVE (scanned at start, in this order; a later dir does not replace an earlier plugin of the same name)
#     ~/.config/DABT/plugins ($TUI_PLUGINS_DIR): the plugins that ship with DABT (the installer copies them here) and yours
#     <app dir>/plugins   the application's         $TUI_ROOT/share/plugins   the shipped originals (used when DABT is not installed)
#     TUI_PLUGIN_DIRS  (colon list)      tui.plugin.install copies into ~/.config/DABT/plugins
#
#   tui.plugin.dir_add DIR | tui.plugin.scan          add a search dir / (re)discover
#   tui.plugin.add PATH                               register one file or dir           -> TUI_PLUGIN_NAME
#   tui.plugin.install PATH [--force]                 copy into the user's dir, register (not enabled)
#   tui.plugin.remove NAME                            disable, unregister, delete it if it is a user plugin
#   tui.plugin.enable NAME | disable NAME | toggle NAME | reload NAME       (state is saved: config plugin.NAME.enabled)
#   tui.plugin.list                                   NAME<TAB>STATE<TAB>VERSION<TAB>SOURCE<TAB>TITLE per plugin
#   tui.plugin.info NAME                              text describing it     tui.plugin.get NAME FIELD
#   tui.plugin.enabled NAME                           rc 0 when enabled      tui.plugin.dir NAME   its directory
#   tui.plugin.config NAME KEY [VALUE]                a plugin's own saved setting (config plugin.NAME.KEY)
#   tui.plugin.own TYPE VALUE                         add to what disable undoes (TYPE: cmd bind hook every tick overlay
#                                                     provider run - `run` evals VALUE)
# HOOKS (the events between the framework and plugins)
#   tui.hook.on EVENT FN | tui.hook.off EVENT FN | tui.hook.fire EVENT [ARG...]
#   init (tui.init done)  ready (first frame about to run)  page FILE (after every page switch)  resize ROWS COLS
#   key NAME (before bindings - FN returns 0 to CONSUME the key)  quit (tui.stop)  exit (terminal being restored -
#   give shortcuts/files back here)  plugin_enabled NAME  plugin_disabled NAME
# Plugins are trusted code: they run in the app's shell with its permissions.

declare -gA _TPL_KIND=() _TPL_FILE=() _TPL_TITLE=() _TPL_VER=() _TPL_DESC=() _TPL_AUTHOR=() _TPL_REQ=() _TPL_DEF=() _TPL_SRC=() _TPL_STATE=() _TPL_ERR=() _TPL_OWN=()
declare -ga _TPL_ORDER=() _TPL_DIRS=()
declare -gA _TPL_HOOK=()
declare -g  _TPL_CUR="" _TPL_READY=0 _TPL_SCANNED=0
declare -g  TUI_PLUGIN_NAME="" TUI_PLUGIN_ERROR="" TUI_PLUGIN_DIRS="${TUI_PLUGIN_DIRS:-}"

_tui_plugin.id() { _PID="${1,,}"; _PID="${_PID//[^a-z0-9_]/_}"; }

# ── ownership: what a plugin registered, so disabling can undo it ────────
_tui_plugin.own() { [[ -n "${_TPL_CUR:-}" ]] && _TPL_OWN[$_TPL_CUR]+="$1"$'\t'"$2"$'\n'; return 0; }
tui.plugin.own()  { _tui_plugin.own "$@"; }

_tui_plugin.release() {   # NAME: undo, newest first
    local name="$1" line t v i
    local -a lines=()
    while IFS= read -r line; do [[ -n "$line" ]] && lines+=("$line"); done <<< "${_TPL_OWN[$name]:-}"
    for (( i = ${#lines[@]} - 1; i >= 0; i-- )); do
        t="${lines[i]%%$'\t'*}"; v="${lines[i]#*$'\t'}"
        case "$t" in
            cmd)      tui.cmd.remove "$v" ;;
            bind)     tui.unbind $v ;;
            hook)     tui.hook.off $v ;;
            every)    tui.every.cancel "$v" ;;
            tick)     tui.tick.remove "$v" ;;
            overlay)  tui.overlay.remove "$v" ;;
            provider) local f; local -a keep=(); for f in "${_TUI_CMD_PROVIDERS[@]}"; do [[ "$f" == "$v" ]] || keep+=("$f"); done; _TUI_CMD_PROVIDERS=("${keep[@]}") ;;
            run)      eval "$v" ;;
        esac
    done
    unset '_TPL_OWN[$name]'
}

# ── hooks ────────────────────────────────────────────────────────────────
tui.hook.on() {
    local ev="$1" fn="$2" f
    for f in ${_TPL_HOOK[$ev]:-}; do [[ "$f" == "$fn" ]] && return 0; done
    _TPL_HOOK[$ev]="${_TPL_HOOK[$ev]:+${_TPL_HOOK[$ev]} }$fn"
    _tui_plugin.own hook "$ev $fn"
}
tui.hook.off() {
    local ev="$1" fn="$2" f; local -a keep=()
    for f in ${_TPL_HOOK[$ev]:-}; do [[ "$f" == "$fn" ]] || keep+=("$f"); done
    _TPL_HOOK[$ev]="${keep[*]}"
}
# rc 0 when at least one handler returned 0 ("handled"); only the key event uses that
tui.hook.fire() {
    local ev="$1" fn rc=1; shift
    [[ -n "${_TPL_HOOK[$ev]:-}" ]] || return 1
    for fn in ${_TPL_HOOK[$ev]}; do
        declare -F "$fn" >/dev/null || continue
        "$fn" "$@" && rc=0
    done
    return $rc
}

# ── registry ─────────────────────────────────────────────────────────────
_tui_plugin.parse() {   # FILE -> _PL_NAME _PL_TITLE _PL_VER _PL_DESC _PL_AUTHOR _PL_REQ _PL_DEF
    local line n=0 k v
    _PL_NAME=""; _PL_TITLE=""; _PL_VER=""; _PL_DESC=""; _PL_AUTHOR=""; _PL_REQ=""; _PL_DEF=""
    while IFS= read -r line && (( n++ < 40 )); do
        [[ "$line" =~ ^#[[:space:]]*(plugin|title|version|description|author|requires|default):[[:space:]]*(.*)$ ]] || continue
        k="${BASH_REMATCH[1]}"; v="${BASH_REMATCH[2]}"; v="${v%"${v##*[![:space:]]}"}"
        case "$k" in
            plugin) _tui_plugin.id "$v"; _PL_NAME="$_PID" ;; title) _PL_TITLE="$v" ;; version) _PL_VER="$v" ;;
            description) _PL_DESC="$v" ;; author) _PL_AUTHOR="$v" ;; requires) _PL_REQ="$v" ;; default) _PL_DEF="${v,,}" ;;
        esac
    done < "$1"
}

tui.plugin.dir_add() { local d; for d in "${_TPL_DIRS[@]}"; do [[ "$d" == "$1" ]] && return 0; done; _TPL_DIRS+=("$1"); }

# tui.plugin.add PATH [SOURCE]   SOURCE = builtin | app | user (where it came from)
tui.plugin.add() {
    local path="$1" src="${2:-user}" file dir base
    TUI_PLUGIN_NAME=""; TUI_PLUGIN_ERROR=""
    if [[ -d "$path" ]]; then dir="$(cd -P "${path%/}" && pwd -P)"; file="$dir/plugin.sh"; base="${dir##*/}"        # always the real, resolved path
    else base="${path##*/}"; dir="$(cd -P "$(dirname "$path")" 2>/dev/null && pwd -P)"; file="$dir/$base"; base="${base%.plugin.sh}"; base="${base%.sh}"; fi
    [[ -r "$file" ]] || { TUI_PLUGIN_ERROR="cannot read $file"; return 1; }
    _tui_plugin.parse "$file"
    local name="$_PL_NAME"; [[ -n "$name" ]] || { _tui_plugin.id "$base"; name="$_PID"; }
    [[ -n "$name" ]] || { TUI_PLUGIN_ERROR="no plugin name in $file"; return 1; }
    if [[ -n "${_TPL_FILE[$name]:-}" ]]; then
        [[ "${_TPL_FILE[$name]}" == "$file" ]] || { TUI_PLUGIN_ERROR="a plugin named '$name' is already registered (${_TPL_FILE[$name]})"; return 1; }
    else _TPL_ORDER+=("$name"); _TPL_STATE[$name]=disabled; fi
    _TPL_FILE[$name]="$file"; _TPL_SRC[$name]="$src"; [[ -d "$path" ]] && _TPL_KIND[$name]=dir || _TPL_KIND[$name]=file
    _TPL_TITLE[$name]="${_PL_TITLE:-$name}"; _TPL_VER[$name]="${_PL_VER:-0}"; _TPL_DESC[$name]="$_PL_DESC"
    _TPL_AUTHOR[$name]="$_PL_AUTHOR"; _TPL_REQ[$name]="$_PL_REQ"; _TPL_DEF[$name]="$_PL_DEF"
    TUI_PLUGIN_NAME="$name"
}

tui.plugin.scan() {
    local d f src
    (( ${#_TPL_DIRS[@]} )) || _tui_plugin.default_dirs
    for d in "${_TPL_DIRS[@]}"; do
        [[ -d "$d" ]] || continue
        for f in "$d"/*.plugin.sh "$d"/*/plugin.sh; do
            [[ -e "$f" ]] || continue
            src=user
            [[ -n "${_TUI_APP_DIR:-}" && "$d" == "$_TUI_APP_DIR/plugins" ]] && src=app
            _tui_plugin.shipped "$f" && src=builtin                    # a plugin that ships with DABT, wherever its copy lives
            if [[ "${f##*/}" == plugin.sh ]]; then tui.plugin.add "${f%/plugin.sh}" "$src"; else tui.plugin.add "$f" "$src"; fi
        done
    done
    _TPL_SCANNED=1
}

# rc 0 when a plugin file/dir has the name of one that ships in $TUI_ROOT/share/plugins
_tui_plugin.shipped() {
    local n="${1%/plugin.sh}"; n="${n##*/}"
    [[ -e "$TUI_ROOT/share/plugins/$n" ]]
}

_tui_plugin.user_dir() { _UD="$TUI_PLUGINS_DIR"; }
_tui_plugin.default_dirs() {
    local d; local -a extra
    _tui_plugin.user_dir; tui.plugin.dir_add "$_UD"                         # ~/.config/DABT/plugins: shipped copies + yours
    [[ -n "${_TUI_APP_DIR:-}" ]] && tui.plugin.dir_add "$_TUI_APP_DIR/plugins"
    tui.plugin.dir_add "$TUI_ROOT/share/plugins"                            # not installed yet (a checkout): use the shipped ones
    IFS=: read -ra extra <<< "$TUI_PLUGIN_DIRS"
    for d in "${extra[@]}"; do [[ -n "$d" ]] && tui.plugin.dir_add "$d"; done
}

# ── enable / disable ─────────────────────────────────────────────────────
_tui_plugin.persist() { tui.config.set "plugin.$1.enabled" "$2"; }

tui.plugin.enable() {
    local name="$1" save=1 r prev
    [[ "${2:-}" == --no-save ]] && save=0
    TUI_PLUGIN_ERROR=""
    [[ -n "${_TPL_FILE[$name]:-}" ]] || { TUI_PLUGIN_ERROR="no such plugin: $name"; return 1; }
    [[ "${_TPL_STATE[$name]}" == enabled ]] && return 0
    [[ "${_TPL_STATE[$name]}" == enabling ]] && { TUI_PLUGIN_ERROR="$name: circular requires"; return 1; }
    _TPL_STATE[$name]=enabling
    for r in ${_TPL_REQ[$name]}; do
        tui.plugin.enable "$r" "${2:-}" || { TUI_PLUGIN_ERROR="$name needs $r: $TUI_PLUGIN_ERROR"; _TPL_STATE[$name]=error; _TPL_ERR[$name]="$TUI_PLUGIN_ERROR"; return 1; }
    done
    prev="$_TPL_CUR"; _TPL_CUR="$name"
    if ! source "${_TPL_FILE[$name]}" || { declare -F "plugin.$name.on_enable" >/dev/null && ! "plugin.$name.on_enable"; }; then
        _TPL_CUR="$prev"
        TUI_PLUGIN_ERROR="$name failed to start"
        _tui_plugin.release "$name"; _TPL_STATE[$name]=error; _TPL_ERR[$name]="$TUI_PLUGIN_ERROR"
        return 1
    fi
    _TPL_CUR="$prev"
    _TPL_STATE[$name]=enabled; _TPL_ERR[$name]=""
    (( save )) && _tui_plugin.persist "$name" 1
    tui.hook.fire plugin_enabled "$name"
    return 0
}

tui.plugin.disable() {
    local name="$1" save=1 p r
    [[ "${2:-}" == --no-save ]] && save=0
    [[ -n "${_TPL_FILE[$name]:-}" ]] || { TUI_PLUGIN_ERROR="no such plugin: $name"; return 1; }
    [[ "${_TPL_STATE[$name]}" == enabled ]] || { (( save )) && _tui_plugin.persist "$name" 0; return 0; }
    for p in "${_TPL_ORDER[@]}"; do                                   # whoever needs this plugin goes first
        [[ "${_TPL_STATE[$p]}" == enabled ]] || continue
        for r in ${_TPL_REQ[$p]}; do [[ "$r" == "$name" ]] && tui.plugin.disable "$p" "${2:-}"; done
    done
    declare -F "plugin.$name.on_disable" >/dev/null && "plugin.$name.on_disable"
    _tui_plugin.release "$name"
    _TPL_STATE[$name]=disabled
    (( save )) && _tui_plugin.persist "$name" 0
    tui.hook.fire plugin_disabled "$name"
    return 0
}

tui.plugin.toggle() { if [[ "${_TPL_STATE[$1]:-}" == enabled ]]; then tui.plugin.disable "$1"; else tui.plugin.enable "$1"; fi; }
tui.plugin.enabled() { [[ "${_TPL_STATE[$1]:-}" == enabled ]]; }

tui.plugin.reload() {
    local name="$1" f
    [[ -n "${_TPL_FILE[$name]:-}" ]] || return 1
    local was="${_TPL_STATE[$name]}"
    tui.plugin.disable "$name" --no-save
    for f in $(compgen -A function "plugin.$name."); do unset -f "$f"; done
    _tui_plugin.parse "${_TPL_FILE[$name]}"
    _TPL_TITLE[$name]="${_PL_TITLE:-$name}"; _TPL_VER[$name]="${_PL_VER:-0}"; _TPL_DESC[$name]="$_PL_DESC"; _TPL_REQ[$name]="$_PL_REQ"
    [[ "$was" == enabled ]] && tui.plugin.enable "$name" --no-save
}

# ── install / remove ─────────────────────────────────────────────────────
tui.plugin.install() {
    local src="$1" force=0 dest base name
    [[ "${2:-}" == --force ]] && force=1
    TUI_PLUGIN_ERROR=""
    [[ -e "$src" ]] || { TUI_PLUGIN_ERROR="not found: $src"; return 1; }
    _tui_plugin.user_dir; mkdir -p "$_UD" || { TUI_PLUGIN_ERROR="cannot create $_UD"; return 1; }
    src="${src%/}"; base="${src##*/}"; dest="$_UD/$base"
    if [[ -e "$dest" ]] && (( ! force )); then TUI_PLUGIN_ERROR="$base is already installed (use --force to replace)"; return 1; fi
    rm -rf "$dest"; cp -R "$src" "$dest" || { TUI_PLUGIN_ERROR="copy failed"; return 1; }
    tui.plugin.add "$dest" user || { rm -rf "$dest"; return 1; }
    return 0
}

tui.plugin.remove() {
    local name="$1" f file dir n
    [[ -n "${_TPL_FILE[$name]:-}" ]] || { TUI_PLUGIN_ERROR="no such plugin: $name"; return 1; }
    tui.plugin.disable "$name" --no-save
    declare -F "plugin.$name.on_remove" >/dev/null && "plugin.$name.on_remove"
    for f in $(compgen -A function "plugin.$name."); do unset -f "$f"; done
    file="${_TPL_FILE[$name]}"
    _tui_plugin.user_dir
    if [[ "${_TPL_SRC[$name]}" == user && "$file" == "$_UD"/* ]]; then
        if [[ "${file##*/}" == plugin.sh ]]; then rm -rf "${file%/plugin.sh}"; else rm -f "$file"; fi
    fi
    local -a keep=(); for n in "${_TPL_ORDER[@]}"; do [[ "$n" == "$name" ]] || keep+=("$n"); done; _TPL_ORDER=("${keep[@]}")
    unset '_TPL_FILE[$name]' '_TPL_TITLE[$name]' '_TPL_VER[$name]' '_TPL_DESC[$name]' '_TPL_AUTHOR[$name]' '_TPL_REQ[$name]' '_TPL_DEF[$name]' '_TPL_SRC[$name]' '_TPL_STATE[$name]' '_TPL_ERR[$name]' '_TPL_KIND[$name]'
    tui.config.unset "plugin.$name.enabled" 2>/dev/null
    return 0
}

# ── queries ──────────────────────────────────────────────────────────────
tui.plugin.list() {
    local n
    for n in "${_TPL_ORDER[@]}"; do printf '%s\t%s\t%s\t%s\t%s\n' "$n" "${_TPL_STATE[$n]}" "${_TPL_VER[$n]}" "${_TPL_SRC[$n]}" "${_TPL_TITLE[$n]}"; done
}
tui.plugin.get() {
    case "$2" in
        title) printf '%s\n' "${_TPL_TITLE[$1]:-}" ;; version) printf '%s\n' "${_TPL_VER[$1]:-}" ;; description) printf '%s\n' "${_TPL_DESC[$1]:-}" ;;
        author) printf '%s\n' "${_TPL_AUTHOR[$1]:-}" ;; requires) printf '%s\n' "${_TPL_REQ[$1]:-}" ;; state) printf '%s\n' "${_TPL_STATE[$1]:-}" ;;
        source) printf '%s\n' "${_TPL_SRC[$1]:-}" ;; file) printf '%s\n' "${_TPL_FILE[$1]:-}" ;; error) printf '%s\n' "${_TPL_ERR[$1]:-}" ;;
        *) return 1 ;;
    esac
}
# tui.plugin.root NAME : the plugin's own folder (a directory plugin) or its single file
tui.plugin.root() { local f="${_TPL_FILE[$1]:-}"; [[ -n "$f" ]] || return 1; if [[ "${_TPL_KIND[$1]}" == dir ]]; then printf '%s\n' "${f%/plugin.sh}"; else printf '%s\n' "$f"; fi; }
# tui.plugin.files NAME : every file of the plugin, one per line (recursive for a directory plugin)
tui.plugin.files() {
    local root; root="$(tui.plugin.root "$1")" || return 1
    [[ -d "$root" ]] || { printf '%s\n' "$root"; return 0; }
    _tui_plugin.walk "$root"
}
_tui_plugin.walk() { local f; for f in "$1"/*; do if [[ -d "$f" ]]; then _tui_plugin.walk "$f"; elif [[ -f "$f" ]]; then printf '%s\n' "$f"; fi; done; }
# tui.plugin.stats NAME : key=value lines: files dirs bytes lines functions + what the plugin has registered while enabled
tui.plugin.stats() {
    local n="$1" f line t root files=0 dirs=0 bytes=0 lines=0 funcs=0 c b
    root="$(tui.plugin.root "$n")" || return 1
    if [[ -d "$root" ]]; then
        dirs=$(( $(find "$root" -type d 2>/dev/null | wc -l) - 1 ))
    fi
    while IFS= read -r f; do
        [[ -f "$f" ]] || continue
        (( files++ ))
        c="$(<"$f")"; bytes=$(( bytes + ${#c} + 1 ))
        while IFS= read -r line; do
            (( lines++ ))
            [[ "$line" =~ ^[[:space:]]*(function[[:space:]]+)?[A-Za-z_.][A-Za-z0-9_.:-]*[[:space:]]*\(\)[[:space:]]*\{? ]] && (( funcs++ ))
        done <<< "$c"
    done < <(tui.plugin.files "$n")
    printf 'files=%s\ndirs=%s\nbytes=%s\nlines=%s\nfunctions=%s\n' "$files" "$dirs" "$bytes" "$lines" "$funcs"
    local -A own=()
    while IFS= read -r line; do [[ -n "$line" ]] && (( own[${line%%$'\t'*}]++ )); done <<< "${_TPL_OWN[$n]:-}"
    printf 'commands=%s\nbinds=%s\nhooks=%s\ntimers=%s\nticks=%s\noverlays=%s\nproviders=%s\n' "${own[cmd]:-0}" "${own[bind]:-0}" "${own[hook]:-0}" "${own[every]:-0}" "${own[tick]:-0}" "${own[overlay]:-0}" "${own[provider]:-0}"
}
tui.plugin.dir() { local f="${_TPL_FILE[$1]:-}"; [[ -n "$f" ]] && printf '%s\n' "${f%/*}"; }
tui.plugin.info() {
    local n="$1"
    [[ -n "${_TPL_FILE[$n]:-}" ]] || return 1
    printf '%s  %s\n%s\n\n' "${_TPL_TITLE[$n]}" "v${_TPL_VER[$n]}" "${_TPL_DESC[$n]:-(no description)}"
    printf 'id        %s\nstate     %s%s\nsource    %s\nfile      %s\n' "$n" "${_TPL_STATE[$n]}" "${_TPL_ERR[$n]:+  (${_TPL_ERR[$n]})}" "${_TPL_SRC[$n]}" "${_TPL_FILE[$n]/#$HOME/~}"
    [[ -n "${_TPL_AUTHOR[$n]}" ]] && printf 'author    %s\n' "${_TPL_AUTHOR[$n]}"
    [[ -n "${_TPL_REQ[$n]}" ]] && printf 'requires  %s\n' "${_TPL_REQ[$n]}"
    return 0
}
tui.plugin.config() {
    if (( $# >= 3 )); then tui.config.set "plugin.$1.$2" "$3"; else tui.config.get "plugin.$1.$2" "${3:-}"; fi
}

# ── startup: discover, then enable what the user (or the plugin's default) wants ─────────────────────
tui.plugin.startup() {
    local n en
    [[ -n "${TUI_NO_PLUGINS:-}" ]] && return 0                  # e.g. the installer wizard
    (( _TPL_SCANNED )) || tui.plugin.scan
    for n in "${_TPL_ORDER[@]}"; do
        en="${_TUI_CFG[plugin.$n.enabled]:-}"
        [[ -z "$en" ]] && { [[ "${_TPL_DEF[$n]}" == on ]] && en=1 || en=0; }
        [[ "$en" == 1 ]] && { tui.plugin.enable "$n" --no-save || echo "plugin $n: $TUI_PLUGIN_ERROR" >&2; }
    done
    return 0
}

# ── command bar: plugins are manageable from it ──────────────────────────
_tui_plugin.provide() {
    local n
    tui.cmd.add plugins.manage "DABT: Plugins" "tui.action.goto_default plugins" --group Plugins --desc "List, enable, disable, install and remove plugins"
    for n in "${_TPL_ORDER[@]}"; do
        if [[ "${_TPL_STATE[$n]}" == enabled ]]; then tui.cmd.add "plugin.off.$n" "Plugin: disable ${_TPL_TITLE[$n]}" "tui.plugin.disable $n" --group Plugins --desc "${_TPL_DESC[$n]}"
        else tui.cmd.add "plugin.on.$n" "Plugin: enable ${_TPL_TITLE[$n]}" "tui.plugin.enable $n" --group Plugins --desc "${_TPL_DESC[$n]}"; fi
    done
}
tui.cmd.provider _tui_plugin.provide
