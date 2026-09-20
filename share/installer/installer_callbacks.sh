#!/usr/bin/env bash
# installer_callbacks.sh - the steps of the DABT installer wizard. Every step is a dialog; the answer calls the next step.
# State comes from install.sh:  DABT_INSTALL_SRC (the release to install), INST_PREFIX / INST_CONFIG / INST_BINDIR (proposed
# locations), INST_POLICY (how conflicts are settled without asking). Result: INST_RESULT = done | cancelled | failed.

tui.require terminal_renderer
declare -g INST_RESULT="" INST_EXISTING="" INST_MODE=fresh
declare -ga INST_LOG=()

_inst_log() { INST_LOG+=("$1"); tui.set_text inst_log "$(printf '%s\n' "${INST_LOG[@]}")"; }
_inst_home() { printf '%s' "${1/#$HOME/~}"; }

inst_visit() {
    tui.update inst_title "DABT $(<"$DABT_INSTALL_SRC/VERSION")"
    tui.set_text inst_head "$(banner_string DABT box3 2>/dev/null | sed 's/\\n/\n/g')" 2>/dev/null
    _inst_log "Installing from ${DABT_INSTALL_SRC/#$HOME/~}"
    INST_EXISTING="$(tui.install.detect)"
    if [[ -n "$INST_EXISTING" ]]; then
        local v; v="$(sed -n 's/^version=//p' "$INST_EXISTING/install.meta" 2>/dev/null)"
        _inst_log "Found an existing DABT config folder: $(_inst_home "$INST_EXISTING")${v:+ (version $v)}"
        tui.choose "DABT is already set up here" inst_existing_picked \
            "Update it: keep my changes, ask about conflicts" "Install somewhere else" "Cancel" \
            --message "Config folder: $(_inst_home "$INST_EXISTING")${v:+, installed version $v}"$'\n'"Files you changed will not be overwritten without asking." --width 66
    else
        _inst_log "No existing DABT config folder found (looked at ~/.config/DABT and \$DABT_HOME)."
        _inst_ask_location
    fi
}

inst_existing_picked() {
    case "$1" in
        0) INST_CONFIG="$INST_EXISTING"; INST_MODE=update
           # keep the program where the last install put it, when it recorded that
           local p; p="$(sed -n 's/^prefix=//p' "$INST_EXISTING/install.meta" 2>/dev/null)"; [[ -n "$p" ]] && INST_PREFIX="$p"
           _inst_summary ;;
        1) _inst_ask_location ;;
        *) _inst_cancel ;;
    esac
}

_inst_ask_location() {
    tui.choose "Where should DABT be installed?" inst_location_picked \
        "Default locations" "Let me choose the folders" \
        --message "Default:"$'\n'"  program  $(_inst_home "$INST_PREFIX")"$'\n'"  config   $(_inst_home "$INST_CONFIG")"$'\n'"  command  $(_inst_home "$INST_BINDIR")/dabt" --width 66 --cancel _inst_cancel
}
inst_location_picked() {
    case "$1" in
        0) _inst_summary ;;
        1) tui.prompt "Program folder (the code lives here):" inst_prefix_set --value "$INST_PREFIX" --validate inst_validate_dir --cancel _inst_ask_location --title "Program folder" ;;
    esac
}
inst_validate_dir() {
    tui.install.check_dir "${1/#\~/$HOME}" && return 0
    TUI_DIALOG_ERROR="$TUI_INSTALL_ERROR"; return 1
}
inst_prefix_set() {
    INST_PREFIX="${1/#\~/$HOME}"
    tui.prompt "Config folder (your settings, defaults and plugins):" inst_config_set --value "$INST_CONFIG" --validate inst_validate_dir --cancel _inst_ask_location --title "Config folder"
}
inst_config_set() { INST_CONFIG="${1/#\~/$HOME}"; _inst_summary; }

_inst_summary() {
    local extra=""
    [[ "$INST_CONFIG" != "${XDG_CONFIG_HOME:-$HOME/.config}/DABT" ]] && extra=$'\n\n'"The config folder is not ~/.config/DABT: the installer records it in the program folder so DABT finds it again."
    tui.confirm "Install DABT $(<"$DABT_INSTALL_SRC/VERSION")?"$'\n\n'"  program  $(_inst_home "$INST_PREFIX")"$'\n'"  config   $(_inst_home "$INST_CONFIG")"$'\n'"  command  $(_inst_home "$INST_BINDIR")/dabt${extra}" \
        inst_go _inst_cancel --title "Ready to install" --yes "Install" --no "Cancel" --width 70
}

# plan first: files you changed (or that were there before) are conflicts and are asked about
inst_go() {
    tui.sync.plan "$DABT_INSTALL_SRC" "$INST_CONFIG"
    tui.update inst_prog 10; _inst_log "Comparing with $(_inst_home "$INST_CONFIG") ..."
    if (( ${#TUI_SYNC_CONFLICT[@]} )); then
        _inst_log "${#TUI_SYNC_CONFLICT[@]} file(s) differ from what is already there."
        tui.sync.resolve_ui inst_run "$DABT_INSTALL_SRC"
    else inst_run; fi
}
inst_run() {
    tui.progress.set inst_prog 40; _inst_log "Copying ..."
    if tui.install.run "$DABT_INSTALL_SRC" "$INST_PREFIX" "$INST_CONFIG" --bindir "$INST_BINDIR" --resolver _tui_sync.decided; then
        local l; for l in "${TUI_INSTALL_LOG[@]}"; do _inst_log "$l"; done
        tui.progress.set inst_prog 100; tui.update inst_status "Done."
        INST_RESULT=done
        tui.message "$(printf '%s\n' "${TUI_INSTALL_LOG[@]}")"$'\n\n'"Start it with:  dabt   (or $(_inst_home "$INST_PREFIX")/bin/dabt)" inst_finish --title "DABT is installed" --width 76
    else
        INST_RESULT=failed; _inst_log "FAILED: $TUI_INSTALL_ERROR"
        tui.message "The install failed:"$'\n'"$TUI_INSTALL_ERROR" inst_finish --title "Install failed"
    fi
}
inst_finish() { tui.stop; }
_inst_cancel() { INST_RESULT=cancelled; _inst_log "Cancelled: nothing was changed."; tui.stop; }
