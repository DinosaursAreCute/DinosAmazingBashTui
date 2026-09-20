#!/usr/bin/env bash
# tui_install.sh - installing DABT: copy the program to a PREFIX and the defaults/plugins into the DABT config home.
# No TUI in here (the wizard in share/installer and `install.sh --yes` both call tui.install.run), no network.
#
#   ~/.local/share/dabt/           PREFIX  the program: lib/ bin/ share/ docs/ examples/ VERSION ...   (replaced by updates)
#   ~/.config/DABT/                CONFIG  what you edit: defaults/ plugins/ apps/ manifest install.meta backups/
#   ~/.local/bin/dabt              BINDIR  a link to $PREFIX/bin/dabt
# When CONFIG is not the default place, $PREFIX/etc/dabt.env records it (DABT_HOME=...) so the program can find it again.
#
#   tui.install.detect                 print the existing DABT config home: ~/.config/DABT if it exists, else $DABT_HOME if that
#                                      is a folder, else nothing (rc 1)
#   tui.install.defaults               -> TUI_INSTALL_PREFIX TUI_INSTALL_CONFIG TUI_INSTALL_BINDIR (the default locations)
#   tui.install.run SRC PREFIX CONFIG [--policy override|skip|new] [--bindir DIR | --no-link] [--dry-run] [--resolver FN]
#                                      -> TUI_INSTALL_LOG (lines), plan arrays from tui_sync.sh; rc 0 ok, 1 failed, 2 nothing valid
# The release SRC is whatever folder holds VERSION, lib/, share/ (a git checkout works too).

declare -g TUI_INSTALL_PREFIX="" TUI_INSTALL_CONFIG="" TUI_INSTALL_BINDIR="" TUI_INSTALL_ERROR=""
declare -ga TUI_INSTALL_LOG=()

tui.install.defaults() {
    TUI_INSTALL_PREFIX="${XDG_DATA_HOME:-$HOME/.local/share}/dabt"
    TUI_INSTALL_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/DABT"
    TUI_INSTALL_BINDIR="$HOME/.local/bin"
}

tui.install.detect() {
    local d="${XDG_CONFIG_HOME:-$HOME/.config}/DABT"
    if [[ -d "$d" ]]; then printf '%s\n' "$d"
    elif [[ -n "${DABT_HOME:-}" && -d "$DABT_HOME" ]]; then printf '%s\n' "$DABT_HOME"
    else return 1; fi
}

