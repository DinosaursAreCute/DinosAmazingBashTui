#!/usr/bin/env bash
# tui_own.sh - ownership tracking: what a plugin registered while it loads, so disabling it can undo exactly that.
#
#   _tui_plugin.own TYPE VALUE     records that the plugin being enabled owns VALUE of TYPE (cmd, bind, hook, tick, ...);
#                                  the public wrapper tui.plugin.own lives in tui_plugin.sh
#
# Loaded before everything else so any module can call _tui_plugin.own while it is being sourced; the plugin loader
# (tui_plugin.sh) sets _TPL_CUR and replays _TPL_OWN when it disables a plugin.
# requires:

declare -gA _TPL_OWN=() # PLUGIN -> "TYPE<TAB>VALUE" lines, in registration order
declare -g _TPL_CUR=""  # the plugin being enabled, empty outside a plugin load

_tui_plugin.own() {
	[[ -n "${_TPL_CUR:-}" ]] && _TPL_OWN[$_TPL_CUR]+="$1"$'\t'"$2"$'\n'
	return 0
}
