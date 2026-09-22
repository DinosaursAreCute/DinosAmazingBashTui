#!/usr/bin/env bash
# tui_apps.sh - installing and managing DABT applications (`dabt app ...`). Standalone: needs no tui.sh, only tui_home.sh + tui_update.sh.
#
# An application is a folder with a .dabt.metadata file (key=value, # comments) next to its files:
#   name         required   lowercase id: a-z 0-9 . _ -   ("dabt" is reserved)
#   entry        required   the script that starts it, relative to the app folder
#   version      optional   the app's version (default 0)
#   title, description, author   optional, shown by `dabt app info`
#   own_dir      optional   yes = the app lives in its own folder (~/.local/share/dabt-apps/NAME), default no =
#                           it lives in ~/.config/DABT/apps/NAME next to its settings
#   install_hook / uninstall_hook   optional   scripts (relative to the app folder) run with bash: install_hook after an install
#                           or update, uninstall_hook before a remove. Env: DABT_HOOK (install|update|uninstall), DABT_APP_NAME,
#                           DABT_APP_DIR, DABT_APP_CONF, DABT_APP_VERSION. A failing hook only warns. No hook = a warning.
#   min_dabt / max_dabt   optional   the DABT versions it works with (both inclusive)
#
# Installed apps are listed in $TUI_HOME/apps.list (name|version|dir|entry|kind|installed|source; kind = meta | forced).
#
#   tui.apps.cli ARGS...                 the `dabt app` command line
#   tui.apps.install SRC [--force] [--name N] [--entry REL]     SRC = a folder or a git URL (URL#ref for a branch/tag)
#   tui.apps.update [NAME...]            reinstall from the recorded source (no NAME = all)
#   tui.apps.remove NAME [--yes] [--purge]
#   tui.apps.list / tui.apps.info NAME
#   tui.apps.run [--entry PATH] [--force] NAME|PATH|DIR [ARGS...]
#
# An update replaces everything in the app folder except the app's own settings (dabt.conf keybinds.xml settings.conf app.meta
# terminal_shortcuts.*). Apps keep their state in $TUI_APP_CONF (~/.config/DABT/apps/NAME), which `remove` keeps unless --purge.

_TUI_APPS_SELF="${BASH_SOURCE[0]%/*}"
[[ -n "${TUI_HOME:-}" ]] || source "$_TUI_APPS_SELF/tui_home.sh"
[[ -n "${_TUI_SCAN_LOADED:-}" ]] || { source "$_TUI_APPS_SELF/tui_scan.sh"; _TUI_SCAN_LOADED=1; }
declare -F tui.version.newer >/dev/null || source "$_TUI_APPS_SELF/tui_update.sh"

declare -g TUI_APPS_LIST="${TUI_APPS_LIST:-$TUI_HOME/apps.list}"
declare -g TUI_APPS_DIR="${TUI_APPS_DIR:-$TUI_HOME/apps}"
declare -g TUI_APPS_OWN_ROOT="${TUI_APPS_OWN_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/dabt-apps}"
declare -g TUI_APPS_ERROR=""
declare -gA TUI_APP_META=()
declare -g _APP_SRC_DIR="" _APP_ORIGIN="" _TUI_APPS_CUSTOM_DEST=""
declare -g A_NAME="" A_VERSION="" A_DIR="" A_ENTRY="" A_KIND="" A_WHEN="" A_SOURCE=""
declare -ga _TUI_APPS_KEEP=(dabt.conf keybinds.xml settings.conf app.meta 'terminal_shortcuts.*')

_tui_apps.err() { TUI_APPS_ERROR="$*"; printf 'dabt app: %s\n' "$*" >&2; return 1; }

