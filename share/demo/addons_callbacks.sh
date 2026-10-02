#!/usr/bin/env bash
# addons_callbacks.sh - Addons demo page: tick example addons, press Apply, and the page changes with them.
# The examples live in addon_examples/*.xml next to this file. Applying copies the ticked ones into $TUI_APP_CONF/addons/
# (the folder every DABT app reads addons from) and empties the others, then tui.page.refresh re-applies the addons to
# the page on screen: only the panes that changed are rebuilt, within the 100 ms of a page switch.
# Every example targets addons.xml only, so no other page of the demo is touched.

_AD_DIR="${BASH_SOURCE[0]%/*}/addon_examples"
_AD_NAMES=(banner toolbar retitle shout tidy)

# Everything below avoids starting processes ($(...), cp, rm): a handler runs while the user waits. A file is "switched
# off" by emptying it - an empty addon file adds nothing - and read back with `[[ -s ]]`.

_AD_DEST="" # the folder addons are read from (empty when the app has no config folder)
_ad_dest() { _AD_DEST="${TUI_APP_CONF:+$TUI_APP_CONF/addons}"; }

addons_visit() {
	local n active=0
	_ad_dest
	for n in "${_AD_NAMES[@]}"; do
		if [[ -n "$_AD_DEST" && -s "$_AD_DEST/$n.xml" ]]; then
			tui.set "chk_$n" 1
			active=$((active + 1))
		fi
	done
	tui.update lbl_state "$active of ${#_AD_NAMES[@]} addons applied to this page"
}

on_addon_apply() {
	local n v content
	_ad_dest
	[[ -n "$_AD_DEST" ]] || {
		tui.notify "No app config folder: addons can't be applied here." warn
		return
	}
	[[ -d "$_AD_DEST" ]] || mkdir -p "$_AD_DEST"
	for n in "${_AD_NAMES[@]}"; do
		tui.get "chk_$n" v
		if [[ "$v" == 1 ]]; then
			content="$(<"$_AD_DIR/$n.xml")" # `$(<file)` reads without a subshell
			printf '%s\n' "$content" >"$_AD_DEST/$n.xml"
		else
			: >"$_AD_DEST/$n.xml"
		fi
	done
	tui.page.refresh # only the panes the addons changed are rebuilt: within the 100 ms of a page switch
	addons_visit     # the status line counts the files now switched on
}

on_addon_click() { tui.notify "Pressed '$1'" info; }
