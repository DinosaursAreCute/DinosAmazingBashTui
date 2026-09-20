#!/usr/bin/env bats
# install.sh and lib/tui_install.sh. Nothing leaves $BATS_TEST_TMPDIR (see helpers.bash).
load helpers
setup() { setup_env; source "$REPO/lib/tui_sync.sh"; source "$REPO/lib/tui_install.sh"; REL="$T/rel"; }

CONF() { echo "$XDG_CONFIG_HOME/DABT"; }
run_install() { run bash "$REL/install.sh" --yes --prefix "$T/prog" --bindir "$T/bin" "$@"; }

# ── detecting an existing install ───────────────────────────────────────
@test "detect: nothing found" { run tui.install.detect; [ "$status" -eq 1 ]; [ -z "$output" ]; }
@test "detect: ~/.config/DABT" { mkdir -p "$(CONF)"; run tui.install.detect; [ "$output" = "$(CONF)" ]; }
@test "detect: falls back to \$DABT_HOME" { mkdir -p "$T/x"; DABT_HOME="$T/x" run tui.install.detect; [ "$output" = "$T/x" ]; }
@test "detect: the default folder is checked before \$DABT_HOME" { mkdir -p "$(CONF)" "$T/x"; DABT_HOME="$T/x" run tui.install.detect; [ "$output" = "$(CONF)" ]; }

# ── the default locations and folder checks ─────────────────────────────
@test "defaults point into HOME" {
    tui.install.defaults
    [ "$TUI_INSTALL_PREFIX" = "$XDG_DATA_HOME/dabt" ]; [ "$TUI_INSTALL_CONFIG" = "$XDG_CONFIG_HOME/DABT" ]; [ "$TUI_INSTALL_BINDIR" = "$HOME/.local/bin" ]
}
@test "check_dir: rejects empty, relative, a file, an unwritable parent" {
    run tui.install.check_dir "";          [ "$status" -eq 1 ]
    run tui.install.check_dir "rel/path";  [ "$status" -eq 1 ]; [[ "$output" == "" ]]
    : > "$T/afile"; tui.install.check_dir "$T/afile" || true; [[ "$TUI_INSTALL_ERROR" == *"is a file"* ]]
    mkdir -p "$T/ro"; chmod 555 "$T/ro"; run tui.install.check_dir "$T/ro/sub"; chmod 755 "$T/ro"
    [ "$status" -eq 1 ]
}
@test "check_dir: accepts a new folder in a writable place" { run tui.install.check_dir "$T/new/deep/dir"; [ "$status" -eq 0 ]; }

