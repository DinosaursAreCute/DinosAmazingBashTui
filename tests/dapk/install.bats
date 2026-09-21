#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load ../helpers
setup() {
    dapk_setup; P="$T/proj"; make_project "$P"
    cat >> "$P/dabt.pkg" <<'X'

[[dependency]]
name  = "zzz-tool"
check = "command -v zzz-tool"
pacman = "zzz-tool"
apt = "zzz-tool"

[[dependency]]
name = "opt-tool"
optional = true
pacman = "opt-tool"
X
    # a package manager that "installs" by creating the tools; MOCK_PM_FAIL=1 makes it do nothing
    cat > "$MOCKBIN/pacman" <<'M'
#!/usr/bin/env bash
echo "pacman $*" >> "$PM_LOG"
[[ -n "${MOCK_PM_FAIL:-}" ]] && exit 1
for a in "$@"; do [[ "$a" == -* ]] || { printf '#!/bin/sh\n' > "$MOCKBIN/$a"; chmod +x "$MOCKBIN/$a"; }; done
M
    chmod +x "$MOCKBIN/pacman"; export PM_LOG="$T/pm.log"; : > "$PM_LOG"
    build_project "$P" >/dev/null 2>&1; PKG="$(pkg_of "$P")"
    INST=(bash "$DABT" app install "$PKG" --trust-key "$FP" --no-scan)
    installed() { bash "$DABT" app list | grep -q '^demoapp '; }
    marker() { [ -f "$TUI_HOME/apps.deps/demoapp" ]; }
}

@test "install: verifies, shows News, installs and registers the app" {
    run "${INST[@]}" --no-deps
    [ "$status" -eq 0 ]; [[ "$output" == *"What's new"* ]]; [[ "$output" == *"Shiny new thing"* ]]
    installed; [ -f "$TUI_HOME/apps/demoapp/app.sh" ]; [ -f "$TUI_HOME/apps/demoapp/MANIFEST" ]
    run bash "$DABT" app info demoapp; [[ "$output" == *"$PKG"* ]]
}

@test "install: a tampered package installs nothing" {
    unpack() { rm -rf "$T/x"; mkdir "$T/x"; tar -xzf "$PKG" -C "$T/x"; }; unpack
    echo evil >> "$T/x/demoapp-1.2.3-7/app.sh"
    ( cd "$T/x" && { echo demoapp-1.2.3-7/MANIFEST; echo demoapp-1.2.3-7/MANIFEST.sig; find demoapp-1.2.3-7 ! -name MANIFEST ! -name MANIFEST.sig; } | tar --no-recursion -czf "$T/bad.dapk" -T - )
    run bash "$DABT" app install "$T/bad.dapk" --trust-key "$FP" --no-scan --no-deps
    [ "$status" -eq 1 ]; ! installed; [ ! -d "$TUI_HOME/apps/demoapp" ]
}

@test "install --plan: verifies and plans, installs nothing" {
    run "${INST[@]}" --plan; [ "$status" -eq 0 ]; [[ "$output" == *"plan only"* ]]; [[ "$output" == *"will run:"*"zzz-tool"* ]]
    ! installed; [ ! -s "$PM_LOG" ]
}

@test "install --install-path: the app lives at that folder and remove works there" {
    run "${INST[@]}" --no-deps --install-path "$T/myapps/demo"; [ "$status" -eq 0 ]
    [ -f "$T/myapps/demo/app.sh" ]; bash "$DABT" app list | grep -q "$T/myapps/demo"
    run bash "$DABT" app remove demoapp --yes; [ "$status" -eq 0 ]; [ ! -e "$T/myapps/demo/app.sh" ]
}

@test "install: an update shows only the News newer than the installed version; app update reinstalls from the recorded package" {
    "${INST[@]}" --no-deps >/dev/null 2>&1
    echo 1.3.0 > "$P/VERSION"; printf '## [Unreleased]\n### News\n- Even newer\n\n' > "$T/n.md"; cat "$T/n.md" "$P/CHANGELOG.md" | grep -v '^# Changelog' > "$T/cl.md"; { echo '# Changelog'; cat "$T/cl.md"; } > "$P/CHANGELOG.md"
    rm -rf "$P/dist"; build_project "$P" >/dev/null 2>&1
    run bash "$DABT" app install "$(pkg_of "$P")" --no-scan --no-deps
    [ "$status" -eq 0 ]; [[ "$output" == *"you have 1.2.3"* ]]; [[ "$output" == *"Even newer"* ]]; [[ "$output" != *"Old thing"* ]]
    run bash "$DABT" app update demoapp --no-deps 2>&1; bash "$DABT" app list | grep -q '^demoapp *1.3.0'
}

# ── dependencies (docs/concepts/dapk-packaging.md, 11.2) ───────────────────
@test "deps default without a terminal: warn, install the app anyway, mark deps unmet, run nothing" {
    run "${INST[@]}"; [ "$status" -eq 0 ]; [[ "$output" == *"no terminal to ask on"* ]]
    installed; marker; [ ! -s "$PM_LOG" ]
    run bash "$DABT" app run --entry app.sh demoapp 2>&1; [[ "$output" == *"unmet dependencies"* ]]
}

