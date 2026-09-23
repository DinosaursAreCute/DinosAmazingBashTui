#!/usr/bin/env bash
# tui_home.sh - where DABT keeps its files. One home for everything, one folder per application:
#
#   ~/.config/DABT/                      TUI_HOME          (found as described in _tui_home.locate below)
#       defaults/                        TUI_DEFAULTS_DIR  default keybinds, commands, theme and default pages (copied here by the installer)
#       plugins/                         TUI_PLUGINS_DIR   plugins: the ones that ship with DABT (copied here) and yours - shared by every app
#       install.meta, manifest           what was installed, and the checksums the updater compares against
#       backups/                         files the updater replaced
#       apps/<TUI_APP_NAME>/             TUI_APP_CONF      one folder per application:
#           dabt.conf                      framework settings (theme overlay, default-key groups, notifications, plugin on/off ...)
#           keybinds.xml                   your saved keybinds
#           settings.conf                  the application's own settings (the demo's Settings page)
#           app.meta                       metadata about the application (below)
#           terminal_shortcuts.*           state of the terminal_shortcuts plugin (backups it needs to restore your terminal)
#
# TUI_APP_NAME (default "dabt") must be set BEFORE tui.sh is sourced. app.meta is key=value, written by tui.init:
#   name, title (TUI_APP_TITLE), description (TUI_APP_DESC), dabt_version, app_dir (where the pages live), entry,
#   first_run, last_run, runs  - and anything else you store with tui.app.meta_set.
#   tui.app.meta_get KEY [DEFAULT]    tui.app.meta_set KEY VALUE    tui.app.dir  (prints TUI_APP_CONF)
# Files from the old layout (~/.config/<app>/{dabt.conf,keybinds.xml,settings.conf}) are moved here the first time.

