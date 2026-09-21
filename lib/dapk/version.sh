#!/usr/bin/env bash
# version.sh - version and build-number resolution, semver comparison and bumping. No dependencies on other modules.
#
# dapk.version.valid V                 rc 0 when V is semver (MAJOR.MINOR.PATCH[-pre][+meta])
# dapk.version.cmp A B                 sets DAPK_VCMP to -1 | 0 | 1 (semver precedence; +meta ignored)
# dapk.version.bump KIND VERSION VAR   KIND = major|minor|patch : the bumped core version (pre-release dropped) into VAR
# dapk.version.resolve DIR [SUFFIX] [OFFSET]   sets DAPK_VERSION (no build), DAPK_BUILD, DAPK_FULL (version-build), DAPK_TAG (v<version>),
#                                      DAPK_VERSION_SOURCE, DAPK_BUILD_SOURCE (which counter), DAPK_BUILD_NOTE (a warning worth showing)
#   version: CI tag (v1.2.3) > DIR/VERSION > version= in DIR/.dabt.metadata > 0.0.0.   SUFFIX (dev|prerelease|rc.N) becomes -SUFFIX.
#   build:   DABT_BUILD_NUMBER (used as given) > the CI system's own run counter (GITHUB_RUN_NUMBER, CI_PIPELINE_IID, BUILDKITE_BUILD_NUMBER,
#            CIRCLE_BUILD_NUM, BUILD_NUMBER (Jenkins), BUILD_BUILDID (Azure)) > git commit count > 0. OFFSET (build_offset in dabt.pkg) is added
#            to the last two, so numbering can continue after moving CI systems. CI counters only ever grow and stay the same on a re-run.
# dapk.version.write DIR VERSION       writes VERSION (and version= in .dabt.metadata when present)

declare -g DAPK_BUILD_SOURCE="" DAPK_BUILD_NOTE="" DAPK_VERSION=""  DAPK_BUILD="" DAPK_FULL="" DAPK_TAG="" DAPK_VERSION_SOURCE="" DAPK_VCMP=0 DAPK_VERSION_ERROR=""
_DAPK_SEMVER='^([0-9]+)\.([0-9]+)\.([0-9]+)(-([0-9A-Za-z.-]+))?(\+([0-9A-Za-z.-]+))?$'

dapk.version.valid() { [[ "$1" =~ $_DAPK_SEMVER ]]; }

dapk.version.cmp() {
    local a="${1#v}" b="${2#v}" i x y
    a="${a%%+*}"; b="${b%%+*}"
    local ca="${a%%-*}" cb="${b%%-*}" pa="" pb=""
    [[ "$a" == *-* ]] && pa="${a#*-}"; [[ "$b" == *-* ]] && pb="${b#*-}"
    local -a na nb ia ib
    IFS=. read -r -a na <<< "$ca"; IFS=. read -r -a nb <<< "$cb"
    for i in 0 1 2; do
        x=$(( 10#${na[i]:-0} )); y=$(( 10#${nb[i]:-0} ))
        (( x < y )) && { DAPK_VCMP=-1; return 0; }; (( x > y )) && { DAPK_VCMP=1; return 0; }
    done
    if [[ -z "$pa" && -z "$pb" ]]; then DAPK_VCMP=0; return 0; fi
    [[ -z "$pa" ]] && { DAPK_VCMP=1; return 0; }      # a release outranks its pre-releases
    [[ -z "$pb" ]] && { DAPK_VCMP=-1; return 0; }
    IFS=. read -r -a ia <<< "$pa"; IFS=. read -r -a ib <<< "$pb"
    local n=${#ia[@]}; (( ${#ib[@]} > n )) && n=${#ib[@]}
    for (( i = 0; i < n; i++ )); do
        x="${ia[i]:-}"; y="${ib[i]:-}"
        [[ -z "$x" ]] && { DAPK_VCMP=-1; return 0; }; [[ -z "$y" ]] && { DAPK_VCMP=1; return 0; }
        if [[ "$x" =~ ^[0-9]+$ && "$y" =~ ^[0-9]+$ ]]; then
            (( 10#$x < 10#$y )) && { DAPK_VCMP=-1; return 0; }; (( 10#$x > 10#$y )) && { DAPK_VCMP=1; return 0; }
        elif [[ "$x" =~ ^[0-9]+$ ]]; then DAPK_VCMP=-1; return 0
        elif [[ "$y" =~ ^[0-9]+$ ]]; then DAPK_VCMP=1; return 0
        elif [[ "$x" < "$y" ]]; then DAPK_VCMP=-1; return 0
        elif [[ "$x" > "$y" ]]; then DAPK_VCMP=1; return 0; fi
    done
    DAPK_VCMP=0
}

dapk.version.bump() {
    local kind="$1" v="${2#v}" var="$3" M m p
    [[ "$v" =~ $_DAPK_SEMVER ]] || return 1
    M="${BASH_REMATCH[1]}" m="${BASH_REMATCH[2]}" p="${BASH_REMATCH[3]}"
    case "$kind" in
        major) M=$((M + 1)) m=0 p=0 ;; minor) m=$((m + 1)) p=0 ;; patch) p=$((p + 1)) ;;
        *) return 2 ;;
    esac
    printf -v "$var" '%s.%s.%s' "$M" "$m" "$p"
}

# normalize "1" / "1.2" to 1.0.0 / 1.2.0 (the app metadata format allows short versions)
_dapk.version.pad() {
    local v="${1#v}" core rest=""
    core="${v%%[-+]*}"; [[ "$v" != "$core" ]] && rest="${v#"$core"}"
    case "$core" in *.*.*) ;; *.*) core="$core.0" ;; *) core="$core.0.0" ;; esac
    printf '%s%s' "$core" "$rest"
}

