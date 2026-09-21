#!/usr/bin/env bash
# config.sh - loads and validates a project's dabt.pkg (TOML), falling back to .dabt.metadata for name/entry/title/description/author.
#
# dapk.config.load DIR [FILE]   fills DAPK_CFG (assoc) and sets DAPK_ROOT; rc 1 with DAPK_CONFIG_ERROR set on an invalid file.
# dapk.config.get KEY [DEFAULT] value of a key      dapk.config.list KEY ARRAY : array-valued key into ARRAY
# dapk.config.add_include TYPE SOURCE TARGET RECURSIVE      append an include entry (used by the CLI -f/-d flags, not written to disk)
# dapk.config.table_append FILE TABLE KEY=VALUE...          append a [[TABLE]] to dabt.pkg (strings are quoted)
# dapk.config.table_remove FILE TABLE N                     remove the Nth [[TABLE]]
# Keys: name entry requires_dabt homepage title description author changelog suffix release_template sign_key publish_repo
#       release_title release_logo release_header_base (release-note images, see docs/guide/packaging.md)
#       include_paths exclude ; tables include.N.* (type source target recursive exclude optional overwrite follow_symlinks)
#       dependency.N.* (name check version_cmd min_version optional apt pacman dnf zypper apk brew install)

declare -gA DAPK_CFG=()
declare -g DAPK_ROOT="" DAPK_CONFIG_ERROR="" DAPK_CONFIG_FILE=""
_DAPK_CFG_TOP=" name entry requires_dabt homepage title description author changelog suffix release_template sign_key publish_repo build_offset release_title release_logo release_header_base include_paths exclude "
_DAPK_CFG_INC=" type source target recursive exclude optional overwrite follow_symlinks "
_DAPK_CFG_DEP=" name check version_cmd min_version optional apt pacman dnf zypper apk brew install "

dapk.config.get() { printf '%s' "${DAPK_CFG[$1]:-${2:-}}"; }
dapk.config.list() { dapk.toml.split "${DAPK_CFG[$1]:-}" "$2"; }

_dapk.config.bool() { case "${1,,}" in true|yes|1) return 0 ;; esac; return 1; }

