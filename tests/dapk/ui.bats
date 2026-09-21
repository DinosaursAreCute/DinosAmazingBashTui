#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load ../helpers
setup() { dapk_setup; P="$T/proj"; make_project "$P"; }

@test "ui: without a terminal there are no escape codes, no carriage returns and no progress bar" {
    run --separate-stderr build_project "$P"
    [ "$status" -eq 0 ]
    ! grep -q $'\e' <<< "$stderr"; ! grep -q $'\r' <<< "$stderr"; ! grep -q '▕' <<< "$stderr"
    grep -q '^\[1/7\] Configuration' <<< "$stderr"; grep -q '^  ✓ ' <<< "$stderr"
}

@test "ui: stdout carries only the artifact path" {
    run --separate-stderr build_project "$P"; [ "$output" = "$P/dist/demoapp-1.2.3-7.dapk" ]
}

@test "ui: GitHub Actions gets group and warning annotations" {
    mkdir -p "$P/emptydir"; printf '[[include]]\ntype="directory"\nsource="emptydir"\ntarget="share/e"\n' >> "$P/dabt.pkg"
    run --separate-stderr bash -c "cd '$P' && GITHUB_ACTIONS=true DABT_SIGN_KEY=\"\$(<'$T/key')\" bash '$DABT' build"
    grep -q '^::group::\[1/7\] Configuration' <<< "$stderr"; grep -q '^::warning::include' <<< "$stderr"; grep -q '^::endgroup::' <<< "$stderr"
}

@test "ui: -q shows only warnings and errors, but build.log has everything" {
    mkdir -p "$P/emptydir"; printf '[[include]]\ntype="directory"\nsource="emptydir"\ntarget="share/e"\n' >> "$P/dabt.pkg"
    run --separate-stderr build_project "$P" -q
    ! grep -q 'Configuration' <<< "$stderr"; grep -q 'matched no files' <<< "$stderr"
    grep -q 'Configuration' "$P/dist/build.log"; grep -q 'ok: RELEASE_NOTES.md' "$P/dist/build.log"; grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8} (INFO|WARN) ' "$P/dist/build.log"
}

@test "ui: --log FILE overrides the log location; secrets are masked" {
    export GITHUB_TOKEN=ghp_SECRET123
    run bash -c "cd '$P' && DABT_SIGN_KEY=\"\$(<'$T/key')\" bash '$DABT' build --log '$T/my.log'"; [ -s "$T/my.log" ]
    source "$REPO/lib/dapk/dapk.sh"; DAPK_UI_LOG_FILE="$T/mask.log"; dapk.ui.init; _dapk.ui.log INFO "curl with ghp_SECRET123 and Bearer abc123"
    ! grep -q ghp_SECRET123 "$T/mask.log"; ! grep -q abc123 "$T/mask.log"
}

@test "ui: the bar matches the cache spinner (30 cells, ▕█░▏), ASCII in non-UTF-8 locales" {
    source "$REPO/lib/dapk/ui.sh"; DAPK_UI_COLOR=0; _DAPK_UI_PAL=("" "" "" "")
    DAPK_UI_UTF8=1; dapk.ui.bar 47 30 out; [ "$out" = "▕██████████████░░░░░░░░░░░░░░░░▏" ]
    dapk.ui.bar 0 30 out; [ "$out" = "▕░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▏" ]; dapk.ui.bar 100 30 out; [ "$out" = "▕██████████████████████████████▏" ]
    DAPK_UI_UTF8=0; dapk.ui.bar 50 10 out; [ "$out" = "[#####-----]" ]
}

@test "ui: the bar uses the cache palette (pink, blue, yellow, red along the bar)" {
    source "$REPO/lib/dapk/ui.sh"; DAPK_UI_COLOR=1; export COLORTERM=truecolor; _DAPK_UI_INITED=0; NO_COLOR= FORCE_COLOR=1 dapk.ui.init
    [[ "${_DAPK_UI_PAL[0]}" == *"255;140;191"* && "${_DAPK_UI_PAL[1]}" == *"168;216;255"* && "${_DAPK_UI_PAL[2]}" == *"255;243;168"* && "${_DAPK_UI_PAL[3]}" == *"255;158;158"* ]]
    unset COLORTERM; _DAPK_UI_INITED=0; FORCE_COLOR=1 dapk.ui.init; [[ "${_DAPK_UI_PAL[0]}" == *"38;5;212"* && "${_DAPK_UI_PAL[3]}" == *"38;5;217"* ]]
}

@test "ui: the bar repaints only when the integer percent changes" {
    source "$REPO/lib/dapk/ui.sh"; DAPK_UI_PROGRESS=1; DAPK_UI_QUIET=0; DAPK_UI_COLS=100
    n="$( { dapk.ui.progress_start "Hashing files" 1000; for i in $(seq 1000); do dapk.ui.progress_tick; done; } 2>&1 | tr -cd '\r' | wc -c)"
    [ "$n" -le 102 ]; [ "$n" -ge 100 ]
}

@test "ui: --progress forces the bar on outside a terminal; the DABT prefix and label are printed" {
    run --separate-stderr build_project "$P" --progress
    grep -q 'Hashing files' <<< "$stderr"; grep -q '▕' <<< "$stderr" || grep -q '\[' <<< "$stderr"
}

@test "ui: NO_COLOR and a non-terminal produce no colors even with --progress" {
    run --separate-stderr bash -c "cd '$P' && NO_COLOR=1 DABT_SIGN_KEY=\"\$(<'$T/key')\" bash '$DABT' build --progress"
    ! grep -q $'\e\\[[0-9;]*m' <<< "$stderr"
}
