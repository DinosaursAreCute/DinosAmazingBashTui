#!/usr/bin/env bash
# ui.sh - CLI presentation for the dapk module: step headers, ok/warn/err lines, logging, the progress bar. Standalone (no tui.sh state).
#
# Look: install.sh's steps ([n/N] bold blue, ✓ green, ! yellow, ✗ red, dim key/value). The progress bar copies tui.cache.warm_with_spinner:
# 30 cells, ▕█░▏, pink -> blue -> yellow -> red gradient by position (truecolor when COLORTERM says so, else 256 colors); ASCII when not UTF-8.
# Human output goes to stderr; only results (paths, data) go to stdout. A plain-text log is always written when DAPK_UI_LOG_FILE is set.
#
# Configure before dapk.ui.init:  DAPK_UI_QUIET=1 DAPK_UI_VERBOSE=1 DAPK_UI_LOG_FILE=PATH DAPK_UI_STRICT=1 DAPK_UI_PROGRESS_MODE=auto|on|off
# Public:  dapk.ui.init  dapk.ui.step TITLE  dapk.ui.ok|warn|err|info|debug|kv  dapk.ui.summary
#          dapk.ui.progress_start LABEL TOTAL | progress_tick [N] | progress_done [MSG]      dapk.ui.run LABEL CMD...     dapk.ui.bar PCT WIDTH VAR
#          dapk.ui.ci  dapk.ui.cleanup  dapk.ui.confirm PROMPT [default y|n]

[[ -n "${_DAPK_UI_LOADED:-}" ]] && return 0
declare -g _DAPK_UI_LOADED=1
declare -g DAPK_UI_QUIET="${DAPK_UI_QUIET:-0}" DAPK_UI_VERBOSE="${DAPK_UI_VERBOSE:-0}" DAPK_UI_STRICT="${DAPK_UI_STRICT:-0}"
declare -g DAPK_UI_LOG_FILE="${DAPK_UI_LOG_FILE:-}" DAPK_UI_PROGRESS_MODE="${DAPK_UI_PROGRESS_MODE:-auto}"
declare -g DAPK_UI_CI=0 DAPK_UI_COLOR=0 DAPK_UI_UTF8=0 DAPK_UI_PROGRESS=0 DAPK_UI_COLS=80
declare -g DAPK_UI_STEP=0 DAPK_UI_STEPS=0 DAPK_UI_GROUP=0
declare -g _DAPK_UI_TMP="" _DAPK_UI_FD="" _DAPK_UI_INITED=0
declare -g _PG_LABEL="" _PG_TOTAL=0 _PG_CUR=0 _PG_LAST=-1 _PG_ACTIVE=0
declare -ga DAPK_UI_WARNINGS=() _DAPK_UI_PAL=()
declare -g B="" D="" R="" BLUE="" GRN="" YEL="" RED="" CYN="" _G245="" _G250="" _G238=""

dapk.ui.ci() { [[ -n "${CI:-}${GITHUB_ACTIONS:-}${GITLAB_CI:-}${JENKINS_URL:-}${BUILDKITE:-}${TF_BUILD:-}" ]]; }