dapk.config.load() {
    local dir="$1" file="${2:-}" k v line base n i f raw
    DAPK_CFG=(); DAPK_CONFIG_ERROR=""; DAPK_CONFIG_UNKNOWN=()
    DAPK_ROOT="$(cd -P "$dir" 2>/dev/null && pwd -P)" || { DAPK_CONFIG_ERROR="not a folder: $dir"; return 1; }
    [[ -n "$file" ]] || file="$DAPK_ROOT/dabt.pkg"
    DAPK_CONFIG_FILE="$file"
    if [[ -f "$file" ]]; then
        dapk.toml.parse "$file" DAPK_CFG || { DAPK_CONFIG_ERROR="$DAPK_TOML_ERROR"; return 1; }
    elif [[ "${2:-}" != "" ]]; then DAPK_CONFIG_ERROR="cannot read $file"; return 1
    else DAPK_CONFIG_FILE=""; fi

    # unknown / malformed keys
    for k in "${!DAPK_CFG[@]}"; do
        case "$k" in
            @count.*) ;;
            include.*|dependency.*)
                n="${k%%.*}"; raw="${k#*.}"
                [[ "$raw" =~ ^[0-9]+\.([a-z_]+)$ ]] || { DAPK_CONFIG_ERROR="[$n] must be written as [[$n]] (an array of tables): $k"; return 1; }
                f="${BASH_REMATCH[1]}"
                if [[ "$n" == include ]]; then [[ "$_DAPK_CFG_INC" == *" $f "* ]] || DAPK_CONFIG_UNKNOWN+=("$k")
                else [[ "$_DAPK_CFG_DEP" == *" $f "* ]] || DAPK_CONFIG_UNKNOWN+=("$k"); fi ;;
            *.*) DAPK_CONFIG_ERROR="unknown table [${k%%.*}]"; return 1 ;;
            *) [[ "$_DAPK_CFG_TOP" == *" $k "* ]] || DAPK_CONFIG_UNKNOWN+=("$k") ;;
        esac
    done

    # .dabt.metadata fallbacks
    if [[ -r "$DAPK_ROOT/.dabt.metadata" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line%$'\r'}"; [[ "$line" =~ ^[[:space:]]*(#|$) || "$line" != *=* ]] && continue
            k="${line%%=*}"; v="${line#*=}"; k="${k//[[:space:]]/}"; k="${k,,}"
            v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
            case "$k" in name|entry|title|description|author) [[ -n "${DAPK_CFG[$k]:-}" ]] || DAPK_CFG[$k]="$v" ;;
                min_dabt) [[ -n "${DAPK_CFG[requires_dabt]:-}" ]] || DAPK_CFG[requires_dabt]=">=$v" ;; esac
        done < "$DAPK_ROOT/.dabt.metadata"
    fi
    if [[ -z "${DAPK_CFG[name]:-}" ]]; then base="${DAPK_ROOT##*/}"; base="${base,,}"; DAPK_CFG[name]="${base//[^a-z0-9._-]/-}"; fi
    [[ "${DAPK_CFG[name]}" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || { DAPK_CONFIG_ERROR="invalid name '${DAPK_CFG[name]}' (a-z 0-9 . _ -)"; return 1; }
    [[ "${DAPK_CFG[build_offset]:-0}" =~ ^[0-9]+$ ]] || { DAPK_CONFIG_ERROR="build_offset must be a non-negative integer"; return 1; }
    [[ -n "${DAPK_CFG[changelog]:-}" ]] || { [[ -f "$DAPK_ROOT/CHANGELOG.md" ]] && DAPK_CFG[changelog]="CHANGELOG.md"; }
    if [[ -z "${DAPK_CFG[release_template]:-}" ]]; then
        if [[ -f "$DAPK_ROOT/.dabt/release.tpl" ]]; then DAPK_CFG[release_template]=".dabt/release.tpl"
        else DAPK_CFG[release_template]="${TUI_ROOT:-}/share/release/default.tpl"; fi
    fi
    DAPK_CFG[sign_key]="${DAPK_CFG[sign_key]/#\~/$HOME}"

    # tables
    for n in include dependency; do
        for (( i = 1; i <= ${DAPK_CFG[@count.$n]:-0}; i++ )); do
            if [[ "$n" == include ]]; then
                local t="${DAPK_CFG[include.$i.type]:-}"
                case "$t" in f|file) t=file ;; d|directory) t=directory ;; *) DAPK_CONFIG_ERROR="[[include]] #$i: type must be file or directory"; return 1 ;; esac
                DAPK_CFG[include.$i.type]="$t"
                [[ -n "${DAPK_CFG[include.$i.source]:-}" && -n "${DAPK_CFG[include.$i.target]:-}" ]] \
                    || { DAPK_CONFIG_ERROR="[[include]] #$i: source and target are required"; return 1; }
                if [[ "$t" == file && "${DAPK_CFG[include.$i.recursive]:-}" == true ]]; then DAPK_CONFIG_ERROR="[[include]] #$i: recursive only applies to directories"; return 1; fi
            else
                [[ -n "${DAPK_CFG[dependency.$i.name]:-}" ]] || { DAPK_CONFIG_ERROR="[[dependency]] #$i: name is required"; return 1; }
            fi
        done
    done
    return 0
}
declare -ga DAPK_CONFIG_UNKNOWN=()

dapk.config.add_include() {
    local n=$(( ${DAPK_CFG[@count.include]:-0} + 1 ))
    DAPK_CFG[@count.include]=$n
    DAPK_CFG[include.$n.type]="$1" DAPK_CFG[include.$n.source]="$2" DAPK_CFG[include.$n.target]="$3"
    [[ "${4:-}" == 1 ]] && DAPK_CFG[include.$n.recursive]=true
    return 0
}

_dapk.config.quote() {
    case "$1" in true|false|[0-9]*) [[ "$1" =~ ^(true|false|[0-9]+)$ ]] && { printf '%s' "$1"; return; } ;; esac
    local s="${1//\\/\\\\}"; s="${s//\"/\\\"}"; printf '"%s"' "$s"
}

dapk.config.table_append() {
    local file="$1" table="$2" kv; shift 2
    { [[ -s "$file" ]] && printf '\n'; printf '[[%s]]\n' "$table"
      for kv in "$@"; do printf '%s = %s\n' "${kv%%=*}" "$(_dapk.config.quote "${kv#*=}")"; done; } >> "$file"
}

dapk.config.table_remove() {
    local file="$1" table="$2" n="$3" tmp="$1.tmp.$$"
    awk -v t="[[$table]]" -v n="$n" '
        /^\[/ { skip = 0; if ($0 == t) { if (++c == n) skip = 1 } }
        !skip { print }' "$file" > "$tmp" && mv -f "$tmp" "$file"
}
