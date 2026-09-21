#!/usr/bin/env bash
# cmd/version.sh - `dabt pkg version`, `dabt pkg release`, `dabt pkg notes`

dapk.cmd.version() {
    local dir="." action="show" kind="" root suffix=""
    while (( $# )); do
        case "$1" in
            show) action=show; shift ;; bump) action=bump; kind="${2:-}"; shift 2 ;;
            --suffix) suffix="${2:-}"; shift 2 ;;
            -h|--help) _dapk.cmd.help; return 0 ;;
            -*) _dapk.cmd.usage "version: unknown option $1"; return 2 ;;
            *) dir="$1"; shift ;;
        esac
    done
    root="$(cd -P "$dir" 2>/dev/null && pwd -P)" || { _dapk.cmd.usage "version: '$dir' is not a folder"; return 2; }
    dapk.version.resolve "$root" "$suffix" || { printf 'dabt: %s\n' "$DAPK_VERSION_ERROR" >&2; return 1; }
    if [[ "$action" == show ]]; then printf '%s\n' "$DAPK_FULL"; return 0; fi
    local nv; dapk.version.bump "$kind" "$DAPK_VERSION" nv || { _dapk.cmd.usage "version bump: use major, minor or patch"; return 2; }
    dapk.version.write "$root" "$nv" || return 1
    printf '%s -> %s\n' "$DAPK_VERSION" "$nv"
}

dapk.cmd.release() {
    local dir="." arg="" push=0 commit=1 root cur nv cl date tag rc=0
    while (( $# )); do
        if _dapk.cmd.ui "$1" "${2:-}"; then shift "$_UI_SHIFT"; continue; fi
        case "$1" in
            --push) push=1; shift ;; --no-commit) commit=0; shift ;;
            -h|--help) _dapk.cmd.help; return 0 ;;
            -*) _dapk.cmd.usage "release: unknown option $1"; return 2 ;;
            major|minor|patch|[0-9]*) arg="$1"; shift ;;
            *) dir="$1"; shift ;;
        esac
    done
    [[ -n "$arg" ]] || { _dapk.cmd.usage "release: give major, minor, patch or an explicit version"; return 2; }
    root="$(cd -P "$dir" 2>/dev/null && pwd -P)" || { _dapk.cmd.usage "release: '$dir' is not a folder"; return 2; }
    dapk.ui.init; dapk.ui.steps 3
    dapk.ui.step "Checking"
    dapk.config.load "$root" || { dapk.ui.err "$DAPK_CONFIG_ERROR"; _dapk.cmd.finish 1; return; }
    dapk.version.resolve "$root" || { dapk.ui.err "$DAPK_VERSION_ERROR"; _dapk.cmd.finish 1; return; }
    cur="${DAPK_VERSION%%-*}"
    case "$arg" in major|minor|patch) dapk.version.bump "$arg" "$cur" nv ;; *) nv="${arg#v}"; dapk.version.valid "$nv" || { dapk.ui.err "'$arg' is not a semantic version"; _dapk.cmd.finish 1; return; } ;; esac
    dapk.version.cmp "$nv" "$cur"; (( DAPK_VCMP > 0 )) || { dapk.ui.err "$nv is not newer than $cur"; _dapk.cmd.finish 1; return; }
    cl="${DAPK_CFG[changelog]:-}"
    if [[ -n "$cl" ]]; then
        [[ -r "$root/$cl" ]] || { dapk.ui.err "changelog '$cl' not found"; _dapk.cmd.finish 1; return; }
        dapk.changelog.unreleased_empty "$root/$cl" && { dapk.ui.err "the Unreleased section of $cl is empty: nothing to release"; _dapk.cmd.finish 1; return; }
    else dapk.ui.warn "no changelog configured"; fi
    if (( commit )) && git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
        [[ -z "$(git -C "$root" status --porcelain 2>/dev/null)" ]] || { dapk.ui.err "the working tree is not clean: commit or stash first (or use --no-commit)"; _dapk.cmd.finish 1; return; }
    fi
    dapk.ui.ok "$cur -> $nv"

    dapk.ui.step "Updating files"
    tag="v$nv"; printf -v date '%(%Y-%m-%d)T' -1
    dapk.version.write "$root" "$nv" && dapk.ui.ok "VERSION $nv"
    if [[ -n "$cl" ]]; then
        dapk.changelog.rewrite "$root/$cl" "$root/$cl.tmp" "$nv" "$date" && mv -f "$root/$cl.tmp" "$root/$cl" && dapk.ui.ok "$cl: Unreleased -> [$nv] - $date" || dapk.ui.warn "$cl has no Unreleased section"
    fi

    dapk.ui.step "Commit and tag"
    if (( commit )) && git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
        local f; for f in VERSION .dabt.metadata ${cl:+"$cl"}; do [[ -e "$root/$f" ]] && git -C "$root" add -- "$f"; done
        git -C "$root" commit -q -m "Release $tag" && git -C "$root" tag "$tag" && dapk.ui.ok "committed and tagged $tag" || { dapk.ui.err "git commit/tag failed"; rc=1; }
        (( push && rc == 0 )) && { git -C "$root" push && git -C "$root" push origin "$tag" && dapk.ui.ok "pushed" || { dapk.ui.err "git push failed"; rc=1; }; }
    else dapk.ui.info "no commit made (--no-commit or not a git repository)"; fi
    _dapk.cmd.finish "$rc"
}

dapk.cmd.notes() {
    local dir="." root stage
    while (( $# )); do
        case "$1" in -h|--help) _dapk.cmd.help; return 0 ;; -*) _dapk.cmd.usage "notes: unknown option $1"; return 2 ;; *) dir="$1"; shift ;; esac
    done
    root="$(cd -P "$dir" 2>/dev/null && pwd -P)" || { _dapk.cmd.usage "notes: '$dir' is not a folder"; return 2; }
    DAPK_UI_QUIET=1; dapk.ui.init
    dapk.config.load "$root" || { dapk.ui.err "$DAPK_CONFIG_ERROR"; return 1; }
    dapk.version.resolve "$root" || { dapk.ui.err "$DAPK_VERSION_ERROR"; return 1; }
    _dapk.cmd.epoch "$root"
    _WORK="$(mktemp -d "${TMPDIR:-/tmp}/dapk_notes.XXXXXX")" || return 1
    stage="$_WORK/${DAPK_CFG[name]}-$DAPK_FULL"
    if _dapk.cmd.prepare "$root" "$stage" && dapk.manifest.scan "$stage"; then
        _dapk.cmd.notes_vars "$root"
        dapk.notes.render "$(_dapk.cmd.tpl_path)" "$_WORK/notes.md" && cat "$_WORK/notes.md" || { dapk.ui.err "$DAPK_NOTES_ERROR"; rm -rf "$_WORK"; return 1; }
    else rm -rf "$_WORK"; return 1; fi
    rm -rf "$_WORK"; _WORK=""
}
