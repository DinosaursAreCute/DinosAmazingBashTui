#!/usr/bin/env bash
# tui_update.sh - updating DABT from its public GitHub repository: check for a newer version, download it, show exactly what would
# change, let you resolve conflicts (override / skip / write a .new file), then apply. Built on tui_sync.sh (the comparing and copying).
#
#   tui.update.check                 -> TUI_UPDATE_LATEST ; rc 0 newer version available, 1 up to date, 2 could not check (TUI_UPDATE_ERROR)
#   tui.update.download DIR          download + unpack the latest release into DIR/src ; rc 0 ok
#   tui.update.plan SRC              compare SRC with what is installed -> the plan arrays of tui_sync.sh, TUI_UPDATE_GIT (1 = TUI_ROOT is a git checkout)
#   tui.update.apply SRC [RESOLVER]  apply: program files (not for a git checkout), config files with conflict handling,
#                                    install.meta -> TUI_UPDATE_RESULT (lines)
#   (channel: latest release by default; --dev / TUI_UPDATE_CHANNEL=dev = current main)
#   tui.update.cli [--check] [--yes] [--dev] [--policy override|skip|new]     the same from a terminal, no TUI (`dabt update`)
#   tui.version.newer A B            rc 0 when version A is newer than B (dotted numbers, 0.10.0 > 0.9.2)
# In the app (needs the dialogs): tui.action.update_check, tui.action.update ("DABT: Check for updates" / "DABT: Update DABT" in the
# command bar), tui.sync.resolve_ui DONE_FN (one dialog per conflict: override / skip / .new / show differences / "same for the rest").
#
# WHERE FROM: TUI_UPDATE_REPO (default DinosaursAreCute/DinosAmazingBashTui) at TUI_UPDATE_BRANCH (default main):
#   version   https://raw.githubusercontent.com/REPO/BRANCH/VERSION      (override: TUI_UPDATE_VERSION_URL)
#   archive   https://github.com/REPO/archive/refs/heads/BRANCH.tar.gz    (override: TUI_UPDATE_ARCHIVE_URL)
# Needs curl or wget, and tar. Files are only written after you confirm; the old ones are kept in $TUI_HOME/backups/.

declare -g TUI_UPDATE_REPO="${TUI_UPDATE_REPO:-DinosaursAreCute/DinosAmazingBashTui}" TUI_UPDATE_BRANCH="${TUI_UPDATE_BRANCH:-main}"
declare -g TUI_UPDATE_LATEST="" TUI_UPDATE_ERROR="" TUI_UPDATE_GIT=0 TUI_UPDATE_TIMEOUT="${TUI_UPDATE_TIMEOUT:-15}"
declare -ga TUI_UPDATE_RESULT=()

# CHANNEL: release (default) = the latest GitHub release (tag from the releases API); dev = the current state of TUI_UPDATE_BRANCH.
# The *_URL overrides win over both.
declare -g TUI_UPDATE_CHANNEL="${TUI_UPDATE_CHANNEL:-release}" TUI_UPDATE_TAG=""

_tui_update.dev() { [[ "$TUI_UPDATE_CHANNEL" == dev && -z "${TUI_UPDATE_VERSION_URL:-}" ]]; }
_tui_update.release() { [[ "$TUI_UPDATE_CHANNEL" == release && -z "${TUI_UPDATE_VERSION_URL:-}" ]]; }
_tui_update.version_url() {
    if _tui_update.release; then printf '%s' "https://api.github.com/repos/$TUI_UPDATE_REPO/releases/latest"
    else printf '%s' "${TUI_UPDATE_VERSION_URL:-https://raw.githubusercontent.com/$TUI_UPDATE_REPO/$TUI_UPDATE_BRANCH/VERSION}"; fi
}
_tui_update.archive_url() {
    if [[ -n "${TUI_UPDATE_ARCHIVE_URL:-}" ]]; then printf '%s' "$TUI_UPDATE_ARCHIVE_URL"
    elif [[ -n "$TUI_UPDATE_TAG" && "$TUI_UPDATE_CHANNEL" == release ]]; then printf '%s' "https://github.com/$TUI_UPDATE_REPO/archive/refs/tags/$TUI_UPDATE_TAG.tar.gz"
    else printf '%s' "https://github.com/$TUI_UPDATE_REPO/archive/refs/heads/$TUI_UPDATE_BRANCH.tar.gz"; fi
}

