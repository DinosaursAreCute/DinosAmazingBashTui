#!/usr/bin/env bash
# callbacks.sh - comparison app: the same behaviour as tools/compare/textual_app, public tui.* only.

declare -gi CMP_CLICKS=${CMP_CLICKS:-0} CMP_PROGRESS=${CMP_PROGRESS:-0}

cmp_show_clicks() { tui.update lbl_clicks "Clicks: $CMP_CLICKS"; }
cmp_inc() {
	((CMP_CLICKS++))
	cmp_show_clicks
}
cmp_dec() {
	((CMP_CLICKS--))
	cmp_show_clicks
}
cmp_reset() {
	CMP_CLICKS=0
	cmp_show_clicks
}

cmp_submit() {
	local name news dark
	name="$(tui.get inp_name)"
	news="$(tui.get chk_news)"
	dark="$(tui.get chk_dark)"
	tui.update lbl_status "Hello, ${name:-stranger}! news=$news dark=$dark"
}

cmp_list_moved() { tui.update lbl_sel "Selected: $(tui.list.item lst_items)"; }

cmp_advance() {
	((CMP_PROGRESS = CMP_PROGRESS >= 100 ? 0 : CMP_PROGRESS + 10))
	tui.progress.set prg "$CMP_PROGRESS"
	tui.update lbl_stat "Progress: ${CMP_PROGRESS}%"
}
