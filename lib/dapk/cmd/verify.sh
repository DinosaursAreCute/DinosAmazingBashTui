#!/usr/bin/env bash
# cmd/verify.sh - `dabt pkg verify`, `dabt pkg info`, `dabt pkg news`

dapk.cmd.verify() {
    local pkg="" rc
    while (( $# )); do
        if _dapk.cmd.ui "$1" "${2:-}"; then shift "$_UI_SHIFT"; continue; fi
        case "$1" in
            --trust-key) DAPK_VERIFY_TRUST_KEY="${2:-}"; shift 2 ;;
            --allow-unsigned) DAPK_VERIFY_ALLOW_UNSIGNED=1; shift ;;
            -h|--help) _dapk.cmd.help; return 0 ;;
            -*) _dapk.cmd.usage "verify: unknown option $1"; return 2 ;;
            *) pkg="$1"; shift ;;
        esac
    done
    [[ -n "$pkg" ]] || { _dapk.cmd.usage "verify: give a .$DABT_PKG_EXT file"; return 2; }
    dapk.ui.init; dapk.ui.steps 1
    dapk.ui.step "Verifying ${pkg##*/}"
    dapk.verify.run "$pkg"; rc=$?
    (( rc == 0 )) && { dapk.ui.ok "verified: ${DAPK_MANIFEST_H[name]} ${DAPK_MANIFEST_H[version]}+${DAPK_MANIFEST_H[build]:-0}"; }
    _dapk.cmd.finish "$rc"
}

dapk.cmd.info() {
    local pkg="" k i first=1
    while (( $# )); do
        case "$1" in -h|--help) _dapk.cmd.help; return 0 ;; -*) _dapk.cmd.usage "info: unknown option $1"; return 2 ;; *) pkg="$1"; shift ;; esac
    done
    [[ -n "$pkg" ]] || { _dapk.cmd.usage "info: give a .$DABT_PKG_EXT file"; return 2; }
    dapk.pack.check "$pkg" || { printf 'dabt: %s\n' "$DAPK_PACK_ERROR" >&2; return 1; }
    local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/dapk_info.XXXXXX")" || return 1
    dapk.pack.manifest "$pkg" > "$tmp"; dapk.manifest.read "$tmp" || { rm -f "$tmp"; printf 'dabt: %s\n' "$DAPK_MANIFEST_ERROR" >&2; return 1; }
    rm -f "$tmp"
    for k in name version build commit built entry requires_dabt homepage news_url signer; do
        [[ -n "${DAPK_MANIFEST_H[$k]:-}" ]] && printf '%-14s %s\n' "$k" "${DAPK_MANIFEST_H[$k]}"
    done
    dapk.deps.load_manifest
    for (( i = 1; i <= DAPK_DEPS_N; i++ )); do
        (( first )) && { printf '%-14s\n' dependencies; first=0; }
        printf '  %-12s %s%s\n' "${_DD[$i.name]}" "check: ${_DD[$i.check]:-command -v ${_DD[$i.name]}}" "$(_dapk.deps.optional "$i" && echo '  (optional)')"
    done
    printf '%-14s %s\n' entries "${#DAPK_MANIFEST_ENTRIES[@]} top-level ($DAPK_PACK_COUNT members)"
    printf '%-14s %s\n' note "not verified: run  dabt pkg verify ${pkg##*/}"
    local news; news="$(dapk.pack.file_in "$pkg" NEWS)"
    if [[ -n "$news" ]]; then
        printf '\nNews\n'; local v t last=""
        while IFS=$'\t' read -r v t; do [[ -n "$v" ]] || continue; [[ "$v" != "$last" ]] && { printf '  %s\n' "$v"; last="$v"; }; printf '    - %s\n' "$t"; done <<< "$news"
    fi
}

dapk.cmd.news() {
    local src="" since="" tmp
    while (( $# )); do
        case "$1" in
            --since) since="${2:-}"; shift 2 ;;
            -h|--help) _dapk.cmd.help; return 0 ;;
            -*) _dapk.cmd.usage "news: unknown option $1"; return 2 ;;
            *) src="$1"; shift ;;
        esac
    done
    [[ -n "$src" ]] || { _dapk.cmd.usage "news: give a .$DABT_PKG_EXT, a -news.txt (file or URL) or a CHANGELOG.md"; return 2; }
    tmp="$(mktemp "${TMPDIR:-/tmp}/dapk_news.XXXXXX")" || return 1
    case "$src" in
        *."$DABT_PKG_EXT") dapk.pack.check "$src" || { rm -f "$tmp"; printf 'dabt: %s\n' "$DAPK_PACK_ERROR" >&2; return 1; }; dapk.pack.file_in "$src" NEWS > "$tmp" ;;
        *.md) [[ -r "$src" ]] || { rm -f "$tmp"; printf 'dabt: cannot read %s\n' "$src" >&2; return 1; }; dapk.changelog.news "$src" "unreleased" > "$tmp" ;;
        *) if [[ "$src" == http://* || "$src" == https://* ]]; then curl -fsSL --max-time 20 "$src" > "$tmp" 2>/dev/null || { rm -f "$tmp"; printf 'dabt: could not fetch %s\n' "$src" >&2; return 1; }
           else cp -- "$src" "$tmp" 2>/dev/null || { rm -f "$tmp"; printf 'dabt: cannot read %s\n' "$src" >&2; return 1; }; fi ;;
    esac
    dapk.news.load "$tmp"; rm -f "$tmp"
    [[ -n "$since" ]] && dapk.news.since "$since"
    if (( ${#DAPK_NEWS_ITEMS[@]} )); then dapk.news.print; else printf 'no news\n' >&2; fi
    return 0
}
