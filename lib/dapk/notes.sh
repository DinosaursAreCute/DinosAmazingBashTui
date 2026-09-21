#!/usr/bin/env bash
# notes.sh - release-note templates. Three constructs only:
#     {{var}}                        substitution (name version build date commit news compare_url checksums title summary heading logo header_base)
#     {{section:Name}}               the body of "### Name" in the changelog section of the built version
#     {{#if var}} ... {{/if}}        conditional block (own lines, may nest); var may also be section:Name
# An unknown variable is an error (a typo must not silently produce empty release notes).
#
# DAPK_NOTES (assoc) holds the variables; DAPK_NOTES_CHANGELOG / DAPK_NOTES_VERSION locate the sections.
# dapk.notes.render TEMPLATE OUT       rc 1 + DAPK_NOTES_ERROR on a problem
# dapk.notes.repo_slug DIR             owner/name from publish_repo or the git remote
# dapk.notes.compare_url REPO TAG DIR  https://github.com/REPO/compare/vPREV...TAG (empty when there is no earlier tag)

declare -gA DAPK_NOTES=()
declare -g DAPK_NOTES_CHANGELOG="" DAPK_NOTES_VERSION="" DAPK_NOTES_ERROR=""
_DAPK_NOTES_VARS=" name version build date commit news compare_url checksums title summary heading logo header_base "

_dapk.notes.value() {   # VAR -> _NV ; rc 1 for an unknown variable
    local v="$1"
    if [[ "$v" == section:* ]]; then
        _NV=""; [[ -n "$DAPK_NOTES_CHANGELOG" && -r "$DAPK_NOTES_CHANGELOG" ]] && _NV="$(dapk.changelog.section "$DAPK_NOTES_CHANGELOG" "$DAPK_NOTES_VERSION" "${v#section:}")"
        return 0
    fi
    [[ "$_DAPK_NOTES_VARS" == *" $v "* ]] || return 1
    _NV="${DAPK_NOTES[$v]:-}"
}

dapk.notes.render() {
    local tpl="$1" out="$2" line n=0 t v res rest
    local -a stack=()      # 1 = this block is active
    DAPK_NOTES_ERROR=""
    [[ -r "$tpl" ]] || { DAPK_NOTES_ERROR="release template not readable: $tpl"; return 1; }
    : > "$out"
    while IFS= read -r line || [[ -n "$line" ]]; do
        (( n++ ))
        t="${line#"${line%%[![:space:]]*}"}"; t="${t%"${t##*[![:space:]]}"}"
        if [[ "$t" =~ ^\{\{#if[[:space:]]+([^}[:space:]]+)[[:space:]]*\}\}$ ]]; then
            _dapk.notes.value "${BASH_REMATCH[1]}" || { DAPK_NOTES_ERROR="line $n: unknown variable '${BASH_REMATCH[1]}'"; return 1; }
            [[ -n "${_NV//[[:space:]]/}" ]] && stack+=(1) || stack+=(0); continue
        fi
        if [[ "$t" == "{{/if}}" ]]; then
            (( ${#stack[@]} )) || { DAPK_NOTES_ERROR="line $n: {{/if}} without {{#if}}"; return 1; }
            unset 'stack[${#stack[@]}-1]'; continue
        fi
        [[ " ${stack[*]} " == *" 0 "* ]] && continue
        res=""; rest="$line"
        while [[ "$rest" =~ \{\{([^{}]+)\}\} ]]; do
            v="${BASH_REMATCH[1]}"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
            _dapk.notes.value "$v" || { DAPK_NOTES_ERROR="line $n: unknown variable '$v'"; return 1; }
            res+="${rest%%"${BASH_REMATCH[0]}"*}$_NV"; rest="${rest#*"${BASH_REMATCH[0]}"}"
        done
        printf '%s\n' "$res$rest" >> "$out"
    done < "$tpl"
    (( ${#stack[@]} == 0 )) || { DAPK_NOTES_ERROR="unclosed {{#if}}"; return 1; }
    cat -s "$out" > "$out.tmp" && mv -f "$out.tmp" "$out"
    return 0
}

dapk.notes.repo_slug() {
    local dir="$1" r="${DAPK_CFG[publish_repo]:-}" u
    if [[ -z "$r" ]] && command -v git >/dev/null 2>&1; then
        u="$(git -C "$dir" remote get-url origin 2>/dev/null)"
        [[ "$u" =~ github\.com[:/]([^/]+/[^/]+)$ ]] && { r="${BASH_REMATCH[1]}"; r="${r%.git}"; }
    fi
    printf '%s' "$r"
}

dapk.notes.compare_url() {
    local repo="$1" tag="$2" dir="$3" t best=""
    [[ -n "$repo" ]] && command -v git >/dev/null 2>&1 || return 0
    while IFS= read -r t; do
        [[ "$t" == "$tag" || "$t" != v[0-9]* ]] && continue
        dapk.version.valid "${t#v}" || continue
        dapk.version.cmp "${t#v}" "${tag#v}"; (( DAPK_VCMP < 0 )) || continue
        if [[ -z "$best" ]]; then best="$t"; else dapk.version.cmp "${t#v}" "${best#v}"; (( DAPK_VCMP > 0 )) && best="$t"; fi
    done < <(git -C "$dir" tag --list 'v*' 2>/dev/null)
    [[ -n "$best" ]] && printf 'https://github.com/%s/compare/%s...%s' "$repo" "$best" "$tag"
    return 0
}