# the folder must be creatable: an existing directory we can write to, or a missing one whose parent we can write to
tui.install.check_dir() {   # DIR -> rc 0 ok; TUI_INSTALL_ERROR says why not
    local d="$1" parent
    TUI_INSTALL_ERROR=""
    [[ -n "$d" ]] || { TUI_INSTALL_ERROR="empty path"; return 1; }
    [[ "$d" == /* ]] || { TUI_INSTALL_ERROR="use an absolute path (starting with /)"; return 1; }
    if [[ -e "$d" && ! -d "$d" ]]; then TUI_INSTALL_ERROR="$d is a file"; return 1; fi
    if [[ -d "$d" ]]; then [[ -w "$d" ]] || { TUI_INSTALL_ERROR="$d is not writable"; return 1; }; return 0; fi
    parent="$d"; while [[ ! -d "$parent" && "$parent" != / ]]; do parent="${parent%/*}"; [[ -n "$parent" ]] || parent=/; done
    [[ -w "$parent" ]] || { TUI_INSTALL_ERROR="cannot create $d ($parent is not writable)"; return 1; }
    return 0
}

_tui_install.log() { TUI_INSTALL_LOG+=("$1"); }

tui.install.run() {
    local src="$1" prefix="$2" conf="$3"; shift 3
    local policy="${TUI_SYNC_POLICY:-new}" bindir="" link=1 dry=0 resolver="" ver="" was=""
    while (( $# )); do
        case "$1" in
            --policy) policy="$2"; shift ;; --bindir) bindir="$2"; shift ;; --no-link) link=0 ;;
            --dry-run) dry=1 ;; --resolver) resolver="$2"; shift ;;
        esac
        shift
    done
    TUI_INSTALL_LOG=(); TUI_INSTALL_ERROR=""; TUI_SYNC_POLICY="$policy"
    src="$(cd -P "$src" 2>/dev/null && pwd -P)" || { TUI_INSTALL_ERROR="source folder not found"; return 2; }
    tui.sync.valid_source "$src" || { TUI_INSTALL_ERROR="$src is not a DABT release (needs VERSION, lib/tui.sh, share/defaults)"; return 2; }
    tui.install.check_dir "$prefix" || return 1
    tui.install.check_dir "$conf" || return 1
    read -r ver < "$src/VERSION"; ver="${ver//[[:space:]]/}"
    [[ -f "$conf/install.meta" ]] && was="upgrade"
    local same_tree=0; [[ -d "$prefix" && "$prefix" -ef "$src" ]] && same_tree=1     # a checkout used in place: only the config is installed

    if (( dry )); then
        (( same_tree )) || tui.sync.program_plan "$src" "$prefix"
        tui.sync.plan "$src" "$conf"
        _tui_install.log "dry run: nothing was written"
        return 0
    fi

    local stamp; if [[ -n "${TUI_SYNC_STAMP:-}" ]]; then stamp="$TUI_SYNC_STAMP"; else printf -v stamp '%(%Y%m%d-%H%M%S)T' -1; fi
    TUI_SYNC_STAMP="$stamp"
    mkdir -p "$conf" "$prefix" || { TUI_INSTALL_ERROR="cannot create the folders"; return 1; }
    tui.sync.apply "$src" "$conf" "$resolver" || { TUI_INSTALL_ERROR="config sync failed"; return 1; }
    if (( same_tree )); then _tui_install.log "program: left in place ($prefix is the source folder)"
    else
        tui.sync.program_apply "$src" "$prefix" "$conf/backups/$stamp" || { TUI_INSTALL_ERROR="program copy failed"; return 1; }
        _tui_install.log "program: ${#TUI_SYNC_P_ADD[@]} added, ${#TUI_SYNC_P_UPDATE[@]} changed, ${#TUI_SYNC_P_REMOVE[@]} removed -> $prefix"
    fi
    _tui_install.log "config: ${TUI_SYNC_COUNT[add]} added, ${TUI_SYNC_COUNT[update]} updated, ${TUI_SYNC_COUNT[same]} same, ${TUI_SYNC_COUNT[keep]} yours kept -> $conf"
    (( ${#TUI_SYNC_CONFLICT[@]} )) && _tui_install.log "conflicts: ${#TUI_SYNC_CONFLICT[@]} (override ${TUI_SYNC_COUNT[override]}, skipped ${TUI_SYNC_COUNT[skip]}, .new files ${TUI_SYNC_COUNT[new]})"

    # where the program finds its config again when that is not ~/.config/DABT
    mkdir -p "$prefix/etc" && printf '# written by the DABT installer\nDABT_HOME="%s"\n' "$conf" > "$prefix/etc/dabt.env"
    local now; printf -v now '%(%Y-%m-%d %H:%M:%S)T' -1
    { printf '# DABT install record\nversion=%s\nprefix=%s\nconfig=%s\nsource=%s\n' "$ver" "$prefix" "$conf" "$src"
      if [[ -n "$was" && -r "$conf/install.meta.prev" ]]; then :; fi
      printf 'updated_at=%s\n' "$now"; } > "$conf/install.meta.tmp"
    if [[ -f "$conf/install.meta" ]]; then
        local k v first="$now" pv=""
        while IFS='=' read -r k v; do case "$k" in installed_at) first="$v" ;; version) pv="$v" ;; esac; done < "$conf/install.meta"
        printf 'installed_at=%s\n' "$first" >> "$conf/install.meta.tmp"
        [[ -n "$pv" && "$pv" != "$ver" ]] && printf 'previous_version=%s\n' "$pv" >> "$conf/install.meta.tmp"
    else printf 'installed_at=%s\n' "$now" >> "$conf/install.meta.tmp"; fi
    mv -f "$conf/install.meta.tmp" "$conf/install.meta"

    if (( link )) && [[ -n "$bindir" ]]; then
        if mkdir -p "$bindir" 2>/dev/null && ln -sfn "$prefix/bin/dabt" "$bindir/dabt" 2>/dev/null; then _tui_install.log "launcher: $bindir/dabt"
        else _tui_install.log "launcher: could not link into $bindir (run $prefix/bin/dabt directly)"; fi
    fi
    local default="${XDG_CONFIG_HOME:-$HOME/.config}/DABT"
    if [[ "$conf" != "$default" ]]; then
        _tui_install.log "config is not in $default: DABT finds it through $prefix/etc/dabt.env; for other tools add  export DABT_HOME=\"$conf\"  to your shell profile"
    fi
    _tui_install.log "installed DABT $ver"
    return 0
}
