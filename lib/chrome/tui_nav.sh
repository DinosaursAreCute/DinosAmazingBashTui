#!/usr/bin/env bash
# tui_nav.sh - <nav>: a pane of page buttons whose item for the current page wears the active class.
#
#   <nav id="main" class="panel" item_class="nav_button" active_class="nav_active" orientation="v" active="auto">
#     <item page="home.xml" text="Home" icon="⌂" shortcut="alt+1"/>
#     <item page="mail.xml" text="Inbox" icon="✉" badge="(3)" collapsed_text="✉"/>
#   </nav>
#
# tui_compose.sh turns the nav into a pane and each item into a button (id NAVID_PAGENAME), so everything a button or
# pane does applies. _tui_build.tag.button files each item in _TUI_W_NAV; _tui_nav.sync runs after every page load
# (also a cache replay) and swaps the item classes by the page name, so the highlight stays right after Back, a
# shortcut or a tui.goto from code. active="none" files nothing.
#   tui.nav.sync     re-applies the highlight and redraws the buttons (after code changed the page without loading it)
# State: _TUI_W_NAV[button] = "PAGE_NAME BASE_CLASS ACTIVE_CLASS" (page-scoped, part of the page cache)
# requires: tui_style

declare -gA _TUI_W_NAV=()

# _tui_nav.clear - tui.reset_ui
_tui_nav.clear() { _TUI_W_NAV=(); }

# _tui_nav.sync - every nav button gets the active class when its page is the current one, else its base class. Always
# re-applied (a page replay brings back the styles of the moment it was recorded, so no memory of what was applied
# can be trusted); the nav is small. _NAV_CHANGED = the buttons, for the redraw.
_tui_nav.sync() {
	local file="${_TUI_MARKUP_FILE##*/}" id name base active want
	local -a changed=()
	file="${file%.*}"
	for id in "${!_TUI_W_NAV[@]}"; do
		[[ -n "${_TUI_W_TYPE[$id]:-}" ]] || continue # the button left with its page
		read -r name base active <<<"${_TUI_W_NAV[$id]}"
		want="$base"
		[[ "$name" == "$file" ]] && want="$active"
		_tui.style_clear "$id"
		tui.class "$id" "$want"
		changed+=("$id")
	done
	_NAV_CHANGED=("${changed[@]}")
}
declare -ga _NAV_CHANGED=()

# tui.nav.sync - re-applies the highlight and redraws the nav buttons
tui.nav.sync() {
	local id
	_tui_nav.sync
	((_TUI_RUNNING && ! _TUI_DEFER_RENDER)) || return 0
	for id in "${_NAV_CHANGED[@]}"; do _tui._draw_or_queue "$id"; done
	return 0
}
