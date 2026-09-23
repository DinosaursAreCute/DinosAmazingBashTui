#!/usr/bin/env bats
# lib/apps/tui_sync.sh (the three-way compare) and lib/apps/tui_update.sh (check, download, plan, apply, CLI).
# The network is a mock (helpers.bash: mock_network); every write happens in $BATS_TEST_TMPDIR.
load helpers

setup() {
    setup_env; mock_network
    source "$REPO/lib/apps/tui_sync.sh"; source "$REPO/lib/apps/tui_install.sh"; source "$REPO/lib/apps/tui_update.sh"
    export TUI_ROOT="$T/prog" TUI_HOME="$T/cfg" TUI_VERSION=1.0.0
    make_release "$T/v1" 1.0.0
    bash "$T/v1/install.sh" --yes --prefix "$T/prog" --config "$T/cfg" --no-link > /dev/null
    N="$T/v2"; make_release "$N" 1.1.0
}

# ── version numbers ─────────────────────────────────────────────────────
@test "version compare" {
    tui.version.newer 1.0.1 1.0.0; tui.version.newer 0.10.0 0.9.2; tui.version.newer v2.0 1.9.9; tui.version.newer 1.0.0.1 1.0.0
    ! tui.version.newer 1.0.0 1.0.0; ! tui.version.newer 0.9.9 1.0.0; ! tui.version.newer 1.2 1.10
}

# ── checking ────────────────────────────────────────────────────────────
@test "check: a newer version is available (rc 0) and asks the right URL" {
    pack_release "$N"
    tui.update.check; [ "$?" -eq 0 ]
    [ "$TUI_UPDATE_LATEST" = "1.1.0" ]
    grep -q '^https://api.github.com/repos/DinosaursAreCute/DinosAmazingBashTui/releases/latest$' "$CURL_LOG"
}
@test "check: up to date (rc 1)" { pack_release "$T/v1"; run tui.update.check; [ "$status" -eq 1 ]; }
@test "check: the remote is older (rc 1)" { make_release "$T/old" 0.9.0; pack_release "$T/old"; run tui.update.check; [ "$status" -eq 1 ]; }
@test "check: no network (rc 2, with a reason)" {
    MOCK_CURL_FAIL=1 tui.update.check || rc=$?
    [ "$rc" -eq 2 ]; [[ "$TUI_UPDATE_ERROR" == *"could not reach"* ]]
}
@test "check: an answer that is not a version number (rc 2)" { echo "<html>404</html>" > "$REMOTE/VERSION"; tui.update.check || rc=$?; [ "$rc" -eq 2 ]; }
@test "check: the repository and branch can be changed" {
    pack_release "$N"; TUI_UPDATE_REPO=someone/fork TUI_UPDATE_BRANCH=dev tui.update.check
    grep -q 'repos/someone/fork/releases/latest' "$CURL_LOG"
}

# ── download ────────────────────────────────────────────────────────────
@test "download unpacks a release archive (GitHub layout) into DIR/src" {
    pack_release "$N"; mkdir -p "$T/dl"
    tui.update.download "$T/dl"
    [ -f "$T/dl/src/VERSION" ]; [ "$(cat "$T/dl/src/VERSION")" = "1.1.0" ]
    grep -q 'archive/refs/heads/main.tar.gz' "$CURL_LOG"
}
@test "download: refuses something that is not a DABT release" {
    mkdir -p "$T/junk/x"; echo hi > "$T/junk/x/file"; tar -czf "$REMOTE/release.tar.gz" -C "$T/junk" x
    run tui.update.download "$T/dl"; [ "$status" -eq 1 ]
    tui.update.download "$T/dl" || true; [[ "$TUI_UPDATE_ERROR" == *"not a DABT release"* ]]
}
@test "download: a corrupt archive is reported" { echo "not a tarball" > "$REMOTE/release.tar.gz"; tui.update.download "$T/dl" || true; [[ "$TUI_UPDATE_ERROR" == *"valid archive"* ]]; }
@test "download: network failure" { MOCK_CURL_FAIL=1 tui.update.download "$T/dl" || true; [[ "$TUI_UPDATE_ERROR" == *"download failed"* ]]; }

