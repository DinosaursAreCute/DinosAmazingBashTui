#!/usr/bin/env bash
# install.sh - installs DABT from this folder (a git checkout or an unpacked release).
#
#   ./install.sh                  a small DABT wizard asks: default locations, or your own
#   ./install.sh --yes            no questions: default locations (or the ones given below), conflicts get a .new file
#
#   --prefix DIR     where the program goes            (default ~/.local/share/dabt)
#   --config DIR     the DABT config home              (default ~/.config/DABT; found again through $PREFIX/etc/dabt.env)
#   --bindir DIR     where the `dabt` command is linked (default ~/.local/bin)      --no-link   do not link it
#   --policy P       settle conflicts without asking: override | skip | new (default new = write FILE.new next to yours)
#   --dry-run        show what would be installed, change nothing        --no-tui   never start the wizard
#
# An existing DABT is detected: ~/.config/DABT if it exists, otherwise the folder $DABT_HOME points to. Then this is an UPDATE:
# files you changed are never overwritten silently (see docs/guide/install-and-update.md).
SRC="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
yes=0; notui=0; dry=0; link=1; policy=""; prefix=""; conf=""; bindir=""
while (( $# )); do
    case "$1" in
        --yes|-y) yes=1 ;; --no-tui) notui=1 ;; --dry-run) dry=1 ;; --no-link) link=0 ;;
        --prefix) prefix="$2"; shift ;; --config) conf="$2"; shift ;; --bindir) bindir="$2"; shift ;; --policy) policy="$2"; shift ;;
        -h|--help) sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
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

_run() {
    local args=(--bindir "$TUI_INSTALL_BINDIR"); (( link )) || args=(--no-link); (( dry )) && args+=(--dry-run)
    [[ -n "$policy" ]] && args+=(--policy "$policy")
    tui.install.run "$SRC" "$TUI_INSTALL_PREFIX" "$TUI_INSTALL_CONFIG" "${args[@]}"
}
_finish() {
    local rc=$1
    if (( rc != 0 )); then echo "install.sh: $TUI_INSTALL_ERROR" >&2; exit "$rc"; fi
    if (( dry )); then
        echo "Would install DABT $(<"$SRC/VERSION") to:"; echo "  program  $TUI_INSTALL_PREFIX"; echo "  config   $TUI_INSTALL_CONFIG"
        tui.sync.report; echo "(dry run: nothing was written)"
    else printf '%s\n' "${TUI_INSTALL_LOG[@]}"; fi
    exit 0
}

interactive=0; [[ -t 0 && -t 1 ]] && interactive=1
if (( yes || notui || dry )) || (( ! interactive )); then
    if (( ! yes && ! dry )); then
        # plain questions on the terminal
        if (( interactive )); then
            printf 'Install DABT %s\n  program  %s\n  config   %s%s\n  command  %s/dabt\n' "$(<"$SRC/VERSION")" "$TUI_INSTALL_PREFIX" "$TUI_INSTALL_CONFIG" "${existing:+   (existing install found: this updates it)}" "$TUI_INSTALL_BINDIR"
            printf 'Continue? [Y/n] '; read -r a; [[ "$a" == [nN]* ]] && { echo "Nothing was changed."; exit 0; }
        else echo "install.sh: not a terminal and no --yes: refusing to guess. Use --yes." >&2; exit 2; fi
    fi
    _run; _finish $?
fi

# the wizard: DABT itself, using a throw-away config home so that nothing appears in yours before you agreed
export TUI_HOME="$(mktemp -d)" TUI_NO_PLUGINS=1 TUI_APP_NAME=dabt_installer
trap 'rm -rf "$TUI_HOME"' EXIT
export DABT_INSTALL_SRC="$SRC"
INST_PREFIX="$TUI_INSTALL_PREFIX"; INST_CONFIG="$TUI_INSTALL_CONFIG"; INST_BINDIR="$TUI_INSTALL_BINDIR"; INST_POLICY="$policy"
source "$SRC/lib/tui.sh"
tui.start "$SRC/share/installer/installer.xml"
case "$INST_RESULT" in
    done)      printf '%s\n' "${TUI_INSTALL_LOG[@]}" ;;
    cancelled) echo "Cancelled. Nothing was changed." ;;
    *)         echo "install.sh: ${TUI_INSTALL_ERROR:-the installer did not finish}" >&2; exit 1 ;;
esac
