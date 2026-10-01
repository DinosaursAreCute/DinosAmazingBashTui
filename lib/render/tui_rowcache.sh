#!/usr/bin/env bash
# tui_rowcache.sh - content-addressed cache of composed frame fragments.
# A fragment (the bytes a pane or simple widget appends to _TUI_FRAME) is
# keyed on every input that produces it: geometry, state, resolved content
# and _TUI_STYLE_EPOCH. A changed input is a different key, so staleness is
# detected by construction and nothing is registered or invalidated per
# widget. Callers skip the cache when an input is not a plain value
# (a ${expr} text), so dynamic content always recomposes.
#
# Fork-free: parameter expansion and one associative array.

declare -gA _TUI_RC=()
declare -gi _TUI_RC_N=0
declare -gi _TUI_STYLE_EPOCH=0 # bumped by every style write; part of every key
declare -gi _TUI_ROWCACHE="${TUI_ROWCACHE:-1}"
declare -gi _TUI_RC_MAX=4096 # bounded like _TUI_SGR_MEMO: a gradient or chart must not grow it without limit

# _tui_rowcache.replay KEY - appends the cached fragment to _TUI_FRAME; rc 1 on a miss.
_tui_rowcache.replay() {
	if ((_TUI_ROWCACHE)) && [[ -n "${_TUI_RC[$1]+x}" ]]; then
		_TUI_FRAME+="${_TUI_RC[$1]}"
		_tui_perf.count rowcache_hit
		return 0
	fi
	_tui_perf.count rowcache_miss
	return 1
}

# _tui_rowcache.store KEY FROM - caches _TUI_FRAME from offset FROM (the length before the draw) onward.
_tui_rowcache.store() {
	((_TUI_ROWCACHE)) || return 0
	if ((_TUI_RC_N >= _TUI_RC_MAX)); then _TUI_RC=() _TUI_RC_N=0; fi
	[[ -z "${_TUI_RC[$1]+x}" ]] && _TUI_RC_N+=1
	_TUI_RC[$1]="${_TUI_FRAME:$2}"
}

_tui_rowcache.reset() {
	_TUI_RC=()
	_TUI_RC_N=0
}