# ── the plan: every kind of file ────────────────────────────────────────
scenario() {   # v1 is installed; touch the world so that all categories appear
    # A untouched by me, changed upstream        -> UPDATE      (theme.css: default in v2 already differs)
    # B changed by me, unchanged upstream        -> KEEP        (commands.xml)
    printf 'my commands\n' > "$T/cfg/defaults/commands.xml"; printf 'commands.xml v1.0.0\n' > "$N/share/defaults/commands.xml"
    # C changed by both                          -> CONFLICT    (keybinds.xml)
    printf 'my keys\n' > "$T/cfg/defaults/keybinds.xml"
    # D new upstream                             -> ADD
    printf 'brand new\n' > "$N/share/defaults/pages/plugins.xml"
    # E dropped upstream, untouched by me        -> REMOVE      (plugins/p.plugin.sh gone from v2)
    rm "$N/share/plugins/p.plugin.sh"
    # F dropped upstream but I changed it        -> ORPHAN
    printf 'q v1\n' > "$T/cfg/plugins/q.plugin.sh"; tui.sync.apply "$T/v1" "$T/cfg" >/dev/null   # (q is not in v1's release: only a user file)
    # G identical to the new one                 -> SAME        (pages/settings.xml)
    printf 'settings same\n' > "$T/cfg/defaults/pages/settings.xml"; printf 'settings same\n' > "$N/share/defaults/pages/settings.xml"
}

@test "plan: each file lands in the right category" {
    scenario
    # make E and F real: ship p and q in v1's manifest
    printf 'q v1\n' > "$T/v1/share/plugins/q.plugin.sh"; tui.sync.apply "$T/v1" "$T/cfg" >/dev/null
    printf 'q mine\n' > "$T/cfg/plugins/q.plugin.sh"
    tui.sync.plan "$N" "$T/cfg"
    [[ " ${TUI_SYNC_UPDATE[*]} " == *" defaults/theme.css "* ]]
    [[ " ${TUI_SYNC_KEEP[*]} " == *" defaults/commands.xml "* ]]
    [[ " ${TUI_SYNC_CONFLICT[*]} " == *" defaults/keybinds.xml "* ]]
    [[ " ${TUI_SYNC_ADD[*]} " == *" defaults/pages/plugins.xml "* ]]
    [[ " ${TUI_SYNC_REMOVE[*]} " == *" plugins/p.plugin.sh "* ]]
    [[ " ${TUI_SYNC_ORPHAN[*]} " == *" plugins/q.plugin.sh "* ]]
    [[ " ${TUI_SYNC_SAME[*]} " == *" defaults/pages/settings.xml "* ]]
}
@test "plan changes nothing on disk" {
    scenario; before="$(find "$T/cfg" -type f | sort | xargs sha256sum)"
    tui.sync.plan "$N" "$T/cfg"; tui.sync.program_plan "$N" "$T/prog"
    [ "$before" = "$(find "$T/cfg" -type f | sort | xargs sha256sum)" ]
}
@test "program plan: added, changed, removed and unchanged files" {
    printf 'extra\n' > "$N/docs/NEW.md"; rm "$N/README.md"
    tui.sync.program_plan "$N" "$T/prog"
    [[ " ${TUI_SYNC_P_ADD[*]} " == *" docs/NEW.md "* ]]; [[ " ${TUI_SYNC_P_UPDATE[*]} " == *" VERSION "* ]]; [[ " ${TUI_SYNC_P_REMOVE[*]} " == *" README.md "* ]]
    [[ " ${TUI_SYNC_P_SAME[*]} " == *" lib/tui.sh "* ]]
}
@test "report lists the changed files by category" {
    scenario; tui.sync.plan "$N" "$T/cfg"; tui.sync.program_plan "$N" "$T/prog"
    run tui.sync.report
    [[ "$output" == *"CONFLICTS"*"defaults/keybinds.xml"* ]]; [[ "$output" == *"Program files changed"*"VERSION"* ]]; [[ "$output" == *"Config files added"*"plugins.xml"* ]]
}
@test "report: no changes" { tui.sync.plan "$T/v1" "$T/cfg"; tui.sync.program_plan "$T/v1" "$T/prog"; run tui.sync.report; [ "$output" = "No changes." ]; }