# URL DEST : rc 0 ok
_tui_update.fetch() {
    if command -v curl >/dev/null 2>&1; then curl -fsSL --max-time "$TUI_UPDATE_TIMEOUT" -o "$2" "$1" 2>/dev/null
    elif command -v wget >/dev/null 2>&1; then wget -q -T "$TUI_UPDATE_TIMEOUT" -O "$2" "$1" 2>/dev/null
    else TUI_UPDATE_ERROR="neither curl nor wget is installed"; return 1; fi
}

tui.version.newer() {
    local -a a b; local i x y
    IFS='.' read -ra a <<< "${1#v}"; IFS='.' read -ra b <<< "${2#v}"
    for (( i = 0; i < 4; i++ )); do
        x="${a[i]:-0}"; y="${b[i]:-0}"
        x="${x//[^0-9]/}"; y="${y//[^0-9]/}"; x=$(( 10#${x:-0} )); y=$(( 10#${y:-0} ))
        (( x > y )) && return 0; (( x < y )) && return 1
    done
    return 1
}

tui.update.check() {
    local tmp v; TUI_UPDATE_LATEST=""; TUI_UPDATE_ERROR=""
    tmp="$(mktemp)" || { TUI_UPDATE_ERROR="cannot create a temporary file"; return 2; }
    if ! _tui_update.fetch "$(_tui_update.version_url)" "$tmp"; then
        [[ -n "$TUI_UPDATE_ERROR" ]] || TUI_UPDATE_ERROR="could not reach $(_tui_update.version_url)"
        rm -f "$tmp"; return 2
    fi
    TUI_UPDATE_TAG=""
    if _tui_update.release; then
        v="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$tmp" | head -n1)"; rm -f "$tmp"
        [[ -n "$v" ]] || { TUI_UPDATE_ERROR="no release found (use --dev for the main branch)"; return 2; }
        TUI_UPDATE_TAG="$v"
    else read -r v < "$tmp"; rm -f "$tmp"; fi
    v="${v//[[:space:]]/}"
    [[ "$v" =~ ^v?[0-9]+(\.[0-9]+)*([-+][0-9A-Za-z.]+)?$ ]] || { TUI_UPDATE_ERROR="the answer was not a version number"; return 2; }
    TUI_UPDATE_LATEST="${v#v}"
    _tui_update.dev && return 0     # dev: always offer the current main, even at the same version
    tui.version.newer "$TUI_UPDATE_LATEST" "$TUI_VERSION"
}

tui.update.download() {
    local dir="$1" archive
    TUI_UPDATE_ERROR=""
    command -v tar >/dev/null 2>&1 || { TUI_UPDATE_ERROR="tar is not installed"; return 1; }
    mkdir -p "$dir/src" || { TUI_UPDATE_ERROR="cannot create $dir"; return 1; }
    archive="$dir/release.tar.gz"
    _tui_update.fetch "$(_tui_update.archive_url)" "$archive" || { [[ -n "$TUI_UPDATE_ERROR" ]] || TUI_UPDATE_ERROR="download failed"; return 1; }
    tar -xzf "$archive" -C "$dir/src" --strip-components=1 2>/dev/null || { TUI_UPDATE_ERROR="the download is not a valid archive"; return 1; }
    tui.sync.valid_source "$dir/src" || { TUI_UPDATE_ERROR="the download is not a DABT release"; return 1; }
    return 0
}

tui.update.plan() {
    local src="$1"
    TUI_UPDATE_GIT=0; [[ -e "$TUI_ROOT/.git" ]] && TUI_UPDATE_GIT=1
    tui.sync.plan "$src" "$TUI_HOME"
    if (( TUI_UPDATE_GIT )); then TUI_SYNC_P_ADD=(); TUI_SYNC_P_UPDATE=(); TUI_SYNC_P_SAME=(); TUI_SYNC_P_REMOVE=()
    else tui.sync.program_plan "$src" "$TUI_ROOT"; fi
    return 0
}

tui.update.apply() {
    local src="$1" resolver="${2:-}" ver="" pv="" k v first now stamp
    TUI_UPDATE_RESULT=(); TUI_UPDATE_ERROR=""
    tui.sync.valid_source "$src" || { TUI_UPDATE_ERROR="not a DABT release"; return 1; }
    read -r ver < "$src/VERSION"; ver="${ver//[[:space:]]/}"
    printf -v stamp '%(%Y%m%d-%H%M%S)T' -1; TUI_SYNC_STAMP="${TUI_SYNC_STAMP:-$stamp}"
    tui.sync.apply "$src" "$TUI_HOME" "$resolver" || { TUI_UPDATE_ERROR="config sync failed"; return 1; }
    TUI_UPDATE_RESULT+=("config: ${TUI_SYNC_COUNT[add]} added, ${TUI_SYNC_COUNT[update]} updated, ${TUI_SYNC_COUNT[keep]} yours kept, conflicts: override ${TUI_SYNC_COUNT[override]} / skip ${TUI_SYNC_COUNT[skip]} / .new ${TUI_SYNC_COUNT[new]}, removed ${TUI_SYNC_COUNT[remove]}")
    if [[ -e "$TUI_ROOT/.git" ]]; then TUI_UPDATE_RESULT+=("program: $TUI_ROOT is a git checkout - run  git pull  there for the code")
    else
        tui.sync.program_apply "$src" "$TUI_ROOT" "$TUI_HOME/backups/$TUI_SYNC_STAMP" || { TUI_UPDATE_ERROR="program copy failed"; return 1; }
        TUI_UPDATE_RESULT+=("program: ${#TUI_SYNC_P_ADD[@]} added, ${#TUI_SYNC_P_UPDATE[@]} changed, ${#TUI_SYNC_P_REMOVE[@]} removed in $TUI_ROOT")
    fi
    [[ -n "$TUI_SYNC_BACKUP" ]] && TUI_UPDATE_RESULT+=("backup of replaced files: $TUI_SYNC_BACKUP")
    printf -v now '%(%Y-%m-%d %H:%M:%S)T' -1
    first="$now"
    if [[ -f "$TUI_HOME/install.meta" ]]; then
        while IFS='=' read -r k v; do case "$k" in installed_at) first="$v" ;; version) pv="$v" ;; esac; done < "$TUI_HOME/install.meta"
    fi
    { printf '# DABT install record\nversion=%s\nprefix=%s\nconfig=%s\nsource=%s\nupdated_at=%s\ninstalled_at=%s\n' "$ver" "$TUI_ROOT" "$TUI_HOME" "$TUI_UPDATE_REPO@$TUI_UPDATE_BRANCH" "$now" "$first"
      [[ -n "$pv" && "$pv" != "$ver" ]] && printf 'previous_version=%s\n' "$pv"; } > "$TUI_HOME/install.meta.tmp" && mv -f "$TUI_HOME/install.meta.tmp" "$TUI_HOME/install.meta"
    TUI_UPDATE_RESULT+=("updated to $ver")
    return 0
}