@test "--no-deps: warns, installs, marks unmet, never asks or runs the package manager" {
    run "${INST[@]}" --no-deps; [ "$status" -eq 0 ]; [[ "$output" == *"--no-deps"* ]]; installed; marker; [ ! -s "$PM_LOG" ]
}

@test "--install-dependencies without a terminal and without --yes fails and installs nothing" {
    run "${INST[@]}" --install-dependencies --pm pacman; [ "$status" -eq 1 ]; [[ "$output" == *"pass --yes"* ]]; ! installed; [ ! -s "$PM_LOG" ]
}

@test "--install-dependencies --yes: one batched package-manager call, required and optional together" {
    run "${INST[@]}" --install-dependencies --yes --pm pacman; [ "$status" -eq 0 ]
    installed; ! marker
    [ "$(wc -l < "$PM_LOG")" -eq 1 ]; grep -qx 'pacman -S --needed --noconfirm zzz-tool opt-tool' "$PM_LOG"
}

@test "--yes alone answers the default prompt (installs the dependencies)" {
    run "${INST[@]}" --yes --pm pacman; [ "$status" -eq 0 ]; installed; ! marker; grep -q zzz-tool "$PM_LOG"
}

@test "--require-deps: no terminal and no --yes fails, nothing installed" {
    run "${INST[@]}" --require-deps --pm pacman; [ "$status" -eq 1 ]; ! installed
}

@test "--require-deps --yes: a failing dependency install aborts the app install" {
    MOCK_PM_FAIL=1 run "${INST[@]}" --require-deps --yes --pm pacman; [ "$status" -eq 1 ]; [[ "$output" == *"still missing"* ]]; ! installed; [ ! -d "$TUI_HOME/apps/demoapp" ]
}

@test "flag conflicts: --no-deps with --require-deps or --install-dependencies is a usage error (2)" {
    run "${INST[@]}" --no-deps --require-deps; [ "$status" -eq 2 ]
    run "${INST[@]}" --no-deps --install-dependencies; [ "$status" -eq 2 ]
}

@test "optional dependencies never fail --require-deps" {
    sed -i '/name  = "zzz-tool"/,/apt = "zzz-tool"/d' "$P/dabt.pkg"; sed -i '/^\[\[dependency\]\]$/{N;/^\[\[dependency\]\]\n$/d}' "$P/dabt.pkg"
    rm -rf "$P/dist"; build_project "$P" >/dev/null 2>&1
    run bash "$DABT" app install "$(pkg_of "$P")" --trust-key "$FP" --no-scan --require-deps; [ "$status" -eq 0 ]; installed
}

@test "custom install commands: never batched, need their own consent (--yes does not cover them)" {
    printf '\n[[dependency]]\nname = "cust"\ninstall = "touch %s/custom_ran"\n' "$T" >> "$P/dabt.pkg"
    rm -rf "$P/dist"; build_project "$P" >/dev/null 2>&1; PKG="$(pkg_of "$P")"
    run bash "$DABT" app install "$PKG" --trust-key "$FP" --no-scan --yes --pm pacman; [ "$status" -eq 0 ]
    [ ! -e "$T/custom_ran" ]; [[ "$output" == *"custom command (cust)"* ]]; marker
    run bash "$DABT" app install "$PKG" --no-scan --yes --pm pacman --allow-custom-install --force; [ -e "$T/custom_ran" ]
}

@test "version gate: min_version with version_cmd" {
    printf '\n[[dependency]]\nname = "gate"\ncheck = "true"\nversion_cmd = "echo gate 1.2.0"\nmin_version = "2.0"\n' >> "$P/dabt.pkg"
    rm -rf "$P/dist"; build_project "$P" >/dev/null 2>&1
    run bash "$DABT" app install "$(pkg_of "$P")" --trust-key "$FP" --no-scan --no-deps; [[ "$output" == *"gate (missing)"* ]]
    sed -i 's/min_version = "2.0"/min_version = "1.0"/' "$P/dabt.pkg"; rm -rf "$P/dist"; build_project "$P" >/dev/null 2>&1
    run bash "$DABT" app install "$(pkg_of "$P")" --no-scan --no-deps --force; [[ "$output" != *"gate (missing)"* ]]
}

@test "pkg deps APP: re-checks an installed app, installs with --yes and clears the marker" {
    "${INST[@]}" >/dev/null 2>&1; marker
    run bash "$DABT" pkg deps demoapp --yes --pm pacman; [ "$status" -eq 0 ]; ! marker; grep -q zzz-tool "$PM_LOG"
}

@test "install: a zip (workflow artifact) holding one .dapk installs" {
    ( cd "$(dirname "$PKG")" && bsdtar -a -cf "$T/dapk.zip" "$(basename "$PKG")" 2>/dev/null || zip -q "$T/dapk.zip" "$(basename "$PKG")" )
    run bash "$DABT" app install "$T/dapk.zip" --trust-key "$FP" --no-scan --no-deps
    [ "$status" -eq 0 ]; [[ "$output" == *"unpacked"* ]]; installed
}
