#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load ../helpers
setup() {
    dapk_setup; P="$T/proj"; make_project "$P"
    printf 'publish_repo = "me/demoapp"\n' | cat - "$P/dabt.pkg" > "$T/pkg" && mv "$T/pkg" "$P/dabt.pkg"
    export GITHUB_TOKEN=ghp_SECRET123 DAPK_GITHUB_API=https://api.test DAPK_GITHUB_UPLOAD=https://up.test
    export REQ_LOG="$T/req.log" STDIN_LOG="$T/stdin.log" BODY_LOG="$T/body.log"; : > "$REQ_LOG"; : > "$STDIN_LOG"; : > "$BODY_LOG"
    # a GitHub that answers from $REMOTE/*.json and records every request
    cat > "$MOCKBIN/curl" <<'M'
#!/usr/bin/env bash
method=GET; out=""; url=""; data=""
cat >> "$STDIN_LOG" 2>/dev/null <<< "$(cat)"
while (( $# )); do case "$1" in -X) method="$2"; shift ;; -o) out="$2"; shift ;; --data-binary) data="${2#@}"; shift ;; -w|-H|-K) shift ;; -*) ;; *) url="$1" ;; esac; shift; done
echo "$method $url" >> "$REQ_LOG"; [[ -n "$data" && "$data" == *dapk_rel* ]] && cat "$data" >> "$BODY_LOG"
code=200; body='{}'
case "$method $url" in
  "GET https://api.test/repos/me/demoapp/releases?"*page=1) body="$(cat "$REMOTE/releases.json" 2>/dev/null || echo '[]')" ;;
  "GET https://api.test/repos/me/demoapp/releases?"*) body='[]' ;;
  "POST https://api.test/repos/me/demoapp/releases") code=201; body='{"url":"https://api.test/repos/me/demoapp/releases/99","html_url":"https://github.com/me/demoapp/releases/tag/v1","id":99}' ;;
  "PATCH https://api.test/repos/me/demoapp/releases/"*) body='{"url":"https://api.test/repos/me/demoapp/releases/99","html_url":"https://github.com/me/demoapp/releases/tag/v1","id":99}' ;;
  "GET https://api.test/repos/me/demoapp/releases/"*"/assets"*) body="$(cat "$REMOTE/assets.json" 2>/dev/null || echo '[]')" ;;
  "DELETE "*) code=204; body='' ;;
  "POST https://up.test/"*) code=201; body='{"id":5}' ;;
  *) code=404; body='{"message":"Not Found"}' ;;
esac
[[ -n "${MOCK_HTTP_FAIL:-}" && "$method" == POST && "$url" == *releases ]] && { code=422; body='{"message":"Validation Failed"}'; }
[[ -n "$out" ]] && printf '%s' "$body" > "$out"; printf '%s' "$code"
M
    chmod +x "$MOCKBIN/curl"
    build_project "$P" >/dev/null 2>&1
}

@test "publish: a plain version becomes a DRAFT; assets uploaded; the token never appears in argv" {
    run bash -c "cd '$P' && bash '$DABT' pkg publish"; [ "$status" -eq 0 ]
    grep -q '"draft":true,"prerelease":false' "$BODY_LOG"; grep -q '"tag_name":"v1.2.3"' "$BODY_LOG"
    grep -q '^POST https://api.test/repos/me/demoapp/releases$' "$REQ_LOG"
    for a in 'demoapp-1.2.3-7.dapk' 'demoapp-1.2.3-7.dapk.sha256' 'demoapp-news.txt'; do grep -qF "POST https://up.test/repos/me/demoapp/releases/99/assets?name=$a" "$REQ_LOG"; done
    ! grep -q ghp_SECRET123 "$REQ_LOG"; grep -q ghp_SECRET123 "$STDIN_LOG"
    grep -q 'Shiny new thing' "$BODY_LOG"                                      # the rendered release notes are the body
}

