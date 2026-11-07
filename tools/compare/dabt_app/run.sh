#!/usr/bin/env bash
# run.sh - launches the DABT side of the comparison (4 pages). Same file set as tools/compare/textual_app.
# --themed: runs a copy of the pages in $HOME/themed_app where every pane carries class="panel" and every page loads
# theme.css (a plain dark background, like Textual's default). The checked-in pages never reference a theme.
TUI_APP_NAME=compare_dabt
TUI_APP_TITLE="DABT comparison app"
HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HERE"
if [[ ${1:-} == --themed ]]; then
	APP="$HOME/themed_app"
	mkdir -p "$APP"
	# A file is only rewritten when its content changed: a rewrite bumps the mtime, which invalidates the page cache
	# (it validates by mtime), so the "warm" start would rebuild every page.
	for f in theme.css callbacks.sh; do
		cmp -s "$HERE/$f" "$APP/$f" || cp "$HERE/$f" "$APP/$f"
	done
	for f in "$HERE"/*.xml; do
		new=$(sed -e 's|<pane |<pane class="panel" |' -e 's|\(<script src="callbacks.sh"/>\)|\1\n  <theme src="theme.css"/>|' \
			-e 's|xsi:noNamespaceSchemaLocation="[^"]*"||' "$f")
		[[ -f $APP/${f##*/} && $new == "$(<"$APP/${f##*/}")" ]] || printf '%s\n' "$new" >"$APP/${f##*/}"
	done
fi
# shellcheck source=../../../lib/tui.sh
source "$HERE/../../../lib/tui.sh"
tui.start_cached "$APP/buttons.xml"