# ── a fresh install into the default locations ──────────────────────────
@test "install --yes: program, defaults, plugins, meta, manifest and launcher" {
    make_release "$REL" 1.0.0
    run bash "$REL/install.sh" --yes --prefix "$XDG_DATA_HOME/dabt" --bindir "$HOME/.local/bin"
    [ "$status" -eq 0 ]
    [ -x "$XDG_DATA_HOME/dabt/bin/dabt" ]; [ -f "$XDG_DATA_HOME/dabt/lib/tui.sh" ]; [ -f "$XDG_DATA_HOME/dabt/VERSION" ]
    [ -f "$(CONF)/defaults/keybinds.xml" ]; [ -f "$(CONF)/defaults/pages/settings.xml" ]; [ -f "$(CONF)/plugins/p.plugin.sh" ]
    file_has "$(CONF)/install.meta" "version=1.0.0"
    file_has "$(CONF)/install.meta" "prefix=$XDG_DATA_HOME/dabt"
    file_has "$(CONF)/manifest" "defaults/keybinds.xml"; file_has "$(CONF)/manifest" "plugins/p.plugin.sh"
    [ -L "$HOME/.local/bin/dabt" ]; [ "$(readlink "$HOME/.local/bin/dabt")" = "$XDG_DATA_HOME/dabt/bin/dabt" ]
    [[ "$output" == *"installed DABT 1.0.0"* ]]
}
@test "install with the default config location writes no etc/dabt.env hint" {
    make_release "$REL" 1.0.0
    run bash "$REL/install.sh" --yes --prefix "$T/prog" --no-link
    [[ "$output" != *"DABT_HOME"* ]]
    [ ! -e "$HOME/.local/bin/dabt" ]
}
@test "install into custom folders records the config location and says how to find it" {
    make_release "$REL" 1.0.0
    run_install --config "$T/mycfg"
    [ "$status" -eq 0 ]
    file_has "$T/prog/etc/dabt.env" "DABT_HOME=\"$T/mycfg\""
    [ -f "$T/mycfg/defaults/theme.css" ]; [ ! -e "$(CONF)" ]
    [[ "$output" == *'export DABT_HOME='* ]]
}
@test "the installed program finds a custom config through etc/dabt.env (dabt doctor)" {
    run bash "$REPO/install.sh" --yes --prefix "$T/prog" --config "$T/mycfg" --no-link
    [ "$status" -eq 0 ]
    run "$T/prog/bin/dabt" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"config home    $T/mycfg   (found via: install)"* ]]
}
@test "the real repository installs completely (program, defaults and shipped plugins)" {
    run bash "$REPO/install.sh" --yes --prefix "$T/prog" --config "$T/cfg" --bindir "$T/bin"
    [ "$status" -eq 0 ]
    [ -f "$T/prog/lib/tui.sh" ]; [ -f "$T/prog/bin/dabt" ]; [ -f "$T/prog/share/demo/home.xml" ]; [ -f "$T/prog/docs/README.md" ]
    [ -f "$T/cfg/defaults/keybinds.xml" ]; [ -f "$T/cfg/defaults/pages/plugins.xml" ]; [ -f "$T/cfg/plugins/terminal_shortcuts.plugin.sh" ]
    [ ! -e "$T/prog/tests" ]; [ ! -e "$T/prog/tools" ]                       # dev-only folders are not shipped
    run "$T/prog/bin/dabt" doctor
    [[ "$output" == *"config home    $T/cfg"* ]]; [[ "$output" == *"installed      yes"* ]]
    run "$T/prog/bin/dabt" version
    [[ "$output" == "DABT $(<"$REPO/VERSION")" ]]
}

# ── options and safety ──────────────────────────────────────────────────
@test "--dry-run changes nothing and lists what would be installed" {
    make_release "$REL" 1.0.0
    run_install --dry-run
    [ "$status" -eq 0 ]; [[ "$output" == *"Would install DABT 1.0.0"* ]]; [[ "$output" == *"dry run: nothing was written"* ]]
    [ ! -e "$T/prog" ]; [ ! -e "$(CONF)" ]; [ ! -e "$T/bin" ]
}
@test "refuses a folder that is not a DABT release" {
    mkdir -p "$T/notdabt"; cp "$REPO/install.sh" "$T/notdabt/"; mkdir -p "$T/notdabt/lib"; cp "$REPO/lib/tui_sync.sh" "$REPO/lib/tui_install.sh" "$T/notdabt/lib/"
    run bash "$T/notdabt/install.sh" --yes --prefix "$T/prog"
    [ "$status" -eq 2 ]; [[ "$output" == *"not a DABT release"* ]]; [ ! -e "$T/prog" ]
}
@test "refuses a target that is a file" {
    make_release "$REL" 1.0.0; : > "$T/afile"
    run_install --prefix "$T/afile"
    [ "$status" -ne 0 ]; [[ "$output" == *"is a file"* ]]
}
@test "without a terminal and without --yes it refuses to guess" {
    make_release "$REL" 1.0.0
    run bash "$REL/install.sh" --prefix "$T/prog" < /dev/null
    [ "$status" -eq 2 ]; [ ! -e "$T/prog" ]
}
@test "unknown option" { run bash "$REPO/install.sh" --frobnicate; [ "$status" -eq 2 ]; }
@test "installing never modifies the source tree" { make_release "$REL" 1.0.0; run_install --config "$T/cfg"; assert_repo_untouched; run bash "$REPO/install.sh" --yes --prefix "$T/p2" --config "$T/c2" --no-link; assert_repo_untouched; }

