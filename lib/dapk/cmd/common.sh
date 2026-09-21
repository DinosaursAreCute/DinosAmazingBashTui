#!/usr/bin/env bash
# cmd/common.sh - helpers shared by the command layer: option parsing for the common flags, exit-code mapping, command dispatch.
#
# Exit codes: 0 ok, 1 failure, 2 usage error, 3 refused. Only this layer (and bin/dabt) turns results into exit codes.

# _dapk.cmd.ui ARG NEXT : consume a common UI flag; sets _UI_SHIFT (1 or 2) and returns 0 when ARG was one
_dapk.cmd.ui() {
    case "$1" in
        -v|--verbose)  DAPK_UI_VERBOSE=1; _UI_SHIFT=1 ;;
        -q|--quiet)    DAPK_UI_QUIET=1; _UI_SHIFT=1 ;;
        --log)         DAPK_UI_LOG_FILE="$2"; _UI_SHIFT=2 ;;
        --progress)    DAPK_UI_PROGRESS_MODE=on; _UI_SHIFT=1 ;;
        --no-progress) DAPK_UI_PROGRESS_MODE=off; _UI_SHIFT=1 ;;
        --strict)      DAPK_UI_STRICT=1; _UI_SHIFT=1 ;;
        *) return 1 ;;
    esac
}

# _dapk.cmd.usage MESSAGE : print a usage error, rc 2
_dapk.cmd.usage() { printf 'dabt: %s\n' "$1" >&2; return 2; }

# _dapk.cmd.finish RC : print the warnings summary, clean up, and turn --strict warnings into a failure
_dapk.cmd.finish() {
    local rc="$1"
    dapk.ui.summary || { (( rc == 0 )) && { rc=1; dapk.ui.err "warnings treated as errors (--strict)"; }; }
    dapk.verify.cleanup; dapk.sign.cleanup; dapk.ui.cleanup
    return "$rc"
}

_dapk.cmd.help() {
    cat <<'HELP'
dabt build / dabt pkg - package, sign, verify, release and publish DABT applications (.dapk)

  dabt build [DIR] [--suffix dev|prerelease|rc.N] [--out DIR] [--key FILE | --no-sign] [--plan] [--allow-external]
             [-f|--file -s SRC -t DEST] [-d|--directory -s SRC -t DEST [-r|--recursive]]...
                                   build DIR/dist/<name>-<version>+<build>.dapk (+ .sha256, -news.txt, RELEASE_NOTES.md, build.log)
  dabt pkg verify PKG [--trust-key SHA256:..] [--allow-unsigned]
  dabt pkg info PKG                descriptor, dependencies and News of a package (no extraction)
  dabt pkg news SRC [--since VER]  News bullets from a .dapk, a -news.txt (file or URL) or a CHANGELOG.md
  dabt pkg version [show | bump patch|minor|major]
  dabt pkg release [patch|minor|major|X.Y.Z] [--push] [--no-commit]     bump VERSION, close the changelog's Unreleased section, commit + tag
  dabt pkg notes [DIR]             render the release notes to stdout
  dabt pkg publish [--draft|--prerelease|--release] [--suffix S] [--dry-run] [DIR]    GitHub release (needs GITHUB_TOKEN and publish_repo)
  dabt pkg deps [APP|PKG|DIR] [--install-dependencies] [--yes] [--no-deps] [--pm NAME]     check (and install) declared dependencies
  dabt pkg include add|list|rm    edit the [[include]] entries of dabt.pkg      dabt pkg dep add|list|rm     edit [[dependency]] entries
  dabt pkg ci init github|gitlab [--force]    copy a CI workflow into the project
  dabt app install PKG.dapk|URL   install a package (see: dabt app help)

Common options: -v|--verbose  -q|--quiet  --log FILE  --progress|--no-progress  --strict (warnings fail)
HELP
}

dapk.cmd.dispatch() {
    local cmd="${1:-}"; shift
    case "$cmd" in
        build|verify|info|news|version|release|notes|publish|deps|include|dep|ci) "dapk.cmd.$cmd" "$@" ;;
        ""|-h|--help|help) _dapk.cmd.help ;;
        *) printf "dabt pkg: unknown command '%s'\n\n" "$cmd" >&2; _dapk.cmd.help >&2; return 2 ;;
    esac
}
