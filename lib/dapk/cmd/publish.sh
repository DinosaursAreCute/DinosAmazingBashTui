#!/usr/bin/env bash
# cmd/publish.sh - `dabt pkg publish`, `deps`, `include`, `dep`, `ci`

dapk.cmd.publish() {
    local dir="." mode="" dry=0 root pkg f rc=0 best="" name suffix=""
    while (( $# )); do
        if _dapk.cmd.ui "$1" "${2:-}"; then shift "$_UI_SHIFT"; continue; fi
        case "$1" in
            --draft) mode=draft; shift ;; --prerelease) mode=prerelease; shift ;; --release) mode=release; shift ;;
            --dry-run) dry=1; shift ;; --suffix) suffix="${2:-}"; shift 2 ;;
            -h|--help) _dapk.cmd.help; return 0 ;;
            -*) _dapk.cmd.usage "publish: unknown option $1"; return 2 ;;
            *) dir="$1"; shift ;;
        esac
    done
    root="$(cd -P "$dir" 2>/dev/null && pwd -P)" || { _dapk.cmd.usage "publish: '$dir' is not a folder"; return 2; }
    dapk.ui.init; dapk.ui.steps 2
    dapk.ui.step "Preparing"
    dapk.config.load "$root" || { dapk.ui.err "$DAPK_CONFIG_ERROR"; _dapk.cmd.finish 1; return; }
    dapk.version.resolve "$root" "$suffix" || { dapk.ui.err "$DAPK_VERSION_ERROR"; _dapk.cmd.finish 1; return; }
    name="${DAPK_CFG[name]}"
    for f in "$root/dist/$name-$DAPK_VERSION+"*."$DABT_PKG_EXT"; do
        [[ -f "$f" ]] || continue
        if [[ -z "$best" ]] || [[ "$f" -nt "$best" ]]; then best="$f"; fi
    done
    [[ -n "$best" ]] || { dapk.ui.err "no dist/$name-$DAPK_VERSION+*.$DABT_PKG_EXT: run  dabt build  first"; _dapk.cmd.finish 1; return; }
    pkg="$best"
    DAPK_PUB_ASSETS=("$pkg"); [[ -f "$pkg.sha256" ]] && DAPK_PUB_ASSETS+=("$pkg.sha256"); [[ -f "$root/dist/$name-news.txt" ]] && DAPK_PUB_ASSETS+=("$root/dist/$name-news.txt")
    DAPK_PUB_REPO="$(dapk.notes.repo_slug "$root")" DAPK_PUB_TAG="$DAPK_TAG" DAPK_PUB_NAME="$name $DAPK_VERSION" DAPK_PUB_BODY="$root/dist/RELEASE_NOTES.md"
    DAPK_PUB_COMMIT="$(git -C "$root" rev-parse HEAD 2>/dev/null)" DAPK_PUB_MODE="$mode" DAPK_PUB_DRY=$dry
    DAPK_PUB_PRE=0; [[ "$DAPK_VERSION" == *-* ]] && DAPK_PUB_PRE=1
    dapk.ui.ok "${pkg##*/}"

    dapk.ui.step "Publishing to GitHub"
    dapk.publish.run; rc=$?
    if (( rc == 0 )); then [[ -n "$DAPK_PUB_URL" ]] && { dapk.ui.ok "$DAPK_PUB_URL"; printf '%s\n' "$DAPK_PUB_URL"; }
    else dapk.ui.err "$DAPK_PUB_ERROR"; fi
    _dapk.cmd.finish "$rc"
}