# ── applying: the three answers for a conflict ──────────────────────────
@test "apply, policy new: mine stays, FILE.new appears, the rest is updated" {
    scenario; TUI_SYNC_POLICY=new tui.sync.apply "$N" "$T/cfg"
    [ "$(cat "$T/cfg/defaults/keybinds.xml")" = "my keys" ]; [ "$(cat "$T/cfg/defaults/keybinds.xml.new")" = "keybinds.xml v1.1.0" ]
    [ "$(cat "$T/cfg/defaults/theme.css")" = "theme.css v1.1.0" ]; [ "$(cat "$T/cfg/defaults/commands.xml")" = "my commands" ]
    [ -f "$T/cfg/defaults/pages/plugins.xml" ]; [ ! -e "$T/cfg/plugins/p.plugin.sh" ]
    [ "${TUI_SYNC_COUNT[new]}" -eq 1 ]
}
@test "apply, policy override: the new file replaces mine and mine is backed up" {
    scenario; TUI_SYNC_STAMP=20260202-020202 TUI_SYNC_POLICY=override tui.sync.apply "$N" "$T/cfg"
    [ "$(cat "$T/cfg/defaults/keybinds.xml")" = "keybinds.xml v1.1.0" ]; [ ! -e "$T/cfg/defaults/keybinds.xml.new" ]
    [ "$(cat "$T/cfg/backups/20260202-020202/defaults/keybinds.xml")" = "my keys" ]
    [ "${TUI_SYNC_COUNT[override]}" -eq 1 ]
}
@test "apply, policy skip: nothing changes for the conflicting file" {
    scenario; TUI_SYNC_POLICY=skip tui.sync.apply "$N" "$T/cfg"
    [ "$(cat "$T/cfg/defaults/keybinds.xml")" = "my keys" ]; [ ! -e "$T/cfg/defaults/keybinds.xml.new" ]; [ "${TUI_SYNC_COUNT[skip]}" -eq 1 ]
}
@test "apply with a resolver: one answer per file (the interactive case)" {
    scenario
    printf 'more mine\n' > "$T/cfg/defaults/pages/settings.xml"; printf 'settings v2\n' > "$N/share/defaults/pages/settings.xml"
    resolve() { case "$1" in defaults/keybinds.xml) echo override ;; *) echo skip ;; esac; }
    tui.sync.apply "$N" "$T/cfg" resolve
    [ "$(cat "$T/cfg/defaults/keybinds.xml")" = "keybinds.xml v1.1.0" ]; [ "$(cat "$T/cfg/defaults/pages/settings.xml")" = "more mine" ]
}
@test "a skipped or .new conflict stays a conflict next time; an override does not" {
    scenario; TUI_SYNC_POLICY=skip tui.sync.apply "$N" "$T/cfg"
    tui.sync.plan "$N" "$T/cfg"; [[ " ${TUI_SYNC_CONFLICT[*]} " == *" defaults/keybinds.xml "* ]]
    TUI_SYNC_POLICY=override tui.sync.apply "$N" "$T/cfg"
    tui.sync.plan "$N" "$T/cfg"; [ "${#TUI_SYNC_CONFLICT[@]}" -eq 0 ]
}
@test "the manifest records what was written" {
    scenario; tui.sync.apply "$N" "$T/cfg"; sha="$(sha256sum "$T/cfg/defaults/theme.css")"
    grep -qF "${sha%% *}  defaults/theme.css" "$T/cfg/manifest"
    ! grep -q 'plugins/p.plugin.sh' "$T/cfg/manifest"
}
@test "applying twice is a no-op" {
    scenario; tui.sync.apply "$N" "$T/cfg"; cp "$T/cfg/manifest" "$T/m1"
    TUI_SYNC_POLICY=new tui.sync.apply "$N" "$T/cfg"; cmp "$T/cfg/manifest" "$T/m1"; [ "${TUI_SYNC_COUNT[add]}" -eq 0 ]
}

# ── apply the whole update ──────────────────────────────────────────────
@test "update.apply: program files, config files, install.meta and a summary" {
    scenario; TUI_SYNC_STAMP=20260303-030303 TUI_SYNC_POLICY=new tui.update.apply "$N"
    [ "$(cat "$T/prog/VERSION")" = "1.1.0" ]; [ "$(cat "$T/prog/docs/README.md")" = "docs v1.1.0" ]
    file_has "$T/cfg/install.meta" "version=1.1.0"; file_has "$T/cfg/install.meta" "previous_version=1.0.0"
    [ -d "$T/cfg/backups/20260303-030303" ]
    printf '%s\n' "${TUI_UPDATE_RESULT[@]}" | grep -q "updated to 1.1.0"
}
@test "update.apply on a git checkout: config is updated, program files are left alone" {
    scenario; mkdir "$T/prog/.git"; before="$(cat "$T/prog/docs/README.md")"
    TUI_SYNC_POLICY=new tui.update.apply "$N"
    [ "$(cat "$T/prog/docs/README.md")" = "$before" ]; [ "$(cat "$T/cfg/defaults/theme.css")" = "theme.css v1.1.0" ]
    printf '%s\n' "${TUI_UPDATE_RESULT[@]}" | grep -q "git checkout"
}
@test "update.plan on a git checkout reports no program changes" { mkdir "$T/prog/.git"; tui.update.plan "$N"; [ "$TUI_UPDATE_GIT" -eq 1 ]; [ "${#TUI_SYNC_P_UPDATE[@]}" -eq 0 ]; }
@test "update.apply refuses a folder that is not a release" { mkdir -p "$T/junk"; run tui.update.apply "$T/junk"; [ "$status" -eq 1 ]; }

