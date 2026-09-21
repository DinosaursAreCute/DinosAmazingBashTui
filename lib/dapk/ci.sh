#!/usr/bin/env bash
# ci.sh - copies a CI template (share/ci/) into a project.
# dapk.ci.init PROVIDER DIR [force]   PROVIDER = github | gitlab. rc 1 with DAPK_CI_ERROR set. Prints the written path in DAPK_CI_PATH.
declare -g DAPK_CI_ERROR="" DAPK_CI_PATH=""

dapk.ci.init() {
    local provider="$1" dir="$2" force="${3:-0}" src dest
    DAPK_CI_ERROR=""
    case "$provider" in
        github) src="$TUI_ROOT/share/ci/github-actions.yml"; dest="$dir/.github/workflows/dabt-release.yml" ;;
        gitlab) src="$TUI_ROOT/share/ci/gitlab-ci.yml"; dest="$dir/.gitlab-ci.yml" ;;
        *) DAPK_CI_ERROR="unknown provider '$provider' (github or gitlab)"; return 1 ;;
    esac
    [[ -r "$src" ]] || { DAPK_CI_ERROR="template missing: $src"; return 1; }
    [[ ! -e "$dest" || "$force" == 1 ]] || { DAPK_CI_ERROR="$dest exists (--force overwrites it)"; return 1; }
    mkdir -p "$(dirname "$dest")" && cp -- "$src" "$dest" || { DAPK_CI_ERROR="cannot write $dest"; return 1; }
    DAPK_CI_PATH="$dest"
}