dapk.version.resolve() {
    local dir="${1:-.}" suffix="${2:-}" off="${3:-0}" v="" src="" line n="" nsrc="" var
    DAPK_VERSION_ERROR="" DAPK_BUILD_NOTE="" DAPK_BUILD_SOURCE=""
    [[ "$off" =~ ^[0-9]+$ ]] || { DAPK_VERSION_ERROR="build_offset must be a non-negative integer (got '$off')"; return 1; }
    if [[ "${GITHUB_REF_TYPE:-}" == tag && "${GITHUB_REF_NAME:-}" == v[0-9]* ]]; then v="${GITHUB_REF_NAME#v}"; src="tag ${GITHUB_REF_NAME}"
    elif [[ "${CI_COMMIT_TAG:-}" == v[0-9]* ]]; then v="${CI_COMMIT_TAG#v}"; src="tag $CI_COMMIT_TAG"; fi
    if [[ -z "$v" && -r "$dir/VERSION" ]]; then read -r v < "$dir/VERSION"; v="${v//[[:space:]]/}"; src="VERSION"; fi
    if [[ -z "$v" && -r "$dir/.dabt.metadata" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ "$line" =~ ^[[:space:]]*version[[:space:]]*=[[:space:]]*(.*)$ ]] && { v="${BASH_REMATCH[1]//[[:space:]\"\']/}"; break; }
        done < "$dir/.dabt.metadata"
        [[ -n "$v" ]] && src=".dabt.metadata"
    fi
    [[ -n "$v" ]] || { v="0.0.0"; src="default"; }
    v="$(_dapk.version.pad "$v")"; v="${v%%+*}"
    dapk.version.valid "$v" || { DAPK_VERSION_ERROR="'$v' (from $src) is not a semantic version"; return 1; }
    if [[ -n "$suffix" ]]; then
        [[ "$suffix" =~ ^[0-9A-Za-z.-]+$ ]] || { DAPK_VERSION_ERROR="invalid suffix '$suffix'"; return 1; }
        v="${v%%-*}-$suffix"
    fi
    n=""
    if [[ "${DABT_BUILD_NUMBER:-}" =~ ^[0-9]+$ ]]; then n="$DABT_BUILD_NUMBER" nsrc="DABT_BUILD_NUMBER"
    else
        for var in GITHUB_RUN_NUMBER CI_PIPELINE_IID BUILDKITE_BUILD_NUMBER CIRCLE_BUILD_NUM BUILD_NUMBER BUILD_BUILDID; do
            [[ "${!var:-}" =~ ^[0-9]+$ ]] && { n=$(( 10#${!var} + off )); nsrc="$var"; break; }
        done
        if [[ -z "$n" ]] && command -v git >/dev/null 2>&1 && n="$(git -C "$dir" rev-list --count HEAD 2>/dev/null)" && [[ "$n" =~ ^[0-9]+$ ]]; then
            n=$(( n + off )); nsrc="git commit count"
            [[ "$(git -C "$dir" rev-parse --is-shallow-repository 2>/dev/null)" == true ]] \
                && DAPK_BUILD_NOTE="shallow git clone: the commit count is too low to be a reliable build number (fetch full history, e.g. actions/checkout fetch-depth: 0)"
        else [[ -n "$n" ]] || { n=""; }; fi
        [[ -n "$n" ]] || { n=0; nsrc="none (0)"; }
    fi
    DAPK_VERSION="$v" DAPK_BUILD="${n:-0}" DAPK_FULL="$v-${n:-0}" DAPK_TAG="v$v" DAPK_VERSION_SOURCE="$src" DAPK_BUILD_SOURCE="$nsrc"
}

dapk.version.write() {
    local dir="$1" v="$2" f="$1/.dabt.metadata" tmp line done_=0
    printf '%s\n' "$v" > "$dir/VERSION" || return 1
    if [[ -f "$f" ]]; then
        tmp="$f.tmp.$$"
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" =~ ^([[:space:]]*version[[:space:]]*=[[:space:]]*).* ]]; then line="${BASH_REMATCH[1]}${v%%+*}"; done_=1; fi
            printf '%s\n' "$line"
        done < "$f" > "$tmp" && mv -f "$tmp" "$f"
    fi
    return 0
}
