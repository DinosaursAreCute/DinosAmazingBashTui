#!/usr/bin/env bash
# tui_footer.sh - the footer bar (like Textual's): a one-row strip on the LAST terminal row that shows the keys for
# quitting, the command bar, ... It is a page-level component, not a pane: wherever <footer/> appears in the markup,
# it is drawn on the bottom row of the terminal and the outermost pane is made one row shorter to leave room for it.
#
#   <footer/>                                       the default items
#   <footer items="@tui.action.quit|Quit;ctrl+s|Save"/>
#   tui.footer.show [ITEMS] | tui.footer.hide | tui.footer.add KEYSPEC LABEL [WHEN_FN]     (runtime; they relayout)| tui.footer.hide | tui.footer.add KEYSPEC LABEL [WHEN_FN]
#
# ITEMS = items separated by ';', each  KEY|LABEL[|WHEN_FN]:
#   KEY       shown as written ("ctrl+s"), or  @COMMAND  to show the key currently bound to that command, looked up
#             live from the bindings (your own, code, then defaults), so it follows rebinding. Unbound = skipped.
#   WHEN_FN   optional predicate; the item is shown only while it succeeds.
# Default: quit, command bar, and Back (only when there is a page to go back to).
# Style: theme classes .footer (the bar), .footer_key (a key chip), .footer_label; built-in colours when absent.
# Offered to the screen after every render and once per loop like any overlay (tui_modal.sh), but only written when the
# row would change (new content, a resize or an erase); rebuilt when the bindings, the terminal width or the page history
# change.
# requires:
declare -g TUI_FOOTER_DEFAULT='@tui.action.quit|Quit;@tui.palette.open|Command bar;@tui.action.back|Back|_tui_cmd.has_history;@tui.action.resize_mode|Resize|_tui_resize.can_enter;arrows|Resize|_tui_resize.in_mode;enter|Done|_tui_resize.in_mode;@tui.action.collapse_toggle|Collapse|_tui_collapse.can_collapse;@tui.action.collapse_toggle|Expand|_tui_collapse.can_expand;@tui.action.page_reset|Reset page|tui.page.resettable'
declare -g _TUI_FOOTER_ON=0 _TUI_FOOTER_ITEMS="" _TUI_FOOTER_STR="" _TUI_FOOTER_STAMP=""
declare -g _TUI_BIND_GEN=0 # bumped by every binding change (footer / palette hints re-read the keys)
# What the bottom row shows right now ("ROWS:STRING", empty after an erase). Not _TUI_FOOTER_*: those are part of every page
# snapshot, and this describes the screen, not the page.
declare -g _TUI_FTR_PAINTED=""

# tui.footer.set ITEMS - declare the footer (what <footer/> calls, also replayed from the page cache). It only records the
# state; the page's final layout leaves the last row free. At runtime use tui.footer.show, which also relayouts.
tui.footer.set() {
	_TUI_FOOTER_ITEMS="${1:-$TUI_FOOTER_DEFAULT}"
	_TUI_FOOTER_STAMP=""
	if ((! _TUI_FOOTER_ON)); then
		_TUI_FOOTER_ON=1
		tui.layer.fn_add _tui_footer.draw ambient
	fi
	return 0
}
tui.footer.show() {
	tui.footer.set "$1"
	if ((_TUI_RUNNING)); then
		_tui._root_w
		_tui._root_h
		tui.frame.request
	fi
}
tui.footer.add() { tui.footer.show "${_TUI_FOOTER_ITEMS:-$TUI_FOOTER_DEFAULT};$1|$2${3:+|$3}"; }
tui.footer.hide() {
	((_TUI_FOOTER_ON)) || return 0
	_TUI_FOOTER_ON=0
	tui.layer.fn_remove _tui_footer.draw
	if ((_TUI_RUNNING)); then
		_tui._root_w
		_tui._root_h
		tui.frame.request
	fi
}
# tui.reset_ui: the footer belongs to the page that declared it
_tui_footer.reset() {
	_TUI_FOOTER_ON=0
	_TUI_FOOTER_ITEMS=""
	_TUI_FOOTER_STAMP=""
	tui.layer.fn_remove _tui_footer.draw
}

# the outermost pane leaves the last row to the footer
_tui._root_h() { _TUI_P_H[root]=$((_TUI_ROWS - _TUI_FOOTER_ON)); }

# root's own width, from the live terminal - never from a cached snapshot.
# _TUI_P_W (like every other _TUI_P_* array) is inside tui.cache.record's
# snapshot regex, so a cache-hit replay's `_tui_cache_restore` blindly
# overwrites _TUI_P_W[root] with whatever width was live when the page was
# *recorded* - stale the moment the app runs at a different terminal size
# than that. _tui._root_h already self-heals height the same way (from
# _TUI_ROWS, not the restored value); this is its width counterpart, called
# alongside it everywhere root's own size needs to be current, not cached.
_tui._root_w() { _TUI_P_W[root]=$_TUI_COLS; }

_tui_footer.build() {
	local k spec key label when item plain=0 seg s_bar s_key s_lbl out="" w=$_TUI_COLS
	local -a items
	_tui_input.reverse_keys
	tui.class.sgr footer
	s_bar="${TUI_SGR:-$'\e[0;37;48;2;30;34;52m'}"
	tui.class.sgr footer_key
	s_key="${TUI_SGR:-$'\e[1;30;48;2;97;175;239m'}"
	tui.class.sgr footer_label
	s_lbl="${TUI_SGR:-$s_bar}"
	IFS=';' read -ra items <<<"$_TUI_FOOTER_ITEMS"
	for item in "${items[@]}"; do
		IFS='|' read -r key label when <<<"$item"
		[[ -n "$when" ]] && ! "$when" && continue
		if [[ "$key" == @* ]]; then
			key="${_REVK[${key#@}]:-}"
			[[ -z "$key" ]] && continue
		fi
		seg=" ${key} ${label} "
		((plain + ${#seg} + 1 > w)) && break
		out+="${s_key} ${key} ${s_lbl} ${label} ${s_bar} "
		((plain += ${#seg} + 1))
	done
	local pad
	printf -v pad '%*s' "$((w - 1 - plain > 0 ? w - 1 - plain : 0))" ''
	_TUI_FOOTER_STR="${s_bar}${out}${pad}"$'\e[0m'
}

# overlay DRAWFN: appends to _TUI_FRAME, an ambient function layer (tui_layer.sh).
_tui_footer.draw() {
	((_TUI_FOOTER_ON)) || return 0
	local stamp="$_TUI_BIND_GEN:$_TUI_COLS:${#_TUI_PAGE_HISTORY[@]}:$_TUI_FOOTER_ITEMS:$_TUI_FOCUS_ID:$_TUI_PANE_FOCUS:$_TUI_RESIZE_PANE:$_TUI_LY_GEN"
	if [[ "$stamp" != "$_TUI_FOOTER_STAMP" ]]; then
		_TUI_FOOTER_STAMP="$stamp"
		_tui_footer.build
	fi
	# the footer row belongs to the footer alone (panes stop above it): once drawn it stays until an erase, a resize or new
	# content, so an unchanged footer adds nothing to the frame
	local painted="$_TUI_ROWS:$_TUI_FOOTER_STR"
	[[ "$painted" == "$_TUI_FTR_PAINTED" ]] && return 0
	_TUI_FTR_PAINTED="$painted"
	_tui.emit_printf '\e7\e[?7l\e[%d;1H%s\e[K\e[?7h\e8' "$_TUI_ROWS" "$_TUI_FOOTER_STR"
}
