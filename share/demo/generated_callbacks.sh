#!/usr/bin/env bash
# generated_callbacks.sh - Generated page: the control panel feeds numbers into a page built from a template and loops.
# "Generate" keeps the entered values in $TUI_APP_CONF/gen.conf (so they come back on the next visit) and writes
# $TUI_APP_CONF/addons/gen_values.xml - an addon that sets `count`, `title`, `items` and `compact` on the nodes of
# generated.xml. tui.page.refresh then re-applies the addons to the page on screen and rebuilds only the pane that
# changed (the generated cards); the control panel, and what you typed into it, is not touched.
# Any whole number up to 999999 is accepted on purpose, so you can find out what happens when the page gets big: the
# time follows the number of widgets generated (see the guide), and panes get too small for their content ("min space").
# The addon targets generated.xml only, so no other page is affected.

declare -gA GN=()

_gn_paths() {
	_GN_CONF="${TUI_APP_CONF:-}/gen.conf"
	_GN_ADDON="${TUI_APP_CONF:-}/addons/gen_values.xml"
}

_gn_defaults() { GN=([cards]=3 [items]=2 [title]=Card [compact]=false); }

_gn_load() {
	_gn_paths
	_gn_defaults
	local k v
	[[ -r "$_GN_CONF" ]] || return 0
	while IFS='=' read -r k v; do [[ -n "${GN[$k]+x}" ]] && GN[$k]="$v"; done <"$_GN_CONF"
}

# _gn_int VALUE MIN MAX DEFAULT -> _GN_INT : a whole number clamped into MIN..MAX, DEFAULT when it is not one
_gn_int() {
	local v="${1//[[:space:]]/}"
	[[ "$v" =~ ^[0-9]{1,6}$ ]] || {
		_GN_INT=$4
		return
	}
	v=$((10#$v))
	((v < $2)) && v=$2
	((v > $3)) && v=$3
	_GN_INT=$v
}

# _gn_xml TEXT -> _GN_XML : TEXT safe inside a double-quoted attribute, shortened to 20 characters
_gn_xml() {
	local v="${1//[$'\n\r\t']/ }"
	v="${v:0:20}"
	v="${v//&/"&amp;"}" # quoted replacements: an unquoted & would stand for the matched text (patsub_replacement)
	v="${v//</"&lt;"}"
	v="${v//>/"&gt;"}"
	_GN_XML="${v//\"/"&quot;"}"
}

generated_visit() {
	_gn_load
	tui.set inp_cards "${GN[cards]}"
	tui.set inp_items "${GN[items]}"
	tui.set inp_title "${GN[title]}"
	[[ "${GN[compact]}" == true ]] && tui.set chk_compact 1
}

on_gen_apply() {
	[[ -n "${TUI_APP_CONF:-}" ]] || {
		tui.notify "No app config folder: can't generate here." warn
		return
	}
	local title v compact=false
	_gn_paths
	tui.get inp_cards v # tui.get with a variable name: no subshell
	_gn_int "$v" 0 999999 3
	GN[cards]=$_GN_INT
	tui.get inp_items v
	_gn_int "$v" 0 999999 2
	GN[items]=$_GN_INT
	tui.get inp_title title
	[[ -n "${title//[[:space:]]/}" ]] || title=Card
	_gn_xml "$title"
	GN[title]="$_GN_XML"
	tui.get chk_compact v
	[[ "$v" == 1 ]] && compact=true
	GN[compact]=$compact
	[[ -d "${_GN_ADDON%/*}" ]] || mkdir -p "${_GN_ADDON%/*}"
	printf '%s=%s\n' cards "${GN[cards]}" items "${GN[items]}" title "${GN[title]}" compact "$compact" >"$_GN_CONF"
	cat >"$_GN_ADDON" <<XML
<addon id="gen_values" target="generated.xml" prefix="false">
  <set ref="#cards" attr="count" value="${GN[cards]}"/>
  <set ref="#cards > use" attr="title" value="${GN[title]}"/>
  <set ref="#cards > use" attr="items" value="${GN[items]}"/>
  <set ref="#cards > use" attr="compact" value="$compact"/>
</addon>
XML
	tui.page.refresh # the generated pane is rebuilt; the control panel (and what you typed) stays
}