# dabt pkg deps [APP|PKG|DIR] : check (and with flags install) declared dependencies of an installed app, a package or the project
dapk.cmd.deps() {
    local target="" pm="" rc=0 app="" tmp
    DAPK_DEPS_MODE=default DAPK_DEPS_REQUIRE=0 DAPK_DEPS_YES=0 DAPK_DEPS_ALLOW_CUSTOM=0 DAPK_DEPS_PLAN_ONLY=0 DAPK_DEPS_PM=""
    while (( $# )); do
        if _dapk.cmd.ui "$1" "${2:-}"; then shift "$_UI_SHIFT"; continue; fi
        case "$1" in
            --install-dependencies) DAPK_DEPS_MODE=install; shift ;; --no-deps) DAPK_DEPS_MODE=none; shift ;;
            --require-deps) DAPK_DEPS_REQUIRE=1; shift ;; --yes|-y) DAPK_DEPS_YES=1; shift ;; --allow-custom-install) DAPK_DEPS_ALLOW_CUSTOM=1; shift ;;
            --pm) DAPK_DEPS_PM="${2:-}"; shift 2 ;; --plan) DAPK_DEPS_PLAN_ONLY=1; shift ;;
            -h|--help) _dapk.cmd.help; return 0 ;;
            -*) _dapk.cmd.usage "deps: unknown option $1"; return 2 ;;
            *) target="$1"; shift ;;
        esac
    done
    if [[ "$DAPK_DEPS_MODE" == none && ( $DAPK_DEPS_REQUIRE == 1 ) ]]; then _dapk.cmd.usage "--no-deps cannot be combined with --require-deps"; return 2; fi
    dapk.ui.init; dapk.ui.steps 1
    dapk.ui.step "Dependencies"
    [[ -n "$target" ]] || target="."
    if [[ -d "$target" ]]; then
        dapk.config.load "$target" || { dapk.ui.err "$DAPK_CONFIG_ERROR"; _dapk.cmd.finish 1; return; }
        dapk.deps.load_config
    elif [[ "$target" == *."$DABT_PKG_EXT" ]]; then
        DAPK_VERIFY_ASK=0; dapk.verify.run "$target" || { _dapk.cmd.finish 1; return; }
        dapk.deps.load_manifest
    else
        source "$TUI_ROOT/lib/tui_apps.sh"
        _tui_apps.lookup "$target" || { dapk.ui.err "'$target' is not an installed app, a package or a folder"; _dapk.cmd.finish 1; return; }
        app="$A_NAME"
        tmp="$(mktemp "${TMPDIR:-/tmp}/dapk_dm.XXXXXX")" || return 1
        [[ -r "$A_DIR/MANIFEST" ]] && cp -- "$A_DIR/MANIFEST" "$tmp"
        dapk.manifest.read "$tmp" || { rm -f "$tmp"; dapk.ui.err "$app has no package manifest (not installed from a .$DABT_PKG_EXT)"; _dapk.cmd.finish 1; return; }
        rm -f "$tmp"; dapk.deps.load_manifest
    fi
    (( DAPK_DEPS_N )) || { dapk.ui.ok "no dependencies declared"; [[ -n "$app" ]] && dapk.deps.mark "$app" ok; _dapk.cmd.finish 0; return; }
    dapk.deps.flow; rc=$?
    if [[ -n "$app" ]]; then (( DAPK_DEPS_UNMET )) && dapk.deps.mark "$app" unmet || { (( rc == 0 )) && dapk.deps.mark "$app" ok; }; fi
    _dapk.cmd.finish "$rc"
}

