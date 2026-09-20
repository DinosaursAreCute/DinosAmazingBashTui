#!/usr/bin/env bash
# install.sh - installs DABT from this folder (a git checkout or an unpacked release).
#
#   ./install.sh                  shows where it will install, asks to continue
#   ./install.sh --yes            no questions: default locations (or the ones given below), conflicts get a .new file
#
#   --prefix DIR     where the program goes            (default ~/.local/share/dabt)
#   --config DIR     the DABT config home              (default ~/.config/DABT; found again through $PREFIX/etc/dabt.env)
#   --bindir DIR     where the `dabt` command is linked (default ~/.local/bin)      --no-link   do not link it
#   --policy P       settle conflicts without asking: override | skip | new (default new = write FILE.new next to yours)
#   --dry-run        show what would be installed, change nothing
#   --no-scan        skip the security scan of the incoming files     --force   install even if the scan finds HIGH-risk issues
#
# An existing DABT is detected: ~/.config/DABT if it exists, otherwise the folder $DABT_HOME points to. Then this is an UPDATE:
# files you changed are never overwritten silently (see docs/guide/install-and-update.md).
SRC="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
yes=0; dry=0; link=1; noscan=0; force=0; policy=""; prefix=""; conf=""; bindir=""
while (( $# )); do
    case "$1" in
        --yes|-y) yes=1 ;; --dry-run) dry=1 ;; --no-link) link=0 ;; --no-scan) noscan=1 ;; --force|-f) force=1 ;;
        --prefix) prefix="$2"; shift ;; --config) conf="$2"; shift ;; --bindir) bindir="$2"; shift ;; --policy) policy="$2"; shift ;;
        -h|--help) sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
        *) echo "install.sh: unknown option $1 (try --help)" >&2; exit 2 ;;
    esac
    shift
done
source "$SRC/lib/tui_sync.sh"; source "$SRC/lib/tui_install.sh"
tui.sync.valid_source "$SRC" || { echo "install.sh: $SRC is not a DABT release (VERSION, lib/tui.sh, share/defaults are missing)" >&2; exit 2; }
tui.install.defaults
[[ -n "$prefix" ]] && TUI_INSTALL_PREFIX="$prefix"
[[ -n "$conf" ]] && TUI_INSTALL_CONFIG="$conf"
[[ -n "$bindir" ]] && TUI_INSTALL_BINDIR="$bindir"
existing="$(tui.install.detect)"
[[ -n "$existing" && -z "$conf" ]] && TUI_INSTALL_CONFIG="$existing"

# colors: only on a terminal, never with NO_COLOR
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    B=$'\e[1m' D=$'\e[2m' R=$'\e[0m' BLUE=$'\e[1;34m' GRN=$'\e[1;32m' YEL=$'\e[1;33m' RED=$'\e[1;31m' CYN=$'\e[36m'
else B= D= R= BLUE= GRN= YEL= RED= CYN=; fi
nsteps=$(( 3 + (noscan ? 0 : 1) )); stepn=0
_step() { printf '\n%s[%d/%d]%s %s%s%s\n' "$BLUE" $((++stepn)) "$nsteps" "$R" "$B" "$1" "$R"; }
_ok()   { printf '  %s✓%s %s\n' "$GRN" "$R" "$1"; }
_warn() { printf '  %s!%s %s\n' "$YEL" "$R" "$1"; }
_err()  { printf '  %s✗%s %s\n' "$RED" "$R" "$1" >&2; }
_kv()   { printf '  %s%-9s%s %s\n' "$D" "$1" "$R" "$2"; }

_scan() {
    _step "Security scan"
    source "$SRC/lib/tui_scan.sh"
    tui.scan.run_spin "$SRC" "Scanning incoming files for vulnerabilities"
    [[ -n "$TUI_SCAN_REPORT" ]] && while IFS= read -r l; do
        case "$l" in "  HIGH "*) printf '%s%s%s\n' "$RED" "$l" "$R" ;; "  WARN "*) printf '%s%s%s\n' "$YEL" "$l" "$R" ;; *) printf '%s%s%s\n' "$D" "$l" "$R" ;; esac
    done <<< "$TUI_SCAN_REPORT"
    [[ -n "$TUI_SCAN_NOTES" ]] && printf '  %snote: %s%s\n' "$D" "${TUI_SCAN_NOTES%$'\n'}" "$R"
    if (( TUI_SCAN_HIGH )); then
        _err "$TUI_SCAN_HIGH high-risk finding(s), $TUI_SCAN_WARN warning(s)"
        (( force )) && _warn "--force given: installing anyway" || { echo "install.sh: refusing to install; review the findings, then rerun with --force" >&2; exit 3; }
    elif (( TUI_SCAN_WARN )); then _warn "no high-risk findings, $TUI_SCAN_WARN warning(s)"
    else _ok "no findings"; fi
}
_run() {
    local args=(--bindir "$TUI_INSTALL_BINDIR"); (( link )) || args=(--no-link); (( dry )) && args+=(--dry-run)
    [[ -n "$policy" ]] && args+=(--policy "$policy")
    tui.install.run "$SRC" "$TUI_INSTALL_PREFIX" "$TUI_INSTALL_CONFIG" "${args[@]}"
}
_finish() {
    local rc=$1 l
    if (( rc != 0 )); then _err "$TUI_INSTALL_ERROR"; exit "$rc"; fi
    if (( dry )); then
        _ok "Would install DABT $(<"$SRC/VERSION")"; _kv program "$TUI_INSTALL_PREFIX"; _kv config "$TUI_INSTALL_CONFIG"
        tui.sync.report; printf '\n%sdry run: nothing was written%s\n' "$D" "$R"
    else
        for l in "${TUI_INSTALL_LOG[@]}"; do
            case "$l" in installed*) printf '\n%s✓ %s%s\n' "$GRN" "$l" "$R" ;; conflicts*|*"could not"*|"config is not"*) _warn "$l" ;; *) _ok "$l" ;; esac
        done
    fi
    exit 0
}

interactive=0; [[ -t 0 && -t 1 ]] && interactive=1
printf '%sD.A.B.T%s installer  %s%s%s\n' "$BLUE" "$R" "$D" "$(<"$SRC/VERSION")" "$R"
_step "Target"
_kv program "$TUI_INSTALL_PREFIX"; _kv config "$TUI_INSTALL_CONFIG"; _kv command "$TUI_INSTALL_BINDIR/dabt"
[[ -n "$existing" && "$TUI_INSTALL_CONFIG" == "$existing" ]] && _warn "existing install found: this updates it (your changes are kept)"
if (( ! yes && ! dry )); then
    if (( interactive )); then
        printf '\n%sContinue?%s [Y/n] ' "$B" "$R"; read -r a; [[ "$a" == [nN]* ]] && { echo "Nothing was changed."; exit 0; }
    else echo "install.sh: not a terminal and no --yes: refusing to guess. Use --yes." >&2; exit 2; fi
fi
(( noscan )) || _scan
_step "$( (( dry )) && echo Planning || echo Installing )"
_run; _finish $?