declare -g TUI_ROOT="${TUI_ROOT:-$(cd -P "${BASH_SOURCE[0]%/*}/.." && pwd -P)}" # the program: the folder that holds lib/ bin/ share/
declare -g TUI_VERSION="0.0.6"
[[ -r "$TUI_ROOT/VERSION" ]] && {
	read -r TUI_VERSION <"$TUI_ROOT/VERSION"
	TUI_VERSION="${TUI_VERSION//[[:space:]]/}"
}
declare -g TUI_APP_NAME="${TUI_APP_NAME:-dabt}"

# Where is DABT's config home? First match wins:
#   1. $TUI_HOME (explicit override)          2. ~/.config/DABT (or $XDG_CONFIG_HOME/DABT) when it exists
#   3. $DABT_HOME when it points at a folder  4. the location the installer recorded in $TUI_ROOT/etc/dabt.env
#   5. otherwise the default path, flagged as missing (TUI_HOME_SOURCE=missing: not installed yet)
declare -g TUI_HOME_SOURCE=""
_tui_home.locate() {
	local xdg="${XDG_CONFIG_HOME:-$HOME/.config}" line
	if [[ -n "${TUI_HOME:-}" ]]; then
		TUI_HOME_SOURCE=TUI_HOME
	elif [[ -d "$xdg/DABT" ]]; then
		TUI_HOME="$xdg/DABT"
		TUI_HOME_SOURCE=default
	elif [[ -n "${DABT_HOME:-}" && -d "$DABT_HOME" ]]; then
		TUI_HOME="$DABT_HOME"
		TUI_HOME_SOURCE=DABT_HOME
	else
		TUI_HOME=""
		if [[ -r "$TUI_ROOT/etc/dabt.env" ]]; then
			while IFS= read -r line; do [[ "$line" == DABT_HOME=* ]] && line="${line#DABT_HOME=}" && line="${line//\"/}" && [[ -d "$line" ]] && TUI_HOME="$line" && TUI_HOME_SOURCE=install; done <"$TUI_ROOT/etc/dabt.env"
		fi
		[[ -n "$TUI_HOME" ]] || {
			TUI_HOME="$xdg/DABT"
			TUI_HOME_SOURCE=missing
		}
	fi
}
_tui_home.locate
declare -g TUI_HOME
declare -g TUI_INSTALLED=0
[[ -f "$TUI_HOME/install.meta" ]] && TUI_INSTALLED=1
declare -g TUI_APP_CONF="${TUI_APP_CONF:-$TUI_HOME/apps/$TUI_APP_NAME}"
declare -g TUI_PLUGINS_DIR="${TUI_PLUGINS_DIR:-$TUI_HOME/plugins}"
# the defaults (keybinds, commands, theme, default pages): the config home's copy when installed, else the ones shipped in share/
if [[ -z "${TUI_DEFAULTS_DIR:-}" ]]; then
	if [[ -d "$TUI_HOME/defaults" ]]; then TUI_DEFAULTS_DIR="$TUI_HOME/defaults"; else TUI_DEFAULTS_DIR="$TUI_ROOT/share/defaults"; fi
fi
declare -g TUI_DEFAULTS_DIR

declare -gA _TUI_META=()

_tui_home.migrate() {
	local old="${XDG_CONFIG_HOME:-$HOME/.config}/$TUI_APP_NAME" f
	[[ -d "$old" && "$old" != "$TUI_APP_CONF" ]] || return 0
	for f in dabt.conf keybinds.xml settings.conf; do
		if [[ -f "$old/$f" && ! -e "$TUI_APP_CONF/$f" ]]; then
			mkdir -p "$TUI_APP_CONF" && mv "$old/$f" "$TUI_APP_CONF/$f"
		fi
	done
	rmdir "$old" 2>/dev/null
	return 0
}
_tui_home.migrate

tui.app.dir() { printf '%s\n' "$TUI_APP_CONF"; }

_tui_home.meta_load() {
	local line
	_TUI_META=()
	[[ -r "$TUI_APP_CONF/app.meta" ]] || return 0
	while IFS= read -r line; do
		[[ "$line" == \#* || "$line" != *=* ]] && continue
		_TUI_META["${line%%=*}"]="${line#*=}"
	done <"$TUI_APP_CONF/app.meta"
}
_tui_home.meta_save() {
	local k out="" ordered
	mkdir -p "$TUI_APP_CONF" 2>/dev/null || return 1
	for k in name title description dabt_version app_dir entry first_run last_run runs; do
		[[ -n "${_TUI_META[$k]+x}" ]] && out+="$k=${_TUI_META[$k]}"$'\n'
	done
	for k in $(printf '%s\n' "${!_TUI_META[@]}" | sort); do
		case "$k" in name | title | description | dabt_version | app_dir | entry | first_run | last_run | runs) ;; *) out+="$k=${_TUI_META[$k]}"$'\n' ;; esac
	done
	printf '# DABT application metadata (written by tui.init; add your own keys with tui.app.meta_set)\n%s' "$out" >"$TUI_APP_CONF/app.meta.tmp" && mv -f "$TUI_APP_CONF/app.meta.tmp" "$TUI_APP_CONF/app.meta"
}
tui.app.meta_get() {
	[[ -n "${_TUI_META[$1]+x}" ]] || _tui_home.meta_load
	printf '%s' "${_TUI_META[$1]-${2:-}}"
}
tui.app.meta_set() {
	_tui_home.meta_load
	_TUI_META[$1]="$2"
	_tui_home.meta_save
}

# called by tui.init: record that the application ran
_tui_home.touch() {
	local now
	printf -v now '%(%Y-%m-%d %H:%M:%S)T' -1
	_tui_home.meta_load
	_TUI_META[name]="$TUI_APP_NAME"
	[[ -n "${TUI_APP_TITLE:-}" ]] && _TUI_META[title]="$TUI_APP_TITLE"
	[[ -n "${TUI_APP_DESC:-}" ]] && _TUI_META[description]="$TUI_APP_DESC"
	_TUI_META[dabt_version]="$TUI_VERSION"
	[[ -n "${_TUI_APP_DIR:-}" ]] && _TUI_META[app_dir]="$_TUI_APP_DIR"
	[[ -n "${TUI_APP_ENTRY:-}" ]] && _TUI_META[entry]="$TUI_APP_ENTRY"
	[[ -n "${_TUI_META[first_run]:-}" ]] || _TUI_META[first_run]="$now"
	_TUI_META[last_run]="$now"
	_TUI_META[runs]=$((${_TUI_META[runs]:-0} + 1))
	_tui_home.meta_save
}
