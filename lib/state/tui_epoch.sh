#!/usr/bin/env bash
# tui_epoch.sh - the one way to say "cached state may be stale". Modules call this; they never write another module's
# generation counter or dirty flag. Each KIND names what changed, and the caches that depend on it are listed in
# docs/design/caches.md.
#
#   _tui.epoch_bump KIND...    layout   a pane's rect or the split/gap/pad/min/max math changed -> layout memo (_TUI_LY_GEN)
#                              style    a style table was written or replaced                 -> saved base frame (_TUI_RC_EPOCH)
#                              widgets  the widget list or a widget's type changed            -> focus order and hit index
#                              hit      only the zones changed (scroll, collapse, resize)     -> hit index
#                              focus    only the focus order changed                          -> focus order
#
# Content-addressed caches (rowcache, the SGR / width / slice memos) are not here: their key holds every input, so a
# changed input is a different key and nothing is ever stale. With TUI_CACHES=off every cache is bypassed
# (see docs/design/caches.md), which is how a missing bump shows up as a difference between the two modes.
# requires:

# TUI_CACHES=off (environment) bypasses every cache that can go stale: the layout memo, the widget position cache, the
# row-fragment cache, the paint diff, the hit index, the focus order, the saved base frame, the page cache and the theme
# memo. The two modes must behave the same; a difference is a cache boundary bug (docs/design/caches.md).
declare -gi _TUI_CACHES=1
case "${TUI_CACHES:-on}" in off | 0 | false | no) _TUI_CACHES=0 ;; esac

_tui.epoch_bump() {
	local kind
	for kind in "$@"; do
		case "$kind" in
			layout) : $((_TUI_LY_GEN++)) ;;
			style) : $((_TUI_RC_EPOCH++)) ;;
			widgets) _TUI_FOCUS_DIRTY=1 _TUI_HZ_DIRTY=1 ;;
			hit) _TUI_HZ_DIRTY=1 ;;
			focus) _TUI_FOCUS_DIRTY=1 ;;
			*)
				echo "_tui.epoch_bump: unknown kind '$kind'" >&2
				return 1
				;;
		esac
	done
	return 0
}