@test "publish: --prerelease and --release set the flags; --draft is the default" {
    run bash -c "cd '$P' && bash '$DABT' pkg publish --prerelease"; grep -q '"draft":false,"prerelease":true' "$BODY_LOG"
    : > "$BODY_LOG"; run bash -c "cd '$P' && bash '$DABT' pkg publish --release"; grep -q '"draft":false,"prerelease":false' "$BODY_LOG"
}

@test "publish: a suffixed version defaults to a pre-release and refuses --release (exit 3)" {
    rm -rf "$P/dist"; build_project "$P" --suffix rc.1 >/dev/null 2>&1
    run bash -c "cd '$P' && bash '$DABT' pkg publish --suffix rc.1"; [ "$status" -eq 0 ]; grep -q '"draft":false,"prerelease":true' "$BODY_LOG"; grep -q '"tag_name":"v1.2.3-rc.1"' "$BODY_LOG"
    : > "$REQ_LOG"; run bash -c "cd '$P' && bash '$DABT' pkg publish --suffix rc.1 --release"; [ "$status" -eq 3 ]; [ ! -s "$REQ_LOG" ]
    : > "$BODY_LOG"; run bash -c "cd '$P' && bash '$DABT' pkg publish --suffix rc.1 --draft"; grep -q '"draft":true,"prerelease":true' "$BODY_LOG"
}

@test "publish: idempotent - an existing release is updated (draft promoted) and same-named assets are replaced" {
    printf '[{"url":"https://api.test/repos/me/demoapp/releases/99","id":99,"tag_name":"v1.2.3","draft":true}]' > "$REMOTE/releases.json"
    printf '[{"url":"https://api.test/repos/me/demoapp/releases/assets/7","id":7,"name":"demoapp-news.txt"}]' > "$REMOTE/assets.json"
    run bash -c "cd '$P' && bash '$DABT' pkg publish --release"; [ "$status" -eq 0 ]
    grep -q '^PATCH https://api.test/repos/me/demoapp/releases/99$' "$REQ_LOG"; ! grep -q '^POST https://api.test/repos/me/demoapp/releases$' "$REQ_LOG"
    grep -q '^DELETE https://api.test/repos/me/demoapp/releases/assets/7$' "$REQ_LOG"
    grep -q '"draft":false,"prerelease":false' "$BODY_LOG"
}

@test "publish: --dry-run sends nothing; a missing token, repo or package fails clearly" {
    run bash -c "cd '$P' && bash '$DABT' pkg publish --dry-run"; [ "$status" -eq 0 ]; [ ! -s "$REQ_LOG" ]
    run bash -c "cd '$P' && GITHUB_TOKEN= bash '$DABT' pkg publish"; [ "$status" -eq 1 ]; [[ "$output" == *"GITHUB_TOKEN"* ]]
    sed -i '/^publish_repo/d' "$P/dabt.pkg"; run bash -c "cd '$P' && bash '$DABT' pkg publish"; [ "$status" -eq 1 ]; [[ "$output" == *"no GitHub repository"* ]]
    rm -rf "$P/dist"; run bash -c "cd '$P' && bash '$DABT' pkg publish"; [ "$status" -eq 1 ]; [[ "$output" == *"run  dabt build  first"* ]]
}

@test "publish: an API error is reported with the HTTP status and message" {
    MOCK_HTTP_FAIL=1 run bash -c "cd '$P' && bash '$DABT' pkg publish"; [ "$status" -eq 1 ]; [[ "$output" == *"HTTP 422"*"Validation Failed"* ]]
}

@test "publish: only the package of exactly this version and suffix is picked (not another suffix's build)" {
    build_project "$P" --suffix dev >/dev/null 2>&1                                 # dist now also holds demoapp-1.2.3-dev-7.dapk
    run bash -c "cd '$P' && bash '$DABT' pkg publish --dry-run"; [ "$status" -eq 0 ]; [[ "$output" == *"demoapp-1.2.3-7.dapk"* ]]; [[ "$output" != *"dev"* ]]
    run bash -c "cd '$P' && bash '$DABT' pkg publish --dry-run --suffix dev"; [[ "$output" == *"demoapp-1.2.3-dev-7.dapk"* ]]
}