# ── from a terminal, no TUI ──────────────────────────────────────────────
_tui_update.cli_resolver() {   # REL -> asks on the terminal (or uses the policy with --yes)
    local rel="$1" a
    if [[ -n "${_TUI_UPDATE_CLI_POLICY:-}" ]]; then printf '%s' "$_TUI_UPDATE_CLI_POLICY"; return; fi
    while true; do
        printf '\nConflict: %s  (you and the release both changed it)\n  [o]verride with the new version   [s]kip (keep mine)   [n]ew: write it as %s.new   [d]iff\n> ' "$rel" "$rel" >&2
        read -r a <&3 || a=n
        case "$a" in
            o) printf 'override'; return ;; s) printf 'skip'; return ;; n|"") printf 'new'; return ;;
            d) diff -u "$TUI_HOME/$rel" "$(_tui_sync.config_src "$_TUI_UPDATE_CLI_SRC" "$rel")" >&2 || true ;;
        esac
    done
}

tui.update.cli() {
    local check=0 yes=0 policy="" tmp rc
    exec 3< "${TUI_UPDATE_TTY:-/dev/tty}" 2>/dev/null || exec 3< /dev/null
    while (( $# )); do
        case "$1" in --check) check=1 ;; --dev) TUI_UPDATE_CHANNEL=dev ;; --release) TUI_UPDATE_CHANNEL=release ;; --yes|-y) yes=1 ;; --policy) policy="$2"; shift ;; esac
        shift
    done
    printf 'DABT %s installed. Checking %s ...\n' "$TUI_VERSION" "$(_tui_update.version_url)"
    tui.update.check; rc=$?
    case $rc in
        2) printf 'Could not check for updates: %s\n' "$TUI_UPDATE_ERROR" >&2; return 2 ;;
        1) printf 'You are up to date (latest: %s).\n' "${TUI_UPDATE_LATEST:-$TUI_VERSION}"; return 0 ;;
    esac
    printf 'A newer version is available: %s (you have %s).\n' "$TUI_UPDATE_LATEST" "$TUI_VERSION"
    (( check )) && return 10
    tmp="$(mktemp -d)" || return 1
    trap 'rm -rf "$tmp"' RETURN
    tui.update.download "$tmp" || { printf 'Download failed: %s\n' "$TUI_UPDATE_ERROR" >&2; return 1; }
    tui.update.plan "$tmp/src"
    printf '\nWhat would change:\n'; tui.sync.report
    (( TUI_UPDATE_GIT )) && printf '\n(%s is a git checkout: program files are not touched, use git pull.)\n' "$TUI_ROOT"
    if (( ! yes )); then
        printf '\nApply the update? [y/N] '; local a; read -r a <&3; [[ "$a" == [yY]* ]] || { echo "Nothing was changed."; return 0; }
    fi
    _TUI_UPDATE_CLI_SRC="$tmp/src"; _TUI_UPDATE_CLI_POLICY=""
    if (( yes )); then _TUI_UPDATE_CLI_POLICY="${policy:-new}"; elif [[ -n "$policy" ]]; then _TUI_UPDATE_CLI_POLICY="$policy"; fi
    tui.update.apply "$tmp/src" _tui_update.cli_resolver || { printf 'Update failed: %s\n' "$TUI_UPDATE_ERROR" >&2; return 1; }
    printf '\n'; printf '%s\n' "${TUI_UPDATE_RESULT[@]}"
    return 0
}