dapk.cmd.include() {
    local sub="${1:-list}" dir="." file type="" src="" tgt="" rec=0 n i; shift
    local -a kv=()
    while (( $# )); do
        case "$1" in
            -f|--file) type=file; shift ;; -d|--directory) type=directory; shift ;;
            -s|--source) src="${2:-}"; shift 2 ;; -t|--target) tgt="${2:-}"; shift 2 ;; -r|--recursive) rec=1; shift ;;
            -C|--dir) dir="${2:-}"; shift 2 ;;
            -*) _dapk.cmd.usage "include: unknown option $1"; return 2 ;;
            *) n="$1"; shift ;;
        esac
    done
    file="$dir/dabt.pkg"
    case "$sub" in
        add)
            [[ -n "$type" && -n "$src" && -n "$tgt" ]] || { _dapk.cmd.usage "include add: -f|-d -s SOURCE -t TARGET [-r]"; return 2; }
            kv=("type=$type" "source=$src" "target=$tgt"); (( rec )) && kv+=("recursive=true")
            dapk.config.table_append "$file" include "${kv[@]}" && printf 'added: %s %s -> %s\n' "$type" "$src" "$tgt" ;;
        list)
            dapk.config.load "$dir" || { printf 'dabt: %s\n' "$DAPK_CONFIG_ERROR" >&2; return 1; }
            for (( i = 1; i <= ${DAPK_CFG[@count.include]:-0}; i++ )); do
                printf '%d  %-9s %s -> %s%s\n' "$i" "${DAPK_CFG[include.$i.type]}" "${DAPK_CFG[include.$i.source]}" "${DAPK_CFG[include.$i.target]}" "$([[ ${DAPK_CFG[include.$i.recursive]:-} == true ]] && echo '  (recursive)')"
            done ;;
        rm|remove)
            [[ "${n:-}" =~ ^[0-9]+$ ]] || { _dapk.cmd.usage "include rm N"; return 2; }
            dapk.config.table_remove "$file" include "$n" && printf 'removed include #%s\n' "$n" ;;
        *) _dapk.cmd.usage "include: add | list | rm"; return 2 ;;
    esac
}

dapk.cmd.dep() {
    local sub="${1:-list}" dir="." file name="" n i f; shift
    local -a kv=()
    while (( $# )); do
        case "$1" in
            -n|--name) name="${2:-}"; kv+=("name=$2"); shift 2 ;;
            --check|--version-cmd|--min-version|--install|--apt|--pacman|--dnf|--zypper|--apk|--brew)
                f="${1#--}"; f="${f//-/_}"; kv+=("$f=${2:-}"); shift 2 ;;
            --optional) kv+=("optional=true"); shift ;;
            -C|--dir) dir="${2:-}"; shift 2 ;;
            -*) _dapk.cmd.usage "dep: unknown option $1"; return 2 ;;
            *) n="$1"; shift ;;
        esac
    done
    file="$dir/dabt.pkg"
    case "$sub" in
        add) [[ -n "$name" ]] || { _dapk.cmd.usage "dep add -n NAME [--check CMD] [--apt PKG] [--pacman PKG] ... [--optional]"; return 2; }
             dapk.config.table_append "$file" dependency "${kv[@]}" && printf 'added dependency %s\n' "$name" ;;
        list) dapk.config.load "$dir" || { printf 'dabt: %s\n' "$DAPK_CONFIG_ERROR" >&2; return 1; }
              dapk.deps.load_config
              for (( i = 1; i <= DAPK_DEPS_N; i++ )); do printf '%d  %s%s\n' "$i" "${_DD[$i.name]}" "$(_dapk.deps.optional "$i" && echo '  (optional)')"; done ;;
        rm|remove) [[ "${n:-}" =~ ^[0-9]+$ ]] || { _dapk.cmd.usage "dep rm N"; return 2; }
             dapk.config.table_remove "$file" dependency "$n" && printf 'removed dependency #%s\n' "$n" ;;
        *) _dapk.cmd.usage "dep: add | list | rm"; return 2 ;;
    esac
}

dapk.cmd.ci() {
    local sub="${1:-}" provider="${2:-}" force=0 dir="."; shift 2>/dev/null; shift 2>/dev/null
    while (( $# )); do case "$1" in --force) force=1; shift ;; -C|--dir) dir="${2:-}"; shift 2 ;; *) _dapk.cmd.usage "ci: unknown option $1"; return 2 ;; esac; done
    [[ "$sub" == init && -n "$provider" ]] || { _dapk.cmd.usage "ci init github|gitlab [--force]"; return 2; }
    dapk.ci.init "$provider" "$dir" "$force" || { printf 'dabt: %s\n' "$DAPK_CI_ERROR" >&2; return 1; }
    printf 'wrote %s\n' "$DAPK_CI_PATH"
    printf 'next: add the DABT_SIGN_KEY secret (private Ed25519 key) and publish_repo in dabt.pkg; tag v1.0.0 to release.\n'
}
