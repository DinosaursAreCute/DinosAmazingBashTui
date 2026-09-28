#!/usr/bin/env bash
# chrome_dialog.t.sh - lib/chrome/tui_dialog.sh buffer-mode dialog/toast draw paths (stage 0.3).

t_dialog_draw_appends_to_frame_when_active() {
	_TUI_MODAL="dialog"
	_DLG_KIND="confirm"
	_DLG_TITLE="Confirm"
	_DLG_MSG="Are you sure?"
	_DLG_WIDTH=0
	_DLG_DANGER=0
	_DLG_BTN=("Yes" "No")
	_DLG_SEL=0
	_DLG_SGR_BOX="" _DLG_SGR_TITLE="" _DLG_SGR_BTN="" _DLG_SGR_SEL="" _DLG_SGR_DANGER="" _DLG_SGR_DIM="" _DLG_SGR_ERR=""
	_TUI_COLS=80
	_TUI_ROWS=24
	_TUI_FRAME="prefix:"
	_tui_dialog.draw
	ok '[[ "$_TUI_FRAME" == prefix:$'"'"'\e7'"'"'* ]]'
	ok '[[ "$_TUI_FRAME" == *"Confirm"* ]]'
	ok '[[ "$_TUI_FRAME" == *"Yes"* ]]'
	_TUI_MODAL=""
}

t_dialog_draw_appends_nothing_when_not_active() {
	_TUI_MODAL=""
	_TUI_FRAME="prefix:"
	_tui_dialog.draw
	eq "prefix:" "$_TUI_FRAME"
}

t_dialog_draw_view_appends_to_frame() {
	_TUI_MODAL="dialog"
	_DLG_KIND="view"
	_DLG_TITLE="Help"
	_DLG_WIDTH=0
	_DLG_ITEMS=("line one" "line two")
	_DLG_TOP=0
	_DLG_SGR_BOX="" _DLG_SGR_TITLE="" _DLG_SGR_DIM=""
	_TUI_COLS=80
	_TUI_ROWS=24
	_TUI_FRAME="prefix:"
	_tui_dialog.draw
	ok '[[ "$_TUI_FRAME" == prefix:$'"'"'\e7'"'"'* ]]'
	ok '[[ "$_TUI_FRAME" == *"Help"* ]]'
	ok '[[ "$_TUI_FRAME" == *"line one"* ]]'
	_TUI_MODAL=""
}

t_toast_draw_appends_to_frame_when_toasts_exist() {
	_TST_ID=(1)
	_TST_MSG=("saved")
	_TST_LVL=("success")
	_TST_EXP=(0)
	_TST_SGR_INFO="" _TST_SGR_SUCCESS="" _TST_SGR_WARN="" _TST_SGR_ERROR=""
	TUI_TOAST_WIDTH=46
	TUI_TOAST_POSITION="bottom-right"
	_TUI_COLS=80
	_TUI_ROWS=24
	_TUI_FOOTER_ON=0
	_TUI_FRAME="prefix:"
	_tui_dialog.toast_draw
	ok '[[ "$_TUI_FRAME" == prefix:*"saved"* ]]'
	ok '[[ "$_TUI_FRAME" == *$'"'"'\e[0m\e8'"'"' ]]'
	_TST_ID=()
}

t_toast_draw_appends_nothing_when_no_toasts() {
	_TST_ID=()
	_TUI_FRAME="prefix:"
	_tui_dialog.toast_draw
	eq "prefix:" "$_TUI_FRAME"
}