# ── inside the app: dialogs (only when tui_dialog.sh is loaded) ──────────
declare -gA TUI_SYNC_DECISION=()
declare -g  _RUI_I=0 _RUI_DONE="" _RUI_SRC="" _RUI_ALL=""

_tui_sync.decided() { printf '%s' "${TUI_SYNC_DECISION[$1]:-new}"; }

# tui.sync.resolve_ui DONE_FN [SRC] : ask about each conflict of the current plan; then call DONE_FN (decisions are in TUI_SYNC_DECISION,
# read them with `tui.sync.apply SRC CONFIG _tui_sync.decided`)
tui.sync.resolve_ui() {
    _RUI_DONE="$1"; _RUI_SRC="${2:-$_TUI_UPDATE_SRC}"; _RUI_I=0; _RUI_ALL=""; TUI_SYNC_DECISION=()
    _tui_sync.resolve_next
}
_tui_sync.resolve_next() {
    local rel
    while (( _RUI_I < ${#TUI_SYNC_CONFLICT[@]} )); do
        rel="${TUI_SYNC_CONFLICT[_RUI_I]}"
        if [[ -n "$_RUI_ALL" ]]; then TUI_SYNC_DECISION[$rel]="$_RUI_ALL"; (( _RUI_I++ )); continue; fi
        tui.choose "Conflict $(( _RUI_I + 1 )) of ${#TUI_SYNC_CONFLICT[@]}: $rel" _tui_sync.resolve_pick \
            "Override: use the new version" "Skip: keep my version" "Create $rel.new next to mine" "Show the differences" \
            "Override this and all remaining" "Skip this and all remaining" "Create .new for this and all remaining" \
            --message "You changed this file and the new release changed it too." --width 70 --selected 2 --cancel _tui_sync.resolve_cancel
        return 0
    done
    "$_RUI_DONE"
}
_tui_sync.resolve_pick() {
    local rel="${TUI_SYNC_CONFLICT[_RUI_I]}"
    case "$1" in
        0) TUI_SYNC_DECISION[$rel]=override ;; 1) TUI_SYNC_DECISION[$rel]=skip ;; 2) TUI_SYNC_DECISION[$rel]=new ;;
        3) local d; d="$(diff -u "$TUI_HOME/$rel" "$(_tui_sync.config_src "$_RUI_SRC" "$rel")" 2>&1)"; [[ -n "$d" ]] || d="(the files are identical)"
           tui.view "Differences: $rel   (- yours, + new)" "$d" --cancel _tui_sync.resolve_next; return 0 ;;
        4) _RUI_ALL=override; TUI_SYNC_DECISION[$rel]=override ;;
        5) _RUI_ALL=skip;     TUI_SYNC_DECISION[$rel]=skip ;;
        6) _RUI_ALL=new;      TUI_SYNC_DECISION[$rel]=new ;;
    esac
    (( _RUI_I++ )); _tui_sync.resolve_next
}
_tui_sync.resolve_cancel() { tui.notify "Update cancelled: nothing was changed" info 4; _tui_update.cleanup; }

