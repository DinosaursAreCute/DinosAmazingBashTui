#!/usr/bin/env bash
# publish.sh - GitHub releases through the REST API with curl (no gh dependency). Idempotent: an existing release for the tag is updated.
#
# dapk.publish.run   inputs (globals): DAPK_PUB_REPO owner/name, DAPK_PUB_TAG, DAPK_PUB_NAME, DAPK_PUB_BODY (file), DAPK_PUB_COMMIT,
#                    DAPK_PUB_MODE draft|prerelease|release, DAPK_PUB_PRE (1 = the version has a suffix), DAPK_PUB_ASSETS[] (files),
#                    DAPK_PUB_DRY=1 (print the plan, no network).   Outputs: DAPK_PUB_URL. rc 0 ok, 1 failure, 3 refused.
# Token: $GITHUB_TOKEN or $GH_TOKEN, read from the environment only; it is passed to curl on stdin (never in argv) and masked in the log.
# Environment for tests/GHE: DAPK_GITHUB_API (default https://api.github.com), DAPK_GITHUB_UPLOAD (default https://uploads.github.com)

declare -g DAPK_PUB_REPO="" DAPK_PUB_TAG="" DAPK_PUB_NAME="" DAPK_PUB_BODY="" DAPK_PUB_COMMIT="" DAPK_PUB_MODE="" DAPK_PUB_PRE=0 DAPK_PUB_DRY=0 DAPK_PUB_URL="" DAPK_PUB_ERROR=""
declare -ga DAPK_PUB_ASSETS=()
declare -g _PUB_BODY=""

_dapk.publish.jstr() {   # TEXT : JSON string literal
    local s="$1"
    s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; s="${s//$'\t'/\\t}"
    printf '"%s"' "$s"
}

# GitHub answers with pretty-printed JSON (newlines, indentation, `"key": value`); the parsers below expect the compact form `{"key":value,...}`
_dapk.publish.compact() {
    printf '%s' "$1" | tr -d '\r\n' | sed -E 's/"[[:space:]]*:[[:space:]]+/":/g; s/,[[:space:]]+"/,"/g; s/\{[[:space:]]+"/{"/g; s/\[[[:space:]]+\{/[{/g; s/[[:space:]]+([]}])/\1/g'
}

