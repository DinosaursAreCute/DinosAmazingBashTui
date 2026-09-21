#!/usr/bin/env bash
# collect.sh - builds the package tree: the base tree (include_paths / everything except dotfiles) plus every [[include]] entry.
#
# dapk.collect.run STAGE   copy into STAGE (created). Uses DAPK_CFG + DAPK_ROOT. Sets DAPK_COLLECT_PLAN[] ("source -> target (N files)"),
#                          DAPK_COLLECT_COUNT (files). rc 1 with DAPK_COLLECT_ERROR set. DAPK_COLLECT_DRY=1: validate + plan only.
# Options (set before): DAPK_COLLECT_ALLOW_EXTERNAL=1 lets include sources point outside the project root.
#
# Rules: sources stay inside the project root; targets are relative with no ".."; symlinks are an error unless follow_symlinks = true;
# a target produced twice is an error unless overwrite = true; a missing source is an error unless optional = true; an include that
# matches no files still creates its target directory (mkdir -p) and warns. File modes are normalised (644, or 755 with any exec bit).

declare -ga DAPK_COLLECT_PLAN=()
declare -g DAPK_COLLECT_COUNT=0 DAPK_COLLECT_ERROR="" DAPK_COLLECT_DRY=0 DAPK_COLLECT_ALLOW_EXTERNAL=0
declare -gA _DAPK_COLLECT_SEEN=()
declare -g _DC_STAGE="" _DC_N=0 _DC_OVERWRITE=0 _DC_FOLLOW=0

_dapk.collect.err() { DAPK_COLLECT_ERROR="$*"; return 1; }

# REL PATTERN... : does REL (or one of its path components) match an exclude glob?
_dapk.collect.excluded() {
    local rel="$1" p c; shift
    local -a comps; IFS=/ read -r -a comps <<< "$rel"
    for p in "$@"; do
        [[ -n "$p" ]] || continue
        # shellcheck disable=SC2053
        [[ "$rel" == $p ]] && return 0
        # shellcheck disable=SC2053
        for c in "${comps[@]}"; do [[ "$c" == $p ]] && return 0; done
    done
    return 1
}

# TARGET : validate a package-relative target; prints the normalised path (no leading ./, no trailing /)
_dapk.collect.target() {
    local t="$1"
    [[ -n "$t" && "$t" != /* ]] || return 1
    [[ "/$t/" != *"/../"* ]] || return 1
    t="${t#./}"; while [[ "$t" == *// ]]; do t="${t%/}"; done; t="${t%/}"
    [[ "$t" == . ]] && t=""
    printf '%s' "$t"
}