dapk.ui.init() {
    (( _DAPK_UI_INITED )) && return 0
    _DAPK_UI_INITED=1
    dapk.ui.ci && DAPK_UI_CI=1
    local tty=0; [[ -t 2 ]] && tty=1
    if [[ -z "${NO_COLOR:-}" && ( $tty == 1 || -n "${FORCE_COLOR:-}" ) ]]; then DAPK_UI_COLOR=1; fi
    case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) DAPK_UI_UTF8=1 ;; esac
    case "$DAPK_UI_PROGRESS_MODE" in
        on) DAPK_UI_PROGRESS=1 ;; off) DAPK_UI_PROGRESS=0 ;;
        *) (( tty && ! DAPK_UI_CI )) && DAPK_UI_PROGRESS=1 ;;
    esac
    if (( tty )); then local _r _c; read -r _r _c < <(stty size 2>/dev/null </dev/tty) && [[ "$_c" =~ ^[0-9]+$ ]] && DAPK_UI_COLS="$_c"; fi
    if (( DAPK_UI_COLOR )); then
        B=$'\e[1m' D=$'\e[2m' R=$'\e[0m' BLUE=$'\e[1;34m' GRN=$'\e[1;32m' YEL=$'\e[1;33m' RED=$'\e[1;31m' CYN=$'\e[36m'
        _G245=$'\e[38;5;245m' _G250=$'\e[38;5;250m' _G238=$'\e[38;5;238m'
        if [[ "${COLORTERM:-}" == *truecolor* || "${COLORTERM:-}" == *24bit* ]]; then
            _DAPK_UI_PAL=($'\e[38;2;255;140;191m' $'\e[38;2;168;216;255m' $'\e[38;2;255;243;168m' $'\e[38;2;255;158;158m')
        else _DAPK_UI_PAL=($'\e[38;5;212m' $'\e[38;5;153m' $'\e[38;5;229m' $'\e[38;5;217m'); fi
    else _DAPK_UI_PAL=("" "" "" ""); fi
    if [[ -n "$DAPK_UI_LOG_FILE" ]]; then
        mkdir -p "$(dirname "$DAPK_UI_LOG_FILE")" 2>/dev/null && : > "$DAPK_UI_LOG_FILE" 2>/dev/null || DAPK_UI_LOG_FILE=""
    fi
    return 0
}

# _dapk.ui.log LEVEL TEXT : append to the log file (plain text, secrets masked)
_dapk.ui.log() {
    [[ -n "$DAPK_UI_LOG_FILE" ]] || return 0
    local m="$2" t
    for t in "${GITHUB_TOKEN:-}" "${GH_TOKEN:-}"; do [[ -n "$t" ]] && m="${m//"$t"/***}"; done
    [[ "$m" == *[Bb]earer\ * ]] && m="${m//[Bb]earer [^ ]*/Bearer ***}"
    printf '%(%Y-%m-%dT%H:%M:%S)T %-5s %s\n' -1 "$1" "$m" >> "$DAPK_UI_LOG_FILE"
}

_dapk.ui.group_end() { (( DAPK_UI_GROUP )) && { [[ -n "${GITHUB_ACTIONS:-}" ]] && printf '::endgroup::\n' >&2; DAPK_UI_GROUP=0; }; return 0; }