# METHOD URL [--data FILE | --upload FILE] : response body -> _PUB_BODY, rc 0 on 2xx
_dapk.publish.api() {
    local method="$1" url="$2" kind="${3:-}" file="${4:-}" tok="${GITHUB_TOKEN:-${GH_TOKEN:-}}" tmp code
    local -a args=(-sS -X "$method" -o "" -w '%{http_code}' -H 'Accept: application/vnd.github+json' -K -)
    tmp="$(mktemp "${TMPDIR:-/tmp}/dapk_pub.XXXXXX")" || return 1
    args[4]="$tmp"
    case "$kind" in
        --data)   args+=(-H 'Content-Type: application/json' --data-binary "@$file") ;;
        --upload) args+=(-H 'Content-Type: application/octet-stream' --data-binary "@$file") ;;
    esac
    _dapk.ui.log DEBUG "curl $method $url"
    code="$(printf 'header = "Authorization: Bearer %s"\n' "$tok" | curl "${args[@]}" "$url" 2>>"${DAPK_UI_LOG_FILE:-/dev/null}")" || { rm -f "$tmp"; DAPK_PUB_ERROR="network error calling $url"; return 1; }
    _PUB_BODY="$(<"$tmp")"; rm -f "$tmp"
    _PUB_BODY="$(_dapk.publish.compact "$_PUB_BODY")"
    [[ "$code" =~ ^2 ]] && return 0
    local msg="" ; [[ "$_PUB_BODY" =~ \"message\":\"([^\"]*)\" ]] && msg="${BASH_REMATCH[1]}"
    DAPK_PUB_ERROR="GitHub API $method ${url#*://*/} -> HTTP $code${msg:+: $msg}"; return 1
}

# JSON TAG -> release id whose tag_name is TAG (awk splits the compact JSON array into per-release chunks)
_dapk.publish.find_release() {
    printf '%s' "$1" | awk -v tag="$2" '{
        gsub(/\{"url":"[^"]*\/releases\/[0-9]+"/, "\001&"); n = split($0, parts, "\001")
        for (i = 1; i <= n; i++) if (match(parts[i], /\/releases\/[0-9]+"/)) {
            id = substr(parts[i], RSTART + 10, RLENGTH - 11)
            if (index(parts[i], "\"tag_name\":\"" tag "\"")) { print id; exit }
        } }'
}

# JSON NAME -> asset id of the asset called NAME
_dapk.publish.find_asset() {
    printf '%s' "$1" | awk -v nm="$2" '{
        gsub(/\{"url":"[^"]*\/releases\/assets\/[0-9]+"/, "\001&"); n = split($0, parts, "\001")
        for (i = 1; i <= n; i++) if (match(parts[i], /\/assets\/[0-9]+"/)) {
            id = substr(parts[i], RSTART + 8, RLENGTH - 9)
            if (index(parts[i], "\"name\":\"" nm "\"")) { print id; exit }
        } }'
}

dapk.publish.run() {
    local api="${DAPK_GITHUB_API:-https://api.github.com}" up="${DAPK_GITHUB_UPLOAD:-https://uploads.github.com}"
    local repo="$DAPK_PUB_REPO" tag="$DAPK_PUB_TAG" mode="$DAPK_PUB_MODE" draft prerelease body id page json a name aid n
    DAPK_PUB_ERROR=""; DAPK_PUB_URL=""
    [[ "$repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || { DAPK_PUB_ERROR="no GitHub repository: set publish_repo in dabt.pkg (owner/name) or a github.com origin remote"; return 1; }
    if (( DAPK_PUB_PRE )); then
        [[ "$mode" == release ]] && { DAPK_PUB_ERROR="$tag is a pre-release version: a full release is refused (use --prerelease or --draft)"; return 3; }
        [[ -n "$mode" ]] || mode=prerelease
    else [[ -n "$mode" ]] || mode=draft; fi
    case "$mode" in
        draft) draft=true prerelease=$( (( DAPK_PUB_PRE )) && echo true || echo false ) ;;
        prerelease) draft=false prerelease=true ;;
        release) draft=false prerelease=false ;;
        *) DAPK_PUB_ERROR="unknown publish mode '$mode'"; return 2 ;;
    esac
    body=""; [[ -r "$DAPK_PUB_BODY" ]] && body="$(<"$DAPK_PUB_BODY")"
    dapk.ui.kv repo "$repo"; dapk.ui.kv tag "$tag"; dapk.ui.kv mode "$mode (draft=$draft prerelease=$prerelease)"
    for a in "${DAPK_PUB_ASSETS[@]}"; do dapk.ui.kv asset "${a##*/}"; done
    (( DAPK_PUB_DRY )) && { dapk.ui.info "dry run: nothing was sent"; return 0; }
    [[ -n "${GITHUB_TOKEN:-${GH_TOKEN:-}}" ]] || { DAPK_PUB_ERROR="GITHUB_TOKEN (or GH_TOKEN) is not set"; return 1; }
    command -v curl >/dev/null 2>&1 || { DAPK_PUB_ERROR="curl is required to publish"; return 1; }

    # the release JSON goes through a file so nothing sensitive or large sits in argv
    local jf; jf="$(mktemp "${TMPDIR:-/tmp}/dapk_rel.XXXXXX")" || return 1
    printf '{"tag_name":%s,"name":%s,"body":%s,"draft":%s,"prerelease":%s%s}\n' "$(_dapk.publish.jstr "$tag")" "$(_dapk.publish.jstr "${DAPK_PUB_NAME:-$tag}")" \
        "$(_dapk.publish.jstr "$body")" "$draft" "$prerelease" "${DAPK_PUB_COMMIT:+,\"target_commitish\":$(_dapk.publish.jstr "$DAPK_PUB_COMMIT")}" > "$jf"

    id=""
    for page in 1 2 3 4 5; do
        _dapk.publish.api GET "$api/repos/$repo/releases?per_page=100&page=$page" || { rm -f "$jf"; return 1; }
        json="$_PUB_BODY"; [[ "$json" == "[]" || -z "$json" ]] && break
        id="$(_dapk.publish.find_release "$json" "$tag")"; [[ -n "$id" ]] && break
    done
    if [[ -n "$id" ]]; then
        dapk.ui.info "updating the existing release for $tag"
        _dapk.publish.api PATCH "$api/repos/$repo/releases/$id" --data "$jf" || { rm -f "$jf"; return 1; }
    else
        _dapk.publish.api POST "$api/repos/$repo/releases" --data "$jf" || { rm -f "$jf"; return 1; }
        [[ "$_PUB_BODY" =~ \"id\":([0-9]+) ]] && id="${BASH_REMATCH[1]}"
    fi
    rm -f "$jf"
    [[ "$_PUB_BODY" =~ \"html_url\":\"([^\"]*)\" ]] && DAPK_PUB_URL="${BASH_REMATCH[1]}"
    [[ -n "$id" ]] || { DAPK_PUB_ERROR="could not read the release id from the GitHub response"; return 1; }

    # assets: replace same-named ones
    _dapk.publish.api GET "$api/repos/$repo/releases/$id/assets?per_page=100" && json="$_PUB_BODY" || json="[]"
    n=${#DAPK_PUB_ASSETS[@]}
    dapk.ui.progress_start "Uploading assets" "$n"
    for a in "${DAPK_PUB_ASSETS[@]}"; do
        name="${a##*/}"
        aid="$(_dapk.publish.find_asset "$json" "$name")"
        [[ -n "$aid" ]] && { _dapk.publish.api DELETE "$api/repos/$repo/releases/assets/$aid" || dapk.ui.warn "could not delete the old asset $name"; }
        _dapk.publish.api POST "$up/repos/$repo/releases/$id/assets?name=$name" --upload "$a" || return 1
        dapk.ui.progress_tick
    done
    dapk.ui.progress_done "Uploaded $n asset(s)"
    return 0
}