_tui_apps.valid_name() { [[ "$1" =~ ^[a-z0-9][a-z0-9._-]*$ && "$1" != dabt ]]; }
_tui_apps.valid_ver() { [[ "$1" =~ ^v?[0-9]+(\.[0-9]+)*([-+][0-9A-Za-z.]+)?$ ]]; }
# a dir dabt may write to / delete: the shared apps folder, the own_dir root, the --install-path of this call, or a dir an app was registered at
_tui_apps.registered() {
    local n v d e k w s
    [[ -r "$TUI_APPS_LIST" ]] || return 1
    while IFS='|' read -r n v d e k w s; do [[ "$d" == "$1" && "$k" != builtin ]] && return 0; done < "$TUI_APPS_LIST"
    return 1
}
_tui_apps.managed() {
    [[ -n "$1" && "$1" != *..* ]] || return 1
    [[ "$1" == "$TUI_APPS_DIR/"* || "$1" == "$TUI_APPS_OWN_ROOT/"* ]] && return 0
    [[ "$1" == /* && "$1" != / && "$1" != "$HOME" && "$1" != "$HOME/" ]] || return 1
    [[ "$1" == "${_TUI_APPS_CUSTOM_DEST:-}" ]] || _tui_apps.registered "$1"
}

# ── .dabt.metadata ───────────────────────────────────────────────────────
# tui.apps.meta_load DIR : parse + validate DIR/.dabt.metadata into TUI_APP_META; rc 1 with TUI_APPS_ERROR set
tui.apps.meta_load() {
    local dir="$1" f="$1/.dabt.metadata" line k v
    TUI_APP_META=(); TUI_APPS_ERROR=""
    [[ -f "$f" ]] || { TUI_APPS_ERROR="no .dabt.metadata in $dir"; return 1; }
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ "$line" =~ ^[[:space:]]*(#|$) || "$line" != *=* ]] && continue
        k="${line%%=*}"; v="${line#*=}"
        k="${k//[[:space:]]/}"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
        [[ "$v" == \"*\" || "$v" == \'*\' ]] && v="${v:1:${#v}-2}"
        TUI_APP_META[${k,,}]="$v"
    done < "$f"
    local name="${TUI_APP_META[name]:-}" entry="${TUI_APP_META[entry]:-}" own="${TUI_APP_META[own_dir]:-no}" x
    [[ -n "$name" ]] || { TUI_APPS_ERROR=".dabt.metadata: 'name' is missing"; return 1; }
    _tui_apps.valid_name "$name" || { TUI_APPS_ERROR=".dabt.metadata: invalid name '$name' (a-z 0-9 . _ -, not 'dabt')"; return 1; }
    [[ -n "$entry" ]] || { TUI_APPS_ERROR=".dabt.metadata: 'entry' is missing"; return 1; }
    [[ "$entry" != /* && "$entry" != *..* && -f "$dir/$entry" ]] || { TUI_APPS_ERROR=".dabt.metadata: entry '$entry' is not a file inside the app"; return 1; }
    case "${own,,}" in yes|true|1) TUI_APP_META[own_dir]=yes ;; no|false|0|"") TUI_APP_META[own_dir]=no ;; *) TUI_APPS_ERROR=".dabt.metadata: own_dir must be yes or no"; return 1 ;; esac
    for x in install_hook uninstall_hook; do
        [[ -z "${TUI_APP_META[$x]:-}" ]] && continue
        [[ "${TUI_APP_META[$x]}" != /* && "${TUI_APP_META[$x]}" != *..* && -f "$dir/${TUI_APP_META[$x]}" ]] || { TUI_APPS_ERROR=".dabt.metadata: $x '${TUI_APP_META[$x]}' is not a file inside the app"; return 1; }
    done
    for x in version min_dabt max_dabt; do
        [[ -z "${TUI_APP_META[$x]:-}" ]] && continue
        _tui_apps.valid_ver "${TUI_APP_META[$x]}" || { TUI_APPS_ERROR=".dabt.metadata: $x '${TUI_APP_META[$x]}' is not a version number"; return 1; }
        TUI_APP_META[$x]="${TUI_APP_META[$x]#v}"
    done
    [[ -n "${TUI_APP_META[version]:-}" ]] || TUI_APP_META[version]=0
    if [[ -n "${TUI_APP_META[min_dabt]:-}" && -n "${TUI_APP_META[max_dabt]:-}" ]] && tui.version.newer "${TUI_APP_META[min_dabt]}" "${TUI_APP_META[max_dabt]}"; then
        TUI_APPS_ERROR=".dabt.metadata: min_dabt is higher than max_dabt"; return 1
    fi
    return 0
}

# tui.apps.compat : does the loaded TUI_APP_META fit this DABT version? rc 1 with TUI_APPS_ERROR set
tui.apps.compat() {
    local mn="${TUI_APP_META[min_dabt]:-}" mx="${TUI_APP_META[max_dabt]:-}"
    TUI_APPS_ERROR=""
    if [[ -n "$mn" ]] && tui.version.newer "$mn" "$TUI_VERSION"; then TUI_APPS_ERROR="needs DABT $mn or newer (this is $TUI_VERSION): run  dabt update"; return 1; fi
    if [[ -n "$mx" ]] && tui.version.newer "$TUI_VERSION" "$mx"; then TUI_APPS_ERROR="needs DABT $mx or older (this is $TUI_VERSION)"; return 1; fi
    return 0
}

# ── the list of installed apps ───────────────────────────────────────────
_tui_apps.lookup() {   # NAME -> A_* ; rc 1 when not installed
    local n v d e k w s
    [[ -r "$TUI_APPS_LIST" ]] || return 1
    while IFS='|' read -r n v d e k w s; do
        [[ "$n" == "$1" ]] || continue
        A_NAME="$n" A_VERSION="$v" A_DIR="$d" A_ENTRY="$e" A_KIND="$k" A_WHEN="$w" A_SOURCE="$s"; return 0
    done < "$TUI_APPS_LIST"
    return 1
}
_tui_apps.unregister() {
    local line tmp="$TUI_APPS_LIST.tmp"
    [[ -f "$TUI_APPS_LIST" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do [[ "${line%%|*}" == "$1" ]] || printf '%s\n' "$line"; done < "$TUI_APPS_LIST" > "$tmp"
    mv -f "$tmp" "$TUI_APPS_LIST"
}
_tui_apps.register() {   # NAME VERSION DIR ENTRY KIND SOURCE
    mkdir -p "${TUI_APPS_LIST%/*}"
    _tui_apps.unregister "$1"
    [[ -s "$TUI_APPS_LIST" ]] || printf '# DABT applications: name|version|dir|entry|kind|installed|source   (managed by: dabt app)\n' > "$TUI_APPS_LIST"
    printf '%s|%s|%s|%s|%s|%(%Y-%m-%d %H:%M:%S)T|%s\n' "$1" "$2" "$3" "$4" "$5" -1 "$6" >> "$TUI_APPS_LIST"
}

# ── getting the files ────────────────────────────────────────────────────
_tui_apps.is_url() { local re='^[a-z+]+://|^git@|\.git(#.*)?$'; [[ ! -e "$1" && "$1" =~ $re ]]; }

_tui_apps.fetch() {   # SRC TMPDIR -> _APP_SRC_DIR _APP_ORIGIN
    local src="$1" tmp="$2" ref="" url
    if [[ -d "$src" ]]; then
        _APP_SRC_DIR="$(cd -P "$src" && pwd -P)"; _APP_ORIGIN="$_APP_SRC_DIR"
    elif _tui_apps.is_url "$src"; then
        command -v git >/dev/null 2>&1 || { _tui_apps.err "git is needed to install from a URL"; return 1; }
        url="$src"; [[ "$src" == *'#'* ]] && { ref="${src##*#}"; url="${src%%#*}"; }
        git clone -q --depth 1 ${ref:+--branch "$ref"} "$url" "$tmp/src" 2>"$tmp/git.log" \
            || { _tui_apps.err "git clone failed: $(tail -n1 "$tmp/git.log")"; return 1; }
        _APP_SRC_DIR="$tmp/src"; _APP_ORIGIN="$src"
    else _tui_apps.err "'$src' is neither a folder nor a git URL"; return 1; fi
}

_tui_apps.empty() { ( shopt -s nullglob dotglob; rm -rf -- "$1"/* ); }

# SRC DEST : replace DEST with SRC (no .git); in the shared apps folder the app's settings files survive
_tui_apps.copy() {
    local src="$1" dest="$2" keep f tmp
    command -v tar >/dev/null 2>&1 || { _tui_apps.err "tar is not installed"; return 1; }
    _tui_apps.managed "$dest" || { _tui_apps.err "refusing to write to $dest"; return 1; }
    tmp="$(mktemp -d)" || return 1
    if [[ -d "$dest" ]]; then
        if [[ "$dest" == "$TUI_APPS_DIR/"* ]]; then
            for keep in "${_TUI_APPS_KEEP[@]}"; do for f in "$dest"/$keep; do [[ -e "$f" ]] && mv "$f" "$tmp/"; done; done
        fi
        _tui_apps.empty "$dest"
    fi
    mkdir -p "$dest" || { rm -rf "$tmp"; return 1; }
    ( set -o pipefail; tar -C "$src" --exclude=.git -cf - . | tar -C "$dest" -xf - ) || { rm -rf "$tmp"; _tui_apps.err "copy to $dest failed"; return 1; }
    ( shopt -s nullglob dotglob; for f in "$tmp"/*; do cp -a "$f" "$dest/"; done )
    rm -rf "$tmp"
}

# DIR : delete an app folder; in the shared folder only the code (settings stay unless it is the last thing left)
_tui_apps.wipe() {
    local dir="$1" keep f
    _tui_apps.managed "$dir" || return 1
    [[ -d "$dir" ]] || return 0
    if [[ "$dir" == "$TUI_APPS_DIR/"* ]]; then
        local tmp; tmp="$(mktemp -d)" || return 1
        for keep in "${_TUI_APPS_KEEP[@]}"; do for f in "$dir"/$keep; do [[ -e "$f" ]] && mv "$f" "$tmp/"; done; done
        _tui_apps.empty "$dir"
        ( shopt -s nullglob dotglob; for f in "$tmp"/*; do mv "$f" "$dir/"; done )
        rm -rf "$tmp"; rmdir "$dir" 2>/dev/null
    else rm -rf -- "$dir"; fi
    return 0
}

# ── hooks ────────────────────────────────────────────────────────────────
# _tui_apps.hook KEY EVENT NAME DIR VERSION : run the app's KEY hook (install_hook|uninstall_hook) from DIR; warn when there is none
_tui_apps.hook() {
    local key="$1" event="$2" name="$3" dir="$4" ver="$5" h
    tui.apps.meta_load "$dir" 2>/dev/null; h="${TUI_APP_META[$key]:-}"
    if [[ -z "$h" ]]; then printf 'dabt app: warning: %s has no %s in .dabt.metadata (nothing to run on %s)\n' "$name" "$key" "$event" >&2; return 0; fi
    printf '  running %s: %s\n' "$key" "$h"
    ( cd "$dir" && DABT_HOOK="$event" DABT_APP_NAME="$name" DABT_APP_DIR="$dir" DABT_APP_CONF="$TUI_APPS_DIR/$name" DABT_APP_VERSION="$ver" bash "$h" ) \
        || printf 'dabt app: warning: %s of %s failed (exit %d)\n' "$key" "$name" "$?" >&2
    return 0
}

# the demo ships inside DABT itself: list it (never installed/removed by `dabt app`)
_tui_apps.ensure_builtin() {
    _tui_apps.lookup dabt_demo && return 0
    [[ -f "${TUI_ROOT:-}/bin/DABT_demo.sh" ]] || return 0
    _tui_apps.register dabt_demo "${TUI_VERSION:-0}" "$TUI_ROOT" bin/DABT_demo.sh builtin "$TUI_ROOT"
}

# ── install / update ─────────────────────────────────────────────────────
tui.apps.install() {
    local src="" force=0 strict=0 noscan=0 name="" entry="" tmp dir own=no version=0 kind=meta dest prev="" updating=0 n origin="" ipath="" a
    # --path PATH is sugar for a plain positional SRC (a local folder or .dapk file - no network): normalize it away up front
    # so the rest of this function (and the .dapk sniff below) only ever sees one positional source, same as always.
    local -a _norm=()
    while (( $# )); do [[ "$1" == --path ]] && { _norm+=("$2"); shift 2; continue; }; _norm+=("$1"); shift; done
    set -- "${_norm[@]}"
    # a .dapk package (file or URL): verify, show News, resolve dependencies (lib/dapk), then come back here with the verified folder
    local prev=""
    for a in "$@"; do
        if [[ ( "$a" == *.dapk || "$a" == *.zip ) && "$a" != -* && "$prev" != --origin ]]; then
            [[ -n "${_DAPK_LOADED:-}" ]] || source "$_TUI_APPS_SELF/dapk/dapk.sh"
            dapk.install.run "$@"; return $?
        fi
        prev="$a"
    done
    while (( $# )); do
        case "$1" in
            --force|-f) force=1 ;; --strict) strict=1 ;; --no-scan) noscan=1 ;; --name) name="$2"; shift ;; --entry) entry="$2"; shift ;;
            --origin) origin="$2"; shift ;; --install-path) ipath="$2"; shift ;;
            -*) _tui_apps.err "install: unknown option $1"; return 2 ;;
            *) [[ -z "$src" ]] && src="$1" || { _tui_apps.err "install: one source only"; return 2; } ;;
        esac
        shift
    done
    [[ -n "$src" ]] || { _tui_apps.err "install: give a folder or a git URL"; return 2; }
    tmp="$(mktemp -d)" || return 1
    trap 'rm -rf "$tmp"' RETURN
    _tui_apps.fetch "$src" "$tmp" || return 1
    dir="$_APP_SRC_DIR"; [[ -n "$origin" ]] && _APP_ORIGIN="$origin"
    if (( ! noscan )); then
        tui.scan.run_spin "$dir" "Scanning incoming files for vulnerabilities"; tui.scan.print
        if (( strict && TUI_SCAN_HIGH && ! force )); then _tui_apps.err "scan found $TUI_SCAN_HIGH high-risk issue(s): not installed (--force installs anyway)"; return 1; fi
        (( TUI_SCAN_HIGH )) && printf 'dabt app: warning: review the HIGH findings above before you run this app\n' >&2
    fi

    if tui.apps.meta_load "$dir"; then
        name="${TUI_APP_META[name]}"; entry="${TUI_APP_META[entry]}"; own="${TUI_APP_META[own_dir]}"; version="${TUI_APP_META[version]}"
        if ! tui.apps.compat; then
            (( force )) || { _tui_apps.err "$name: $TUI_APPS_ERROR (--force installs it anyway)"; return 1; }
            printf 'dabt app: warning: %s\n' "$TUI_APPS_ERROR" >&2
        fi
    else
        (( force )) || { _tui_apps.err "$TUI_APPS_ERROR (--force installs it anyway; run it then with: dabt app run --entry PATH NAME)"; return 1; }
        printf 'dabt app: warning: %s - installing anyway\n' "$TUI_APPS_ERROR" >&2
        kind=forced; TUI_APP_META=()
        if [[ -z "$name" ]]; then
            n="${_APP_ORIGIN%%#*}"; n="${n%/}"; n="${n##*/}"; n="${n%.git}"; n="${n,,}"; name="${n//[^a-z0-9._-]/-}"
        fi
        [[ -z "$entry" || ( "$entry" != /* && "$entry" != *..* && -f "$dir/$entry" ) ]] || { _tui_apps.err "--entry '$entry' is not a file inside the app"; return 1; }
    fi
    _tui_apps.valid_name "$name" || { _tui_apps.err "invalid app name '$name' (use --name; a-z 0-9 . _ -, not 'dabt')"; return 1; }

    if [[ -n "$ipath" ]]; then
        [[ "$ipath" == /* && "$ipath" != *..* && "$ipath" != / && "$ipath" != "$HOME" ]] || { _tui_apps.err "--install-path must be an absolute folder path (not / or your home)"; return 2; }
        dest="${ipath%/}"; _TUI_APPS_CUSTOM_DEST="$dest"
    elif [[ "$own" == yes ]]; then dest="$TUI_APPS_OWN_ROOT/$name"; else dest="$TUI_APPS_DIR/$name"; fi
    if _tui_apps.lookup "$name"; then updating=1; prev="$A_DIR"
    elif [[ ( "$own" == yes || -n "$ipath" ) && -e "$dest" ]] && [[ -n "$(ls -A "$dest" 2>/dev/null)" ]] && (( ! force )); then _tui_apps.err "$dest already exists (--force replaces it)"; return 1; fi

    _tui_apps.copy "$dir" "$dest" || { _TUI_APPS_CUSTOM_DEST=""; return 1; }
    [[ -n "$prev" && "$prev" != "$dest" ]] && _tui_apps.wipe "$prev"
    _tui_apps.register "$name" "$version" "$dest" "$entry" "$kind" "$_APP_ORIGIN"; _TUI_APPS_CUSTOM_DEST=""
    printf '%s %s %s\n  location  %s\n' "$( (( updating )) && echo Updated || echo Installed )" "$name" "$version" "$dest"
    if [[ -n "$entry" ]]; then printf '  entry     %s\n  run       dabt app run %s\n' "$entry" "$name"
    else printf '  run       dabt app run --entry PATH %s     (no entry script known: PATH is relative to the location)\n' "$name"; fi
    _tui_apps.hook install_hook "$( (( updating )) && echo update || echo install )" "$name" "$dest" "$version"
}

tui.apps.update() {
    local path="" a; local -a names=()
    while (( $# )); do
        case "$1" in --path) path="$2"; shift 2; continue ;; -*) _tui_apps.err "update: unknown option $1"; return 2 ;; *) names+=("$1") ;; esac
        shift
    done
    if [[ -n "$path" ]]; then   # update from a local folder or .dapk instead of the recorded source (works offline)
        (( ${#names[@]} == 1 )) || { _tui_apps.err "update --path: give exactly one app name"; return 2; }
        _tui_apps.lookup "${names[0]}" || { _tui_apps.err "${names[0]} is not installed"; return 1; }
        [[ "$A_KIND" == builtin ]] && { _tui_apps.err "$A_NAME ships with DABT: update it with  dabt update --path PATH"; return 1; }
        local args=("$path"); [[ "$A_KIND" == forced ]] && args+=(--force --name "$A_NAME" ${A_ENTRY:+--entry "$A_ENTRY"})
        tui.apps.install "${args[@]}"; return $?
    fi
    local n rc=0 args
    if (( ! ${#names[@]} )); then
        _tui_apps.ensure_builtin
        [[ -r "$TUI_APPS_LIST" ]] && while IFS='|' read -r n _; do [[ -n "$n" && "$n" != \#* ]] && names+=("$n"); done < "$TUI_APPS_LIST"
    fi
    (( ${#names[@]} )) || { echo "no apps installed"; return 0; }
    for n in "${names[@]}"; do
        _tui_apps.lookup "$n" || { _tui_apps.err "$n is not installed"; rc=1; continue; }
        [[ "$A_KIND" == builtin ]] && { echo "$n ships with DABT: it is updated by  dabt update"; continue; }
        args=("$A_SOURCE"); [[ "$A_KIND" == forced ]] && args+=(--force --name "$A_NAME" ${A_ENTRY:+--entry "$A_ENTRY"})
        tui.apps.install "${args[@]}" || rc=1
    done
    return $rc
}

tui.apps.remove() {
    local name="" yes=0 purge=0 a
    for a in "$@"; do case "$a" in --yes|-y) yes=1 ;; --purge) purge=1 ;; -*) _tui_apps.err "remove: unknown option $a"; return 2 ;; *) name="$a" ;; esac; done
    [[ -n "$name" ]] || { _tui_apps.err "remove: give an app name"; return 2; }
    _tui_apps.lookup "$name" || { _tui_apps.err "$name is not installed"; return 1; }
    [[ "$A_KIND" == builtin ]] && { _tui_apps.err "$name ships with DABT and cannot be removed"; return 1; }
    printf 'Will remove %s (%s)%s\n' "$name" "$A_DIR" "$( (( purge )) && echo " and its settings in $TUI_APPS_DIR/$name" )"
    if (( ! yes )); then local r; read -r -p "Remove? [y/N] " r; [[ "$r" == [yY]* ]] || { echo aborted; return 1; }; fi
    _tui_apps.hook uninstall_hook uninstall "$name" "$A_DIR" "$A_VERSION"
    if (( purge )); then _tui_apps.managed "$A_DIR" && rm -rf -- "$A_DIR"; _tui_apps.managed "$TUI_APPS_DIR/$name" && rm -rf -- "$TUI_APPS_DIR/$name"
    else _tui_apps.wipe "$A_DIR"; fi
    _tui_apps.unregister "$name"; rm -f "$TUI_HOME/apps.deps/$name"
    echo "removed $name"
}

# ── list / info / run ────────────────────────────────────────────────────
tui.apps.list() {
    local n v d e k w s any=0
    _tui_apps.ensure_builtin
    if [[ -r "$TUI_APPS_LIST" ]]; then
        while IFS='|' read -r n v d e k w s; do
            [[ -z "$n" || "$n" == \#* ]] && continue
            (( any )) || { printf '%-18s %-9s %-18s %s\n' NAME VERSION ENTRY LOCATION; any=1; }
            printf '%-18s %-9s %-18s %s\n' "$n" "$v" "${e:--}" "$d"
        done < "$TUI_APPS_LIST"
    fi
    (( any )) || echo "no apps installed (dabt app install FOLDER|GIT_URL)"
}

tui.apps.info() {
    _tui_apps.lookup "${1:-}" || { _tui_apps.err "${1:-?} is not installed"; return 1; }
    local x
    printf '%-12s %s\n' name "$A_NAME" version "$A_VERSION" location "$A_DIR" entry "${A_ENTRY:--}" source "$A_SOURCE" installed "$A_WHEN" \
        metadata "$([[ "$A_KIND" == forced ]] && echo 'none (installed with --force)' || echo present)" settings "$TUI_APPS_DIR/$A_NAME"
    if tui.apps.meta_load "$A_DIR" 2>/dev/null; then
        for x in title description author own_dir install_hook uninstall_hook min_dabt max_dabt; do [[ -n "${TUI_APP_META[$x]:-}" ]] && printf '%-12s %s\n' "$x" "${TUI_APP_META[$x]}"; done
    fi
}

tui.apps.run() {
    local entry="" force=0 target="" dir="" name="" file
    while (( $# )); do
        case "$1" in --entry) entry="$2"; shift ;; --force|-f) force=1 ;; -*) _tui_apps.err "run: unknown option $1"; return 2 ;; *) target="$1"; shift; break ;; esac
        shift
    done
    [[ -n "$target" ]] || { _tui_apps.err "run: give an app name or the path to its entry script"; return 2; }
    if _tui_apps.lookup "$target"; then
        name="$A_NAME"; dir="$A_DIR"; [[ -n "$entry" ]] || entry="$A_ENTRY"
        [[ -n "$entry" ]] || { _tui_apps.err "$name has no entry script recorded (no .dabt.metadata): dabt app run --entry PATH $name"; return 1; }
        [[ "$entry" == /* ]] && file="$entry" || file="$dir/$entry"
    elif [[ -f "$target" ]]; then
        file="$(cd -P "$(dirname "$target")" && pwd -P)/${target##*/}"; dir="${file%/*}"
    elif [[ -d "$target" ]]; then
        dir="$(cd -P "$target" && pwd -P)"
        if [[ -n "$entry" ]]; then
            [[ "$entry" != /* && "$entry" != *..* && -f "$dir/$entry" ]] || { _tui_apps.err "--entry '$entry' is not a file inside $dir"; return 1; }
            file="$dir/$entry"
        else
            tui.apps.meta_load "$dir" || { _tui_apps.err "$TUI_APPS_ERROR (pass the entry script itself, or --entry PATH)"; return 1; }
            file="$dir/${TUI_APP_META[entry]}"
        fi
    else _tui_apps.err "'$target' is not an installed app, an entry script or an app folder (see: dabt app list)"; return 1; fi
    [[ -f "$file" ]] || { _tui_apps.err "entry script not found: $file"; return 1; }
    if tui.apps.meta_load "$dir" 2>/dev/null; then
        [[ -n "$name" ]] || name="${TUI_APP_META[name]}"
        tui.apps.compat || { (( force )) && printf 'dabt app: warning: %s\n' "$TUI_APPS_ERROR" >&2 || { _tui_apps.err "$name: $TUI_APPS_ERROR (--force runs it anyway)"; return 1; }; }
    fi
    if [[ -z "$name" ]]; then name="${dir##*/}"; name="${name,,}"; name="${name//[^a-z0-9._-]/-}"; fi
    _tui_apps.valid_name "$name" || name=app
    [[ -f "$TUI_HOME/apps.deps/$name" ]] && printf 'dabt app: warning: %s has unmet dependencies: run  dabt pkg deps %s\n' "$name" "$name" >&2
    export TUI_APP_NAME="$name" DABT_APP_DIR="$dir"
    cd "$dir" && exec bash "$file" "$@"
}

# ── the command line ─────────────────────────────────────────────────────
_tui_apps.help() {
    cat <<'HELP'
dabt app - install and manage DABT applications

  dabt app install SOURCE|--path PATH [--force] [--strict] [--no-scan] [--name N] [--entry PATH] [--install-path DIR]
                          SOURCE = a folder, a git URL (URL#branch-or-tag) or a .dapk package or a .zip holding one (file or URL, see: dabt pkg help).
                          --path PATH is the same as SOURCE but only ever local (a folder or a .dapk file) - no connection needed.
                          A .dapk is verified (signature + checksums) first; extra options: --install-dependencies --yes --no-deps
                          --require-deps --allow-custom-install --trust-key SHA256:.. --allow-unsigned --plan.
                          The app needs a .dabt.metadata file;
                          The code is security-scanned first (dabt scan): --strict refuses on HIGH findings, --no-scan skips it.
                          --force installs one without it (or built for another DABT version) anyway.
  dabt app list                       installed apps and where they live
  dabt app info NAME                  details and metadata of an app
  dabt app run NAME [ARGS...]         start an installed app
  dabt app run PATH [ARGS...]         start an entry script (or an app folder) without installing it
  dabt app run --entry PATH NAME|DIR  use PATH (relative) as the entry script: for an app installed with --force, or a plain folder with no .dabt.metadata
  dabt app update [NAME...]           reinstall from the recorded source (no NAME = every app)
  dabt app update NAME --path PATH    update one app from a local folder or .dapk instead of its recorded source - no connection needed
  dabt app remove NAME [--yes] [--purge]     remove an app; --purge also deletes its settings

.dabt.metadata (key=value):  name  entry  [version title description author own_dir install_hook uninstall_hook min_dabt max_dabt]
Apps live in ~/.config/DABT/apps/NAME, or in ~/.local/share/dabt-apps/NAME when they set  own_dir=yes.
HELP
}

tui.apps.cli() {
    local cmd="${1:-}"; shift
    case "$cmd" in
        install|add)          tui.apps.install "$@" ;;
        list|ls)              tui.apps.list ;;
        info)                 tui.apps.info "$@" ;;
        run)                  tui.apps.run "$@" ;;
        update|upgrade)       tui.apps.update "$@" ;;
        remove|rm|uninstall)  tui.apps.remove "$@" ;;
        ""|-h|--help|help)    _tui_apps.help ;;
        *)                    printf "dabt app: unknown command '%s'\n\n" "$cmd" >&2; _tui_apps.help >&2; return 1 ;;
    esac
}