declare -g _TUI_UPDATE_TMP="" _TUI_UPDATE_SRC=""
_tui_update.cleanup() { [[ -n "$_TUI_UPDATE_TMP" && -d "$_TUI_UPDATE_TMP" ]] && rm -rf "$_TUI_UPDATE_TMP"; _TUI_UPDATE_TMP=""; }

tui.action.update_check() {
    tui.notify "Checking for updates ..." info 2
    tui.update.check
    case $? in
        0) tui.confirm "DABT $TUI_UPDATE_LATEST is available (you have $TUI_VERSION)."$'\n\n'"Download it and look at what would change?" tui.action.update --title "Update available" --yes "Review" --no "Later" ;;
        1) tui.notify "DABT is up to date ($TUI_VERSION)" success 4 ;;
        *) tui.notify "Could not check for updates: $TUI_UPDATE_ERROR" error 8 ;;
    esac
}

tui.action.update() {
    tui.notify "Downloading ..." info 3
    _tui_update.cleanup; _TUI_UPDATE_TMP="$(mktemp -d)"
    if ! tui.update.download "$_TUI_UPDATE_TMP"; then tui.notify "Update failed: $TUI_UPDATE_ERROR" error 8; _tui_update.cleanup; return 1; fi
    _TUI_UPDATE_SRC="$_TUI_UPDATE_TMP/src"
    tui.update.plan "$_TUI_UPDATE_SRC"
    local newv; read -r newv < "$_TUI_UPDATE_SRC/VERSION"
    local rep; rep="$(tui.sync.report)"
    (( TUI_UPDATE_GIT )) && rep+=$'\n'"$TUI_ROOT is a git checkout: the program files stay as they are (use git pull)."
    tui.view "Update to $newv: what would change" "$rep" --cancel _tui_update.ui_reviewed
}
_tui_update.ui_reviewed() {
    if (( ${#TUI_SYNC_CONFLICT[@]} )); then tui.sync.resolve_ui _tui_update.ui_confirm "$_TUI_UPDATE_SRC"
    else _tui_update.ui_confirm; fi
}
_tui_update.ui_confirm() {
    local n=$(( ${#TUI_SYNC_P_ADD[@]} + ${#TUI_SYNC_P_UPDATE[@]} + ${#TUI_SYNC_P_REMOVE[@]} + ${#TUI_SYNC_ADD[@]} + ${#TUI_SYNC_UPDATE[@]} + ${#TUI_SYNC_REMOVE[@]} + ${#TUI_SYNC_CONFLICT[@]} ))
    tui.confirm "Apply the update ($n files affected)?"$'\n\n'"Replaced files are backed up in ${TUI_HOME/#$HOME/~}/backups." _tui_update.ui_apply _tui_update.cleanup --title "Apply update" --yes "Apply" --no "Cancel"
}
_tui_update.ui_apply() {
    if tui.update.apply "$_TUI_UPDATE_SRC" _tui_sync.decided; then
        tui.message "$(printf '%s\n' "${TUI_UPDATE_RESULT[@]}")"$'\n\n'"Restart DABT to use the new version." --title "DABT updated"
    else tui.notify "Update failed: $TUI_UPDATE_ERROR" error 8; fi
    _tui_update.cleanup
}
