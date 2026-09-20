#!/usr/bin/env bats
# Where does DABT look for its config home? (lib/tui_home.sh)  Order: $TUI_HOME, ~/.config/DABT, $DABT_HOME, etc/dabt.env, missing.
load helpers
setup() { setup_env; }

locate() { bash -c 'source "$REPO/lib/tui_home.sh"; echo "$TUI_HOME_SOURCE|$TUI_HOME|$TUI_INSTALLED|$TUI_DEFAULTS_DIR"'; }

@test "nothing exists: the default path, flagged as missing, and the defaults come from the program's share/" {
    run locate
    [ "$status" -eq 0 ]
    [ "$output" = "missing|$XDG_CONFIG_HOME/DABT|0|$REPO/share/defaults" ]
}

@test "~/.config/DABT exists: that one is used" {
    mkdir -p "$XDG_CONFIG_HOME/DABT"
    run locate
    [[ "$output" == "default|$XDG_CONFIG_HOME/DABT|0|"* ]]
}

@test "the default folder wins over \$DABT_HOME" {
    mkdir -p "$XDG_CONFIG_HOME/DABT" "$T/elsewhere"
    DABT_HOME="$T/elsewhere" run locate
    [[ "$output" == "default|$XDG_CONFIG_HOME/DABT|"* ]]
}

@test "no default folder: \$DABT_HOME is used when it points at a folder" {
    mkdir -p "$T/elsewhere"
    DABT_HOME="$T/elsewhere" run locate
    [[ "$output" == "DABT_HOME|$T/elsewhere|"* ]]
}

@test "\$DABT_HOME pointing at nothing is ignored" {
    DABT_HOME="$T/nope" run locate
    [[ "$output" == "missing|"* ]]
}

@test "the location the installer recorded (etc/dabt.env) is the fallback" {
    mkdir -p "$T/prog/etc" "$T/cfg" "$T/prog/lib"
    cp "$REPO/lib/tui_home.sh" "$T/prog/lib/"
    printf 'DABT_HOME="%s"\n' "$T/cfg" > "$T/prog/etc/dabt.env"
    run bash -c 'source "$T/prog/lib/tui_home.sh"; echo "$TUI_HOME_SOURCE|$TUI_HOME"'
    [ "$output" = "install|$T/cfg" ]
}

@test "an explicit TUI_HOME beats everything" {
    mkdir -p "$XDG_CONFIG_HOME/DABT" "$T/mine"
    TUI_HOME="$T/mine" run locate
    [[ "$output" == "TUI_HOME|$T/mine|"* ]]
}

@test "installed config: defaults come from the config home, and install.meta marks it installed" {
    mkdir -p "$XDG_CONFIG_HOME/DABT/defaults"; echo "version=1" > "$XDG_CONFIG_HOME/DABT/install.meta"
    run locate
    [ "$output" = "default|$XDG_CONFIG_HOME/DABT|1|$XDG_CONFIG_HOME/DABT/defaults" ]
}

@test "the plugins folder and the per-app folder live in the config home" {
    mkdir -p "$XDG_CONFIG_HOME/DABT"
    run bash -c 'TUI_APP_NAME=myapp; source "$REPO/lib/tui_home.sh"; echo "$TUI_PLUGINS_DIR|$TUI_APP_CONF"'
    [ "$output" = "$XDG_CONFIG_HOME/DABT/plugins|$XDG_CONFIG_HOME/DABT/apps/myapp" ]
}

@test "old ~/.config/<app>/ files are moved into the new layout" {
    mkdir -p "$XDG_CONFIG_HOME/oldapp"; echo "theme=x" > "$XDG_CONFIG_HOME/oldapp/dabt.conf"
    run bash -c 'TUI_APP_NAME=oldapp; source "$REPO/lib/tui_home.sh"; [[ -f "$TUI_APP_CONF/dabt.conf" && ! -e "$XDG_CONFIG_HOME/oldapp" ]] && echo moved'
    [ "$output" = "moved" ]
}

@test "the tests never touch the source tree" { assert_repo_untouched; }
