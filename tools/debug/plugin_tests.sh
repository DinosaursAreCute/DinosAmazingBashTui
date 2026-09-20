#!/usr/bin/env bash
# plugin_tests.sh - headless tests of the plugin system: discovery, enable / disable with automatic cleanup, hooks,
# requires, install / remove, persistence. Exit status = failures.
ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"; DIR="$ROOT/lib"
export XDG_CONFIG_HOME="$(mktemp -d)"; T="$XDG_CONFIG_HOME/plug"; mkdir -p "$T"; trap 'rm -rf "$XDG_CONFIG_HOME"' EXIT
stty() { [[ "$1" == size ]] && echo "30 100"; }
cd "$DIR" && source ./tui.sh
FAIL=0; N=0
ok() { (( N++ )); [[ "$2" == "$3" ]] || { (( FAIL++ )); printf 'FAIL %s: got [%s] want [%s]\n' "$1" "$2" "$3" >&3; }; }
exec 3>&1 1>/dev/null
cat > "$T/a.plugin.sh" <<'P'
# plugin: alpha
# title: Alpha
# version: 2.1
# description: first
# default: on
plugin.alpha.on_enable() { tui.cmd.add alpha.cmd "Alpha cmd" true; tui.bind alt+9 true; tui.hook.on page alpha_page; tui.every 60 alpha_tick alpha_job; ALPHA_ON=1; }
plugin.alpha.on_disable() { ALPHA_ON=0; }
alpha_page() { ALPHA_PAGE="$1"; }
alpha_tick() { :; }
P
mkdir -p "$T/beta"; cat > "$T/beta/plugin.sh" <<'P'
# plugin: beta
# requires: alpha
# description: needs alpha
plugin.beta.on_enable() { tui.cmd.add beta.cmd "Beta cmd" true; }
P
cat > "$T/bad.plugin.sh" <<'P'
# plugin: bad
plugin.bad.on_enable() { tui.cmd.add bad.cmd "Bad" true; return 1; }
P
_TPL_DIRS=("$T")        # only this folder
tui.config.load; tui.plugin.scan
ok "discovered" "$(tui.plugin.list | cut -f1 | tr '\n' ' ')" "alpha bad beta "
ok "metadata" "$(tui.plugin.get alpha version)|$(tui.plugin.get alpha title)" "2.1|Alpha"
tui.plugin.startup
printf '.a { fg: red; }\n.b { fg: blue; }\n' > "$T/t.css"; tui.load_theme "$T/t.css"      # the theme parser must not touch the plugin registry
ok "theme loading leaves the plugin list alone" "$(tui.plugin.list | wc -l)" "3"
ok "default on starts alpha" "$(tui.plugin.get alpha state) ${ALPHA_ON:-}" "enabled 1"
ok "beta not enabled" "$(tui.plugin.get beta state)" "disabled"
ok "cmd registered" "${_TUI_CMD_TITLE[alpha.cmd]:-}" "Alpha cmd"
tui.hook.fire page x.xml; ok "hook fired" "${ALPHA_PAGE:-}" "x.xml"
tui.plugin.enable beta; ok "beta enabled" "$(tui.plugin.get beta state)" "enabled"
tui.plugin.disable alpha
ok "disabling alpha disables beta first" "$(tui.plugin.get alpha state)/$(tui.plugin.get beta state)" "disabled/disabled"
ok "on_disable ran" "${ALPHA_ON:-}" "0"
ok "cmd removed automatically" "${_TUI_CMD_TITLE[alpha.cmd]:-gone}" "gone"
ok "bind removed automatically" "${_TUI_BIND[|alt+9]:-gone}" "gone"
ok "hook removed automatically" "${_TPL_HOOK[page]:-none}" "none"
ok "job removed automatically" "$(tui.every.list | grep -c alpha_job)" "0"
tui.plugin.enable bad; ok "failing plugin -> error state, nothing left" "$(tui.plugin.get bad state)/${_TUI_CMD_TITLE[bad.cmd]:-gone}" "error/gone"
ok "saved state" "$(tui.config.get plugin.alpha.enabled)|$(tui.config.get plugin.beta.enabled)" "0|0"
tui.plugin.enable alpha
tui.hook.on key alpha_eat; alpha_eat() { [[ "$1" == "x" ]]; }
tui.hook.fire key x; ok "key hook can consume" "$?" "0"; tui.hook.fire key y; ok "key hook can pass" "$?" "1"; tui.hook.off key alpha_eat
# reload picks up edits
sed -i 's/# version: 2.1/# version: 2.2/' "$T/a.plugin.sh"; tui.plugin.reload alpha
ok "reload re-reads metadata and stays enabled" "$(tui.plugin.get alpha version) $(tui.plugin.get alpha state)" "2.2 enabled"
# install / remove
mkdir -p "$XDG_CONFIG_HOME/src"; printf '# plugin: gamma\n# title: Gamma\nplugin.gamma.on_enable() { :; }\n' > "$XDG_CONFIG_HOME/src/gamma.plugin.sh"
tui.plugin.install "$XDG_CONFIG_HOME/src/gamma.plugin.sh"; ok "install registers" "$(tui.plugin.get gamma source)" "user"
ok "install copied into the user dir" "$([[ -f "$TUI_PLUGINS_DIR/gamma.plugin.sh" ]] && echo yes)" "yes"
tui.plugin.install "$XDG_CONFIG_HOME/src/gamma.plugin.sh"; ok "install refuses to overwrite" "$?" "1"
tui.plugin.enable gamma; tui.plugin.remove gamma
ok "remove unregisters and deletes" "$(tui.plugin.get gamma state)|$([[ -e "$TUI_PLUGINS_DIR/gamma.plugin.sh" ]] && echo file)" "|"
tui.plugin.remove alpha; ok "a non-user plugin is unregistered but its file stays" "$(tui.plugin.get alpha state)|$([[ -e "$T/a.plugin.sh" ]] && echo file)" "|file"
ok "provider lists remaining plugins" "$(tui.cmd.provider _tui_plugin.provide; _TUI_CMD_IN_PROVIDER=1 _tui_plugin.provide; echo "${_TUI_CMD_TITLE[plugin.on.beta]:-none}")" "Plugin: enable beta"
# ── DABT home: per-app folder, metadata, migration of the old layout ──
ok "app conf dir" "${TUI_APP_CONF#$XDG_CONFIG_HOME/}" "DABT/apps/dabt"
ok "plugins dir" "${TUI_PLUGINS_DIR#$XDG_CONFIG_HOME/}" "DABT/plugins"
TUI_APP_TITLE="Test app"; _tui_home.touch; _tui_home.touch
ok "app.meta written" "$(tui.app.meta_get name)|$(tui.app.meta_get title)|$(tui.app.meta_get runs)|$(tui.app.meta_get dabt_version)" "dabt|Test app|2|$TUI_VERSION"
tui.app.meta_set owner me; ok "custom meta key kept" "$(tui.app.meta_get owner) $(tui.app.meta_get runs)" "me 2"
(  export XDG_CONFIG_HOME="$T/oldcfg" TUI_APP_NAME=oldapp; mkdir -p "$XDG_CONFIG_HOME/oldapp"; echo "theme=x" > "$XDG_CONFIG_HOME/oldapp/dabt.conf"; echo "k" > "$XDG_CONFIG_HOME/oldapp/keybinds.xml"
   unset TUI_HOME TUI_APP_CONF TUI_PLUGINS_DIR; TUI_APP_NAME=oldapp; source "$DIR/tui_home.sh"
   echo "$([[ -f $TUI_APP_CONF/dabt.conf && -f $TUI_APP_CONF/keybinds.xml && ! -e $XDG_CONFIG_HOME/oldapp ]] && echo migrated)" > "$T/mig" )
ok "old ~/.config/<app>/ files moved into DABT/apps/<app>/" "$(<"$T/mig")" "migrated"
echo "$N checks, $FAIL failed" >&3
exit $FAIL