dapk.ui.steps() { DAPK_UI_STEPS="$1"; DAPK_UI_STEP=0; }
dapk.ui.step() {
    _dapk.ui.group_end
    (( ++DAPK_UI_STEP ))
    _dapk.ui.log INFO "[$DAPK_UI_STEP/$DAPK_UI_STEPS] $1"
    (( DAPK_UI_QUIET )) && return 0
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then printf '::group::[%d/%d] %s\n' "$DAPK_UI_STEP" "$DAPK_UI_STEPS" "$1" >&2; DAPK_UI_GROUP=1
    else printf '\n%s[%d/%d]%s %s%s%s\n' "$BLUE" "$DAPK_UI_STEP" "$DAPK_UI_STEPS" "$R" "$B" "$1" "$R" >&2; fi
}
dapk.ui.ok()    { _dapk.ui.log INFO "ok: $1"; (( DAPK_UI_QUIET )) || printf '  %s✓%s %s\n' "$GRN" "$R" "$1" >&2; }
dapk.ui.info()  { _dapk.ui.log INFO "$1"; (( DAPK_UI_QUIET )) || printf '  %s\n' "$1" >&2; }
dapk.ui.kv()    { _dapk.ui.log INFO "$1: $2"; (( DAPK_UI_QUIET )) || printf '  %s%-10s%s %s\n' "$D" "$1" "$R" "$2" >&2; }
dapk.ui.debug() { _dapk.ui.log DEBUG "$1"; (( DAPK_UI_VERBOSE )) && printf '  %s%s%s\n' "$D" "$1" "$R" >&2; return 0; }
dapk.ui.warn()  {
    DAPK_UI_WARNINGS+=("$1"); _dapk.ui.log WARN "$1"
    [[ -n "${GITHUB_ACTIONS:-}" ]] && printf '::warning::%s\n' "$1" >&2
    printf '  %s!%s %s\n' "$YEL" "$R" "$1" >&2
}
dapk.ui.err()   {
    _dapk.ui.log ERROR "$1"
    [[ -n "${GITHUB_ACTIONS:-}" ]] && printf '::error::%s\n' "$1" >&2
    printf '  %s✗%s %s\n' "$RED" "$R" "$1" >&2
}
# dapk.ui.summary : "N warning(s)" + the list; rc 1 when --strict and there were warnings
dapk.ui.summary() {
    _dapk.ui.group_end
    local n=${#DAPK_UI_WARNINGS[@]} w
    (( n )) || return 0
    printf '\n%s%d warning%s%s\n' "$YEL" "$n" "$( (( n == 1 )) || echo s )" "$R" >&2
    for w in "${DAPK_UI_WARNINGS[@]}"; do printf '  %s- %s%s\n' "$D" "$w" "$R" >&2; done
    (( DAPK_UI_STRICT )) && return 1
    return 0
}

# dapk.ui.confirm PROMPT [y|n] : ask on the terminal; rc 0 = yes. Not a terminal -> rc 2 (cannot ask).
dapk.ui.confirm() {
    [[ -t 0 ]] || return 2
    local def="${2:-n}" a hint="[y/N]"; [[ "$def" == y ]] && hint="[Y/n]"
    printf '\n%s%s%s %s ' "$B" "$1" "$R" "$hint" >&2
    read -r a; a="${a:-$def}"; [[ "$a" == [yY]* ]]
}

# ── progress bar ──────────────────────────────────────────────────────
# dapk.ui.bar PCT WIDTH VAR : the bar (caps + cells) into VAR
dapk.ui.bar() {
    local pct="$1" w="${2:-30}" _v="$3" c _o="" fill empty cl cr filled
    (( pct < 0 )) && pct=0; (( pct > 100 )) && pct=100
    filled=$(( pct * w / 100 ))
    if (( DAPK_UI_UTF8 )); then fill="█" empty="░" cl="▕" cr="▏"; else fill="#" empty="-" cl="[" cr="]"; fi
    for (( c = 0; c < w; c++ )); do
        if (( c < filled )); then _o+="${_DAPK_UI_PAL[c * 4 / w]}$fill"; else _o+="${_G238}$empty"; fi
    done
    printf -v "$_v" '%s' "${_G245}${cl}${_o}${_G245}${cr}${R}"
}

_dapk.ui.prefix() {   # OFFSET -> _PFX : "DABT:" with the four logo pastels (rotated by OFFSET)
    local off="${1:-0}" i s="DABT" out=""
    for (( i = 0; i < 4; i++ )); do out+="${_DAPK_UI_PAL[(i + off) % 4]}${B}${s:i:1}"; done
    _PFX="${out}${_G250}:${R}"
}

_dapk.ui.paint() {   # PCT
    local bar pct="$1"
    _dapk.ui.prefix 0
    if (( DAPK_UI_COLS < 60 )); then printf '\r\e[K%s %s(%s)%s %3d%%' "$_PFX" "$_G250" "$_PG_LABEL" "$R" "$pct" >&2
    else dapk.ui.bar "$pct" 30 bar; printf '\r\e[K%s %s(%s)%s  %s  %s%3d%%%s' "$_PFX" "$_G250" "$_PG_LABEL" "$R" "$bar" "$_G250" "$pct" "$R" >&2; fi
}

dapk.ui.progress_start() {
    _PG_LABEL="$1" _PG_TOTAL="${2:-0}" _PG_CUR=0 _PG_LAST=-1 _PG_ACTIVE=1
    _dapk.ui.log INFO "progress: $1 ($_PG_TOTAL)"
    (( DAPK_UI_PROGRESS && ! DAPK_UI_QUIET )) && _dapk.ui.paint 0 && _PG_LAST=0
    return 0
}
# dapk.ui.progress_tick [N] : N = absolute count (default: +1). Repaints only when the integer percent changes.
dapk.ui.progress_tick() {
    (( _PG_ACTIVE )) || return 0
    if [[ -n "${1:-}" ]]; then _PG_CUR="$1"; else (( _PG_CUR++ )); fi
    (( DAPK_UI_PROGRESS && ! DAPK_UI_QUIET )) || return 0
    local pct=100; (( _PG_TOTAL > 0 )) && pct=$(( 100 * _PG_CUR / _PG_TOTAL ))
    (( pct > 100 )) && pct=100
    (( pct == _PG_LAST )) && return 0
    _PG_LAST=$pct; _dapk.ui.paint "$pct"
}
dapk.ui.progress_done() {
    (( _PG_ACTIVE )) || return 0
    _PG_ACTIVE=0
    (( DAPK_UI_PROGRESS && ! DAPK_UI_QUIET )) && printf '\r\e[K' >&2
    dapk.ui.ok "${1:-$_PG_LABEL}"
}

# sleep without a fork: read with a timeout on a fifo nobody writes to (same idea as the cache spinner's polling)
_dapk.ui.sleep() {
    if [[ -z "$_DAPK_UI_FD" ]]; then
        [[ -n "$_DAPK_UI_TMP" ]] || _DAPK_UI_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dapk_ui.XXXXXX")" || return 1
        mkfifo "$_DAPK_UI_TMP/sleep" && exec {_DAPK_UI_FD}<>"$_DAPK_UI_TMP/sleep" || return 1
    fi
    read -r -t "$1" -u "$_DAPK_UI_FD" _ 2>/dev/null; return 0
}

# dapk.ui.run LABEL CMD... : run CMD with its output captured to the log; the DABT letters rotate every 400 ms on a terminal.
# Returns CMD's status; on failure the last lines of its output are shown.
dapk.ui.run() {
    local label="$1" out rc off=0 pid; shift
    [[ -n "$_DAPK_UI_TMP" ]] || _DAPK_UI_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dapk_ui.XXXXXX")" || return 1
    out="$_DAPK_UI_TMP/run.out"; : > "$out"
    _dapk.ui.log INFO "run: $*"
    if (( DAPK_UI_PROGRESS && ! DAPK_UI_QUIET )); then
        "$@" >"$out" 2>&1 & pid=$!
        _PG_LABEL="$label"
        while kill -0 "$pid" 2>/dev/null; do
            _dapk.ui.prefix "$off"; printf '\r\e[K%s %s(%s)%s' "$_PFX" "$_G250" "$label" "$R" >&2
            off=$(( (off + 1) % 4 )); _dapk.ui.sleep 0.4
        done
        wait "$pid"; rc=$?
        printf '\r\e[K' >&2
    else
        "$@" >"$out" 2>&1; rc=$?
    fi
    [[ -n "$DAPK_UI_LOG_FILE" ]] && cat "$out" >> "$DAPK_UI_LOG_FILE"
    (( DAPK_UI_VERBOSE )) && cat "$out" >&2
    if (( rc )); then dapk.ui.err "$label failed (exit $rc)"; (( DAPK_UI_VERBOSE )) || tail -n 5 "$out" | sed 's/^/      /' >&2; else dapk.ui.ok "$label"; fi
    return $rc
}

dapk.ui.cleanup() {
    [[ -n "$_DAPK_UI_FD" ]] && { exec {_DAPK_UI_FD}>&-; _DAPK_UI_FD=""; }
    [[ -n "$_DAPK_UI_TMP" && -d "$_DAPK_UI_TMP" ]] && rm -rf "$_DAPK_UI_TMP"
    _DAPK_UI_TMP=""
}