# ── the command line: dabt update ───────────────────────────────────────
@test "cli --check: newer version -> rc 10 and a message, nothing changed" {
    pack_release "$N"; run tui.update.cli --check
    [ "$status" -eq 10 ]; [[ "$output" == *"A newer version is available: 1.1.0 (you have 1.0.0)"* ]]; [ "$(cat "$T/prog/VERSION")" = "1.0.0" ]
}
@test "cli: up to date" { pack_release "$T/v1"; run tui.update.cli; [ "$status" -eq 0 ]; [[ "$output" == *"up to date"* ]]; }
@test "cli: network down" { MOCK_CURL_FAIL=1 run tui.update.cli; [ "$status" -eq 2 ]; [[ "$output" == *"Could not check for updates"* ]]; }
@test "cli --yes: downloads, shows what changed, applies (conflicts get .new)" {
    printf 'my keys\n' > "$T/cfg/defaults/keybinds.xml"; pack_release "$N"
    run tui.update.cli --yes
    [ "$status" -eq 0 ]
    [[ "$output" == *"What would change"* ]]; [[ "$output" == *"CONFLICTS"*"defaults/keybinds.xml"* ]]; [[ "$output" == *"updated to 1.1.0"* ]]
    [ "$(cat "$T/prog/VERSION")" = "1.1.0" ]; [ "$(cat "$T/cfg/defaults/keybinds.xml")" = "my keys" ]; [ -f "$T/cfg/defaults/keybinds.xml.new" ]
}
@test "cli --yes --policy override" {
    printf 'my keys\n' > "$T/cfg/defaults/keybinds.xml"; pack_release "$N"
    run tui.update.cli --yes --policy override
    [ "$(cat "$T/cfg/defaults/keybinds.xml")" = "keybinds.xml v1.1.0" ]
}
@test "cli asks per conflict on the terminal (answers come from a file, not a real tty)" {
    printf 'my keys\n' > "$T/cfg/defaults/keybinds.xml"; printf 'my theme\n' > "$T/cfg/defaults/theme.css"; pack_release "$N"
    printf 'y\no\ns\n' > "$T/answers"                              # apply? yes; keybinds: override; theme: skip
    TUI_UPDATE_TTY="$T/answers" run tui.update.cli
    [ "$status" -eq 0 ]
    [ "$(cat "$T/cfg/defaults/keybinds.xml")" = "keybinds.xml v1.1.0" ]; [ "$(cat "$T/cfg/defaults/theme.css")" = "my theme" ]
}
@test "cli: answering no changes nothing" {
    pack_release "$N"; printf 'n\n' > "$T/answers"
    TUI_UPDATE_TTY="$T/answers" run tui.update.cli
    [[ "$output" == *"Nothing was changed"* ]]; [ "$(cat "$T/prog/VERSION")" = "1.0.0" ]
}
@test "cli: a broken download is reported and changes nothing" {
    pack_release "$N"; echo garbage > "$REMOTE/release.tar.gz"
    run tui.update.cli --yes
    [ "$status" -eq 1 ]; [[ "$output" == *"Download failed"* ]]; [ "$(cat "$T/prog/VERSION")" = "1.0.0" ]
}
@test "updating never touches the source tree" { pack_release "$N"; run tui.update.cli --yes; assert_repo_untouched; }

# ── channels ────────────────────────────────────────────────────────────
@test "release channel downloads the tag archive" {
    pack_release "$N"; tui.update.check; mkdir -p "$T/dl"; tui.update.download "$T/dl"
    grep -q 'archive/refs/tags/v1.1.0.tar.gz' "$CURL_LOG"
}
@test "dev channel reads VERSION and the archive from main, and offers main even at the same version" {
    pack_release "$T/v1"; TUI_UPDATE_CHANNEL=dev tui.update.check; [ "$?" -eq 0 ]
    grep -q 'raw.githubusercontent.com/.*/main/VERSION' "$CURL_LOG"
    mkdir -p "$T/dl"; TUI_UPDATE_CHANNEL=dev tui.update.download "$T/dl"
    grep -q 'archive/refs/heads/main.tar.gz' "$CURL_LOG"
}
@test "check: no release published (rc 2, points to --dev)" {
    : > "$REMOTE/latest.json"; tui.update.check || rc=$?; [ "$rc" -eq 2 ]; [[ "$TUI_UPDATE_ERROR" == *"--dev"* ]]
}
