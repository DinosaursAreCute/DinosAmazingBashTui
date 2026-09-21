#!/usr/bin/env bash
# manifest.sh - the package MANIFEST: header (descriptor + dependencies) and the checksums of every top-level entry.
#
# Entry lines:  <type> <sha256> <size> <mode> <path>     type f|d; directories have "-" size and mode.
# A file hash is the sha256 of its content. A directory hash (Merkle) is the sha256 of one line per direct child, in LC_ALL=C name
# order:  "<type> <hash> <mode> <name>\n"  (child directories contribute their own hash and mode "-"). Any change at any depth
# therefore changes the hash of its top-level ancestor. MANIFEST and MANIFEST.sig are excluded (they cannot describe themselves).
#
# dapk.manifest.sha256 FILE|-          hex sha256 of a file (or stdin)
# dapk.manifest.scan TREE              hash TREE (progress via dapk.ui.progress_* when DAPK_MANIFEST_PROGRESS=1) -> DAPK_MANIFEST_ENTRIES[]
# dapk.manifest.header_set KEY VALUE   add a header line (order kept)          dapk.manifest.write OUT   write header + DAPK_MANIFEST_ENTRIES
# dapk.manifest.read FILE              parse -> DAPK_MANIFEST_H (assoc) + DAPK_MANIFEST_ENTRIES[]; rc 1 + DAPK_MANIFEST_ERROR when malformed
# dapk.manifest.compare                compare DAPK_MANIFEST_ENTRIES (read) with the recomputed DAPK_MANIFEST_COMPUTED[]; problems -> DAPK_MANIFEST_PROBLEMS[]

declare -ga DAPK_MANIFEST_ENTRIES=() DAPK_MANIFEST_COMPUTED=() DAPK_MANIFEST_PROBLEMS=() _DM_HDR=()
declare -gA DAPK_MANIFEST_H=()
declare -g DAPK_MANIFEST_ERROR="" DAPK_MANIFEST_PROGRESS=0
declare -ga _DM_SHA=()
declare -gA _DM_HASH=() _DM_KIDS=() _DM_SEEN=()
declare -g _DH="" _DM_TREE=""

