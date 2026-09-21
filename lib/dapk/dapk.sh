#!/usr/bin/env bash
# dapk.sh - loader for the dapk packaging module (build, sign, verify, install, publish: docs/concepts/dapk-packaging.md).
#
# Sourcing this file loads every module below, in dependency order. Modules never call `exit` (they return status codes), keep their
# private helpers under _dapk.<module>.*, and expose public functions as dapk.<module>.*. Only cmd/*.sh turn results into exit codes.
#
# Dependencies: bash 5, tar (GNU for reproducible builds), gzip, awk, sort, sha256sum|shasum, ssh-keygen (signing), curl (publish/URLs).

[[ -n "${_DAPK_LOADED:-}" ]] && return 0
declare -g _DAPK_LOADED=1
declare -g DAPK_DIR; DAPK_DIR="$(cd -P "${BASH_SOURCE[0]%/*}" && pwd -P)"
declare -g DABT_PKG_EXT="dapk"          # the package file extension: one constant
declare -g DAPK_MANIFEST_MAGIC="# DABT-MANIFEST 1"
declare -g DAPK_SIG_NAMESPACE="dabt-pkg"

# TUI_HOME / TUI_ROOT are needed for the trust store and installed apps
[[ -n "${TUI_ROOT:-}" ]] || TUI_ROOT="$(cd -P "$DAPK_DIR/../.." && pwd -P)"
[[ -n "${TUI_HOME:-}" ]] || source "$DAPK_DIR/../tui_home.sh"

# order = dependency order (ui, toml, version have no dependencies)
for _dapk_m in ui toml version header config changelog news collect manifest pack sign verify deps notes publish ci install; do
    source "$DAPK_DIR/$_dapk_m.sh"
done
for _dapk_m in "$DAPK_DIR"/cmd/*.sh; do [[ -e "$_dapk_m" ]] && source "$_dapk_m"; done
unset _dapk_m