# SOURCE -> _DC_SRC (absolute, checked)
_dapk.collect.source() {
    local s="$1" full dir
    if [[ "$s" == /* || "/$s/" == *"/../"* ]]; then
        (( DAPK_COLLECT_ALLOW_EXTERNAL )) || return 1
    fi
    [[ "$s" == /* ]] && full="$s" || full="$DAPK_ROOT/$s"
    if [[ -d "$full" ]]; then _DC_SRC="$(cd -P "$full" 2>/dev/null && pwd -P)"
    else dir="$(cd -P "${full%/*}" 2>/dev/null && pwd -P)" || { _DC_SRC=""; return 0; }; _DC_SRC="$dir/${full##*/}"; fi
    [[ -n "$_DC_SRC" ]] || return 0
    if (( ! DAPK_COLLECT_ALLOW_EXTERNAL )) && [[ "$_DC_SRC" != "$DAPK_ROOT" && "$_DC_SRC" != "$DAPK_ROOT/"* ]]; then return 1; fi
    return 0
}

# SRC_FILE DST_REL : place one file
_dapk.collect.put() {
    local src="$1" dst="$2"
    [[ "$dst" != *$'\n'* && "$dst" != *\\* ]] || { _dapk.collect.err "unsupported character in file name: $dst"; return 1; }
    if [[ -n "${_DAPK_COLLECT_SEEN[$dst]:-}" ]] && (( ! _DC_OVERWRITE )); then
        _dapk.collect.err "target '$dst' is produced twice (${_DAPK_COLLECT_SEEN[$dst]} and $src); use overwrite = true"; return 1
    fi
    _DAPK_COLLECT_SEEN[$dst]="$src"; (( _DC_N++, DAPK_COLLECT_COUNT++ ))
    (( DAPK_COLLECT_DRY )) && return 0
    if [[ "$dst" == */* ]]; then mkdir -p "$_DC_STAGE/${dst%/*}" || { _dapk.collect.err "cannot create ${dst%/*}"; return 1; }; fi
    [[ -d "$_DC_STAGE/$dst" ]] && { _dapk.collect.err "target '$dst' is a directory"; return 1; }
    local cp=(cp); (( _DC_FOLLOW )) && cp+=(-L)
    "${cp[@]}" -- "$src" "$_DC_STAGE/$dst" || { _dapk.collect.err "cannot copy $src"; return 1; }
    if [[ -x "$src" ]]; then chmod 755 "$_DC_STAGE/$dst"; else chmod 644 "$_DC_STAGE/$dst"; fi
}

# SRCDIR DSTREL RECURSIVE EXCLUDE... : copy the files of a directory (empty directories are created too when recursive)
_dapk.collect.tree() {
    local src="$1" dst="$2" rec="$3" p rel maxd=() findc=(find); shift 3
    local -a ex=("$@")
    (( _DC_FOLLOW )) && findc+=(-L)
    [[ "$rec" == 1 ]] || maxd=(-maxdepth 1)
    while IFS= read -r -d '' p; do
        rel="${p#"$src"/}"
        _dapk.collect.excluded "$rel" "${ex[@]}" && continue
        if [[ -L "$p" && $_DC_FOLLOW == 0 ]]; then _dapk.collect.err "symlink not allowed: $p (set follow_symlinks = true to dereference)"; return 1; fi
        if [[ -d "$p" ]]; then
            [[ "$rec" == 1 && $DAPK_COLLECT_DRY == 0 ]] && mkdir -p "$_DC_STAGE/${dst:+$dst/}$rel"
        elif [[ -f "$p" ]]; then
            _dapk.collect.put "$p" "${dst:+$dst/}$rel" || return 1
        else _dapk.collect.err "unsupported file type: $p"; return 1; fi
    done < <("${findc[@]}" "$src" -mindepth 1 "${maxd[@]}" -print0 2>/dev/null | LC_ALL=C sort -z)
    return 0
}

_dapk.collect.base() {
    local -a paths ex; local p e rel
    dapk.config.list include_paths paths; dapk.config.list exclude ex
    ex+=(dist .git dabt.pkg)
    if (( ! ${#paths[@]} )); then
        while IFS= read -r -d '' p; do
            e="${p##*/}"
            [[ "$e" == .* && "$e" != .dabt.metadata ]] && continue
            _dapk.collect.excluded "$e" "${ex[@]}" && continue
            paths+=("$e")
        done < <(find "$DAPK_ROOT" -mindepth 1 -maxdepth 1 -print0 | LC_ALL=C sort -z)
    else [[ " ${paths[*]} " == *" .dabt.metadata "* || ! -f "$DAPK_ROOT/.dabt.metadata" ]] || paths+=(.dabt.metadata); fi
    for p in "${paths[@]}"; do
        if ! _dapk.collect.source "$p" || [[ -z "$_DC_SRC" ]]; then _dapk.collect.err "include_paths: '$p' is outside the project or missing"; return 1; fi
        [[ -e "$_DC_SRC" ]] || { _dapk.collect.err "include_paths: '$p' does not exist"; return 1; }
        rel="${p#./}"; rel="${rel%/}"
        _DC_N=0; _DC_OVERWRITE=0; _DC_FOLLOW=0
        if [[ -L "$_DC_SRC" ]]; then _dapk.collect.err "symlink not allowed: $p"; return 1; fi
        if [[ -d "$_DC_SRC" ]]; then _dapk.collect.tree "$_DC_SRC" "$rel" 1 "${ex[@]}" || return 1
        else _dapk.collect.put "$_DC_SRC" "$rel" || return 1; fi
        DAPK_COLLECT_PLAN+=("$rel -> $rel ($_DC_N files)")
    done
}

_dapk.collect.includes() {
    local i n=${DAPK_CFG[@count.include]:-0} type src target rec opt ow follow t tgt base
    local -a ex
    for (( i = 1; i <= n; i++ )); do
        type="${DAPK_CFG[include.$i.type]}" src="${DAPK_CFG[include.$i.source]}" target="${DAPK_CFG[include.$i.target]}"
        rec=0 opt=0 ow=0 follow=0
        _dapk.config.bool "${DAPK_CFG[include.$i.recursive]:-}" && rec=1
        _dapk.config.bool "${DAPK_CFG[include.$i.optional]:-}" && opt=1
        _dapk.config.bool "${DAPK_CFG[include.$i.overwrite]:-}" && ow=1
        _dapk.config.bool "${DAPK_CFG[include.$i.follow_symlinks]:-}" && follow=1
        dapk.toml.split "${DAPK_CFG[include.$i.exclude]:-}" ex
        _DC_OVERWRITE=$ow _DC_FOLLOW=$follow _DC_N=0
        if ! _dapk.collect.source "$src"; then _dapk.collect.err "include #$i: source '$src' is outside the project (--allow-external permits it)"; return 1; fi
        if [[ -z "$_DC_SRC" || ! -e "$_DC_SRC" ]]; then
            (( opt )) && { dapk.ui.debug "include #$i: optional source '$src' not found, skipped"; continue; }
            _dapk.collect.err "include #$i: source '$src' does not exist"; return 1
        fi
        if [[ -L "$_DC_SRC" && $follow == 0 ]]; then _dapk.collect.err "include #$i: '$src' is a symlink (set follow_symlinks = true)"; return 1; fi
        tgt="$(_dapk.collect.target "$target")" || { _dapk.collect.err "include #$i: target '$target' must be relative and contain no '..'"; return 1; }
        if [[ "$type" == file ]]; then
            [[ -f "$_DC_SRC" ]] || { _dapk.collect.err "include #$i: '$src' is not a file"; return 1; }
            [[ "$target" == */ || -z "$tgt" ]] && tgt="${tgt:+$tgt/}${_DC_SRC##*/}"
            _dapk.collect.put "$_DC_SRC" "$tgt" || return 1
        else
            [[ -d "$_DC_SRC" ]] || { _dapk.collect.err "include #$i: '$src' is not a directory"; return 1; }
            _dapk.collect.tree "$_DC_SRC" "$tgt" "$rec" "${ex[@]}" || return 1
            if (( _DC_N == 0 )); then
                (( DAPK_COLLECT_DRY )) || mkdir -p "$_DC_STAGE/$tgt"
                dapk.ui.warn "include '$src' matched no files (created empty target '${tgt:-.}')"
            fi
        fi
        DAPK_COLLECT_PLAN+=("$src -> ${tgt:-.} ($_DC_N files)")
    done
    return 0
}

dapk.collect.run() {
    _DC_STAGE="$1"; DAPK_COLLECT_PLAN=(); DAPK_COLLECT_COUNT=0; DAPK_COLLECT_ERROR=""; _DAPK_COLLECT_SEEN=()
    (( DAPK_COLLECT_DRY )) || mkdir -p "$_DC_STAGE" || { _dapk.collect.err "cannot create $_DC_STAGE"; return 1; }
    _dapk.collect.base || return 1
    _dapk.collect.includes || return 1
    (( DAPK_COLLECT_DRY )) || find "$_DC_STAGE" -type d -exec chmod 755 {} +
    return 0
}