_dapk.manifest.tool() {
    (( ${#_DM_SHA[@]} )) && return 0
    if command -v sha256sum >/dev/null 2>&1; then _DM_SHA=(sha256sum)
    elif command -v shasum >/dev/null 2>&1; then _DM_SHA=(shasum -a 256)
    else DAPK_MANIFEST_ERROR="sha256sum or shasum is required"; return 1; fi
}

dapk.manifest.sha256() {
    _dapk.manifest.tool || return 1
    local h
    if [[ "$1" == - ]]; then h="$("${_DM_SHA[@]}" | cut -d' ' -f1)"; else h="$("${_DM_SHA[@]}" -- "$1" 2>/dev/null | cut -d' ' -f1)"; fi
    [[ -n "$h" ]] || return 1
    printf '%s' "$h"
}

_dapk.manifest.addpath() {   # PATH TYPE : register PATH and all its parent directories as children
    local p="$1" t="$2" parent name key
    while :; do
        parent=""; [[ "$p" == */* ]] && parent="${p%/*}"
        name="${p##*/}"; key="$parent|$name"
        [[ -n "${_DM_SEEN[$key]:-}" ]] && break
        _DM_SEEN[$key]=1; _DM_KIDS["@$parent"]+="$t"$'\t'"$name"$'\n'
        [[ -z "$parent" ]] && break
        p="$parent"; t=d
    done
}

_dapk.manifest.dhash() {   # DIR -> _DH
    local d="$1" kid t n path out="" h m
    while IFS= read -r kid; do
        [[ -n "$kid" ]] || continue
        t="${kid%%$'\t'*}"; n="${kid#*$'\t'}"; path="${d:+$d/}$n"
        if [[ "$t" == d ]]; then _dapk.manifest.dhash "$path"; h="$_DH"; m="-"
        else h="${_DM_HASH[$path]}"; if [[ -x "$_DM_TREE/$path" ]]; then m=755; else m=644; fi; fi
        out+="$t $h $m $n"$'\n'
    done < <(printf '%s' "${_DM_KIDS["@$d"]:-}" | LC_ALL=C sort -t $'\t' -k2,2)
    _DH="$(printf '%s' "$out" | dapk.manifest.sha256 -)"
}

dapk.manifest.scan() {
    local tree="$1" line h p total=0 done_=0 kid t n size m
    DAPK_MANIFEST_ENTRIES=(); DAPK_MANIFEST_ERROR=""; _DM_HASH=(); _DM_KIDS=(); _DM_SEEN=(); _DM_TREE="$tree"
    _dapk.manifest.tool || return 1
    local -a files=()
    while IFS= read -r -d '' p; do
        p="${p#./}"; [[ "$p" == MANIFEST || "$p" == MANIFEST.sig ]] && continue
        [[ "$p" == *$'\n'* || "$p" == *\\* ]] && { DAPK_MANIFEST_ERROR="unsupported character in file name: $p"; return 1; }
        files+=("$p")
    done < <(cd "$tree" && find . -type f -print0 | LC_ALL=C sort -z)
    total=${#files[@]}
    (( DAPK_MANIFEST_PROGRESS )) && dapk.ui.progress_start "Hashing files" "$total"
    if (( total )); then
        while IFS= read -r line; do
            h="${line%% *}"; p="${line#*  }"; p="${p#./}"
            [[ "$line" == \\* ]] && { DAPK_MANIFEST_ERROR="unsupported file name in tree"; return 1; }
            _DM_HASH[$p]="$h"; (( DAPK_MANIFEST_PROGRESS )) && dapk.ui.progress_tick
        done < <(cd "$tree" && printf '%s\0' "${files[@]/#/./}" | xargs -0 "${_DM_SHA[@]}" 2>/dev/null)
        (( ${#_DM_HASH[@]} == total )) || { DAPK_MANIFEST_ERROR="hashing failed (${#_DM_HASH[@]} of $total files)"; return 1; }
    fi
    for p in "${files[@]}"; do _dapk.manifest.addpath "$p" f; done
    while IFS= read -r -d '' p; do p="${p#./}"; [[ "$p" == . || -z "$p" ]] && continue; _dapk.manifest.addpath "$p" d; done < <(cd "$tree" && find . -mindepth 1 -type d -print0)
    while IFS= read -r kid; do
        [[ -n "$kid" ]] || continue
        t="${kid%%$'\t'*}"; n="${kid#*$'\t'}"
        if [[ "$t" == d ]]; then _dapk.manifest.dhash "$n"; DAPK_MANIFEST_ENTRIES+=("d $_DH - - $n")
        else
            size="$(wc -c < "$tree/$n")"; size="${size//[[:space:]]/}"
            if [[ -x "$tree/$n" ]]; then m=755; else m=644; fi
            DAPK_MANIFEST_ENTRIES+=("f ${_DM_HASH[$n]} $size $m $n")
        fi
    done < <(printf '%s' "${_DM_KIDS["@"]:-}" | LC_ALL=C sort -t $'\t' -k2,2)
    (( DAPK_MANIFEST_PROGRESS )) && dapk.ui.progress_done "Hashed $total files"
    return 0
}

dapk.manifest.header_set() { _DM_HDR+=("$1=$2"); }

dapk.manifest.write() {
    { printf '%s\n' "$DAPK_MANIFEST_MAGIC"; printf '%s\n' "${_DM_HDR[@]}"; printf '%s\n' '---'; printf '%s\n' "${DAPK_MANIFEST_ENTRIES[@]}"; } > "$1"
}

dapk.manifest.read() {
    local f="$1" line first=1 inhdr=1 k t h s m p
    DAPK_MANIFEST_H=(); DAPK_MANIFEST_ENTRIES=(); DAPK_MANIFEST_ERROR=""
    [[ -r "$f" ]] || { DAPK_MANIFEST_ERROR="cannot read $f"; return 1; }
    while IFS= read -r line || [[ -n "$line" ]]; do
        if (( first )); then
            first=0; [[ "$line" == "$DAPK_MANIFEST_MAGIC" ]] || { DAPK_MANIFEST_ERROR="not a DABT manifest (missing '$DAPK_MANIFEST_MAGIC')"; return 1; }
            continue
        fi
        if (( inhdr )); then
            [[ "$line" == --- ]] && { inhdr=0; continue; }
            [[ "$line" == *=* ]] || { DAPK_MANIFEST_ERROR="bad header line: $line"; return 1; }
            DAPK_MANIFEST_H[${line%%=*}]="${line#*=}"; continue
        fi
        [[ -n "$line" ]] || continue
        read -r t h s m p <<< "$line"
        [[ ( "$t" == f || "$t" == d ) && "$h" =~ ^[0-9a-f]{64}$ && -n "$p" ]] || { DAPK_MANIFEST_ERROR="bad entry line: $line"; return 1; }
        DAPK_MANIFEST_ENTRIES+=("$line")
    done < "$f"
    (( inhdr )) && { DAPK_MANIFEST_ERROR="manifest has no '---' separator"; return 1; }
    [[ -n "${DAPK_MANIFEST_H[name]:-}" && -n "${DAPK_MANIFEST_H[version]:-}" ]] || { DAPK_MANIFEST_ERROR="manifest lacks name or version"; return 1; }
    return 0
}

# dapk.manifest.compare : DAPK_MANIFEST_ENTRIES (as read) vs a fresh dapk.manifest.scan (moved to DAPK_MANIFEST_COMPUTED by the caller)
dapk.manifest.compare() {
    local e t h s m p; local -A want=() have=()
    DAPK_MANIFEST_PROBLEMS=()
    for e in "${DAPK_MANIFEST_ENTRIES[@]}"; do read -r t h s m p <<< "$e"; want[$p]="$t $h $s $m"; done
    for e in "${DAPK_MANIFEST_COMPUTED[@]}"; do read -r t h s m p <<< "$e"; have[$p]="$t $h $s $m"; done
    for p in "${!want[@]}"; do
        [[ -n "${have[$p]:-}" ]] || { DAPK_MANIFEST_PROBLEMS+=("missing from the package: $p"); continue; }
        [[ "${want[$p]}" == "${have[$p]}" ]] || DAPK_MANIFEST_PROBLEMS+=("checksum mismatch: $p")
    done
    for p in "${!have[@]}"; do [[ -n "${want[$p]:-}" ]] || DAPK_MANIFEST_PROBLEMS+=("not listed in the manifest: $p"); done
    (( ${#DAPK_MANIFEST_PROBLEMS[@]} == 0 ))
}
