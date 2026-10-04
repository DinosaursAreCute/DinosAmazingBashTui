#!/usr/bin/env bash
# ╔════════════════════════════════════════════════════════════════════════╗
# ║    tui_registry.sh                                                     ║
# ╚════════════════════════════════════════════════════════════════════════╝
# tui.register KIND NAME FN...             registers one or more handlers for NAME under KIND
# tui.registered KIND NAME                 looks up NAME's handlers -> $_TUI_REGISTERED
# tui.register.style_contract NAME DESC... registers a style contract (kind "style")
#
# One registry for every kind of pluggable handler (markup-v2 stage 0.4):
# tag, widget, layout, validator, pseudo, expr, hook, style. A later
# registration for the same KIND/NAME is appended, not replacing earlier
# ones - callers that want "last wins" read the last word of $_TUI_REGISTERED,
# callers that want every handler (hooks) iterate the whole list.
#
# Plugin ownership: a registration made while $_TUI_REGISTRY_CURRENT_PLUGIN
# is set is attributed to that plugin via _tui_registry.own, so
# _tui_registry.unregister_plugin removes exactly what it added and nothing
# the framework or another plugin registered for the same KIND/NAME.
#
# Named _tui_registry.own/_tui_registry.unregister_plugin rather than
# _tui_plugin.own/tui.plugin.own: those names already exist (lib/plugin/
# tui_plugin.sh, out of this module's owner file) for the general "what a
# plugin's on_disable undoes" list (cmd/bind/hook/tick/...), a different
# shape (TYPE VALUE, keyed off the currently-loading plugin) from this
# registry's KIND/NAME/FN triples. Wiring an actual plugin's on_disable to
# also call _tui_registry.unregister_plugin is for whichever stage next
# touches tui_plugin.sh.

declare -gA _TUI_REGISTRY=()        # "KIND:NAME" -> space-joined FN list, registration order
declare -gA _TUI_REGISTRY_OWNER=()  # "KIND:NAME:FN" -> owning plugin name
declare -gA _TUI_PLUGIN_OWNS=()     # PLUGIN -> space-joined "KIND:NAME:FN" list
declare -g _TUI_REGISTRY_CURRENT_PLUGIN=""

# tui.register KIND NAME FN... - appends FN (one or more) as handlers for
# NAME under KIND. Attributed to $_TUI_REGISTRY_CURRENT_PLUGIN when set.
tui.register() {
	local kind="$1" name="$2"
	shift 2
	local key="$kind:$name" fn
	[[ "$kind" == widget ]] && _tui_widget.bind "$name" "$@"
	for fn in "$@"; do
		[[ "$fn" == - ]] && continue
		_TUI_REGISTRY[$key]="${_TUI_REGISTRY[$key]:+${_TUI_REGISTRY[$key]} }$fn"
		[[ -n "$_TUI_REGISTRY_CURRENT_PLUGIN" ]] && _tui_registry.own "$_TUI_REGISTRY_CURRENT_PLUGIN" "$kind" "$name" "$fn"
	done
	return 0
}

# tui.registered KIND NAME -> $_TUI_REGISTERED - the space-joined handler
# list for KIND/NAME, registration order (last = most recent override).
# Returns 1 and empties $_TUI_REGISTERED when nothing is registered.
tui.registered() {
	local kind="$1" name="$2"
	_TUI_REGISTERED="${_TUI_REGISTRY[$kind:$name]:-}"
	[[ -n "$_TUI_REGISTERED" ]]
}

# _tui_registry.own PLUGIN KIND NAME FN - records that PLUGIN owns this one
# registration, so _tui_registry.unregister_plugin can undo exactly it later.
_tui_registry.own() {
	local plugin="$1" kind="$2" name="$3" fn="$4"
	local okey="$kind:$name:$fn"
	_TUI_REGISTRY_OWNER[$okey]="$plugin"
	_TUI_PLUGIN_OWNS[$plugin]="${_TUI_PLUGIN_OWNS[$plugin]:+${_TUI_PLUGIN_OWNS[$plugin]} }$okey"
}

# _tui_registry.unregister_plugin PLUGIN - removes every handler PLUGIN
# registered (via tui.register while it was $_TUI_REGISTRY_CURRENT_PLUGIN,
# or via a direct _tui_registry.own call), leaving handlers owned by the
# framework or other plugins untouched.
_tui_registry.unregister_plugin() {
	local plugin="$1" okey kind name fn key rest f
	for okey in ${_TUI_PLUGIN_OWNS[$plugin]:-}; do
		kind="${okey%%:*}"
		rest="${okey#*:}"
		name="${rest%%:*}"
		fn="${rest#*:}"
		key="$kind:$name"
		rest=""
		for f in ${_TUI_REGISTRY[$key]:-}; do
			[[ "$f" == "$fn" ]] && continue
			rest="${rest:+$rest }$f"
		done
		_TUI_REGISTRY[$key]="$rest"
		[[ "$kind" == widget ]] && _tui_widget.unbind_missing "$name"
		unset '_TUI_REGISTRY_OWNER[$okey]'
	done
	unset '_TUI_PLUGIN_OWNS[$plugin]'
}

# tui.register.style_contract NAME DESC... - registers NAME's style
# contract (kind "style"): the pseudo-states it can enter and the framework
# classes it draws with, e.g. "states:hover focus" "classes:.list_sel".
# One table for the CSS lint, the XSD generator and tui.class instead of a
# hard-coded state list in each.
tui.register.style_contract() {
	local name="$1"
	shift
	tui.register style "$name" "$*"
}

# ── style contracts for every existing widget type and chrome element ─────
tui.register.style_contract button "focusable:yes" "states:hover focus active disabled"
tui.register.style_contract label "states:"
tui.register.style_contract checkbox "focusable:yes" "states:checked unchecked focus hover"
tui.register.style_contract input "focusable:yes" "states:focus hover"
tui.register.style_contract password "focusable:yes" "states:focus hover"
tui.register.style_contract textarea "focusable:yes" "states:focus hover"
tui.register.style_contract select "focusable:yes" "states:focus hover"
tui.register.style_contract progress "states:" "classes:.progress .progress_fill"
tui.register.style_contract list "focusable:yes" "states:focus hover" "classes:.list_sel"
tui.register.style_contract table "focusable:yes" "states:focus hover" "classes:.table_head .table_sel"
tui.register.style_contract tabs "states:" "classes:.tab_header .tab_header_compact"
tui.register.style_contract pane "states:border title focus"
tui.register.style_contract resize_handle "states:hover"
tui.register.style_contract collapse_button "states:hover collapsed"
