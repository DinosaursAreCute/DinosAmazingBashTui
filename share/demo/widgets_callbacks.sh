#!/usr/bin/env bash
# widgets_callbacks.sh - Widgets page: every richer widget in use (textarea, password, select, progress, list, table).
# Only public tui.* calls.

_WX_INTRO='Welcome to the text editor.

Try it:
  click to place the cursor
  drag to select
  double-click: a word
  triple-click: a line
  shift+arrows: select
  ctrl+arrows: jump by word
  ctrl+a: select all
  ctrl+x / ctrl+insert / ctrl+v:
      cut / copy / paste
  alt+z / alt+y: undo / redo
  ctrl+k: kill to end of line

Soon: a Markdown mode.'

wx_visit() {
	tui.set wx_text "$_WX_INTRO"
	tui.text.set_cursor wx_text 0
	tui.every 0.3 wx_status_tick wx_status_job
	wx_status_tick
	tui.focus wx_text
}

# the status line under the editor: position, selection, size (polled: moving the cursor is not an edit)
wx_status_tick() {
	local id
	id="$(tui.get.focused)"
	[[ "$id" == wx_text ]] || {
		tui.update wx_stat1 "click into the notes to edit"
		return 0
	}
	local pos sel len
	pos="$(tui.text.cursor wx_text)"
	sel="$(tui.text.selection wx_text)"
	len="$(tui.get wx_text)"
	tui.update wx_stat1 "Ln ${pos% *}, Col ${pos#* }   selected ${#sel}   ${#len} chars   $(tui.text.line_count wx_text) lines"
}
wx_text_changed() { :; }

wx_login() {
	local u p
	u="$(tui.get wx_user)"
	p="$(tui.get wx_pass)"
	if [[ -z "$u" || -z "$p" ]]; then
		tui.notify "Enter a user and a password" warn
		return
	fi
	if [[ "$p" == "secret" ]]; then
		tui.notify "Welcome, $u" success
		tui.set wx_pass ""
		tui.update wx_pass ""
	else tui.notify "Wrong password for $u (hint: secret)" error 6; fi
}
wx_mode_picked() { tui.notify "Mode: $(tui.get wx_mode)" info 2; }

wx_run_job() {
	tui.progress.set wx_prog 0
	tui.every 0.1 wx_job_step wx_job_timer
}
wx_job_step() {
	local v
	v="$(tui.get wx_prog)"
	((v += 4))
	tui.progress.set wx_prog "$v"
	((v >= 100)) && {
		tui.every.cancel wx_job_timer
		tui.notify "Job finished" success
	}
}

wx_list_open() { tui.notify "Open: $(tui.list.item wx_list)" info 2; }
wx_list_moved() { :; }
wx_table_open() { tui.notify "Row: $(tui.table.row wx_table)" info 3; }