# ── installing over an existing install (an update) ─────────────────────
@test "running the installer twice changes nothing the second time" {
    make_release "$REL" 1.0.0; run_install --config "$T/cfg"
    cp "$T/cfg/manifest" "$T/manifest.1"
    run_install --config "$T/cfg"
    [ "$status" -eq 0 ]; [[ "$output" == *"0 added, 0 updated"* ]]
    cmp "$T/cfg/manifest" "$T/manifest.1"
    file_has "$T/cfg/install.meta" "version=1.0.0"
}
@test "an existing ~/.config/DABT is detected and reused" {
    make_release "$REL" 1.0.0; run_install
    [ -f "$(CONF)/install.meta" ]
    make_release "$T/rel2" 1.1.0
    run bash "$T/rel2/install.sh" --yes --prefix "$T/prog" --bindir "$T/bin"
    [ "$status" -eq 0 ]; file_has "$(CONF)/install.meta" "version=1.1.0"; file_has "$(CONF)/install.meta" "previous_version=1.0.0"
}
@test "a default you edited is not overwritten: the new version becomes FILE.new (default policy)" {
    make_release "$REL" 1.0.0; run_install --config "$T/cfg"
    echo "my own keys" > "$T/cfg/defaults/keybinds.xml"
    make_release "$T/rel2" 1.1.0
    run bash "$T/rel2/install.sh" --yes --prefix "$T/prog" --config "$T/cfg" --bindir "$T/bin"
    [ "$status" -eq 0 ]
    [ "$(cat "$T/cfg/defaults/keybinds.xml")" = "my own keys" ]
    [ "$(cat "$T/cfg/defaults/keybinds.xml.new")" = "keybinds.xml v1.1.0" ]
    [ "$(cat "$T/cfg/defaults/theme.css")" = "theme.css v1.1.0" ]              # the untouched ones were updated
    [[ "$output" == *"conflicts: 1"* ]]
}
@test "--policy override replaces the edited file and keeps a backup of it" {
    make_release "$REL" 1.0.0; run_install --config "$T/cfg"
    echo "my own keys" > "$T/cfg/defaults/keybinds.xml"; make_release "$T/rel2" 1.1.0
    TUI_SYNC_STAMP=20260101-000000 run bash "$T/rel2/install.sh" --yes --prefix "$T/prog" --config "$T/cfg" --bindir "$T/bin" --policy override
    [ "$(cat "$T/cfg/defaults/keybinds.xml")" = "keybinds.xml v1.1.0" ]
    [ "$(cat "$T/cfg/backups/20260101-000000/defaults/keybinds.xml")" = "my own keys" ]
    [ ! -e "$T/cfg/defaults/keybinds.xml.new" ]
}
@test "--policy skip keeps the edited file and writes nothing next to it" {
    make_release "$REL" 1.0.0; run_install --config "$T/cfg"
    echo "my own keys" > "$T/cfg/defaults/keybinds.xml"; make_release "$T/rel2" 1.1.0
    run bash "$T/rel2/install.sh" --yes --prefix "$T/prog" --config "$T/cfg" --bindir "$T/bin" --policy skip
    [ "$(cat "$T/cfg/defaults/keybinds.xml")" = "my own keys" ]; [ ! -e "$T/cfg/defaults/keybinds.xml.new" ]
}
@test "files already in the config folder from before DABT recorded checksums are conflicts, never silently replaced" {
    mkdir -p "$T/cfg/defaults"; echo "pre-existing" > "$T/cfg/defaults/keybinds.xml"
    make_release "$REL" 1.0.0
    run_install --config "$T/cfg"
    [ "$(cat "$T/cfg/defaults/keybinds.xml")" = "pre-existing" ]; [ -f "$T/cfg/defaults/keybinds.xml.new" ]
}
@test "reinstalling over a program folder replaces changed program files and backs the old ones up" {
    make_release "$REL" 1.0.0; run_install --config "$T/cfg"
    make_release "$T/rel2" 1.1.0; printf 'new docs\n' > "$T/rel2/docs/README.md"
    TUI_SYNC_STAMP=20260101-000001 run bash "$T/rel2/install.sh" --yes --prefix "$T/prog" --config "$T/cfg" --bindir "$T/bin"
    [ "$(cat "$T/prog/docs/README.md")" = "new docs" ]
    [ "$(cat "$T/cfg/backups/20260101-000001/program/docs/README.md")" = "docs v1.0.0" ]
}
@test "a checkout installed in place only sets up the config (the program is left alone)" {
    make_release "$REL" 1.0.0
    run bash "$REL/install.sh" --yes --prefix "$REL" --config "$T/cfg" --no-link
    [ "$status" -eq 0 ]; [[ "$output" == *"left in place"* ]]; [ -f "$T/cfg/defaults/keybinds.xml" ]
}
