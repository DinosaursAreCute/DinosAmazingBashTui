#!/usr/bin/env bash
# callbacks.sh - workbench benchmark app, DABT side. Behaviour contract: ../SPEC.md. Public tui.* only.

WB_DIR="${BASH_SOURCE[0]%/*}"
# The shell sources this file once; the defaults stay ${VAR:-default} so a reload of the shell keeps the state.
declare -ga WB_ROWS WB_VIEW WB_LOGS WB_LOGS_HEAD
declare -gi WB_B=${WB_B:-0} WB_T=${WB_T:-0} WB_D=${WB_D:-0} WB_CMD_ADDED=${WB_CMD_ADDED:-0}
declare -g WB_STATE=${WB_STATE:-idle} WB_THEME=${WB_THEME:-dark} WB_TAB=${WB_TAB:-General} WB_DEL_ID=${WB_DEL_ID-} WB_NOTES=${WB_NOTES-}

# ---- data (identical generator in the Textual app) ---------------------------------------------------------
wb_seed_tasks() {
	((${#WB_ROWS[@]})) && return
	local -a owners=(ada bob cy dee eli fay) states=(open done blocked) verbs=(Fix Review Ship Plan Test Draft) things=(parser cache login theme report build)
	local i
	for ((i = 1; i <= 200; i++)); do
		printf -v "WB_ROWS[${#WB_ROWS[@]}]" 'T-%04d|%s %s %d|%s|%s' "$i" "${verbs[i % 6]}" "${things[i / 6 % 6]}" "$i" "${owners[i % 6]}" "${states[i % 3]}"
	done
}

# the log lines are a static file (identical for both apps): read once, never generated
wb_load_logs() {
	((${#WB_LOGS[@]})) && return
	mapfile -t WB_LOGS <"$WB_DIR/../data/logs.txt"
	WB_LOGS_HEAD=("${WB_LOGS[@]:0:200}")
}

# ---- overview: three jobs advanced by a timer -----------------------------------------------------------------
wb_jobs_show() {
	tui.progress.set prg_build "$WB_B"
	tui.progress.set prg_test "$WB_T"
	tui.progress.set prg_deploy "$WB_D"
	tui.update lbl_jobs "Jobs: $WB_STATE"
}

wb_overview_visit() {
	if ((! WB_CMD_ADDED)); then
		tui.cmd.add wb_logs "Go to Logs" "tui.action.goto logs.xml" --desc "Open the Logs page"
		WB_CMD_ADDED=1
	fi
	wb_jobs_show
	[[ $WB_STATE == running ]] && tui.every 0.1 wb_jobs_tick
}

wb_jobs_start() {
	[[ $WB_STATE == running ]] && return
	WB_B=0 WB_T=0 WB_D=0 WB_STATE=running
	wb_jobs_show
	tui.every 0.1 wb_jobs_tick
}

wb_jobs_reset() {
	tui.every.cancel wb_jobs_tick
	WB_B=0 WB_T=0 WB_D=0 WB_STATE=idle
	wb_jobs_show
}

wb_jobs_tick() {
	((WB_B = WB_B + 10 > 100 ? 100 : WB_B + 10, WB_T = WB_T + 8 > 100 ? 100 : WB_T + 8, WB_D = WB_D + 5 > 100 ? 100 : WB_D + 5))
	if ((WB_B == 100 && WB_T == 100 && WB_D == 100)); then
		tui.every.cancel wb_jobs_tick
		WB_STATE=done
		tui.notify "All jobs finished" success
	fi
	wb_jobs_show
}

# ---- tasks: filter + select + table + detail + confirm dialog --------------------------------------------------
wb_tasks_visit() {
	wb_seed_tasks
	wb_apply_filter
}

wb_apply_filter() {
	local needle status row
	tui.get inp_filter needle
	tui.get sel_status status
	needle="${needle,,}"
	WB_VIEW=()
	for row in "${WB_ROWS[@]}"; do
		[[ $status != all && ${row##*|} != "$status" ]] && continue
		[[ -n $needle && ${row,,} != *"$needle"* ]] && continue
		WB_VIEW+=("$row")
	done
	tui.table.set tbl_tasks "ID|Title|Owner|Status" "${WB_VIEW[@]}"
	tui.update lbl_count "Rows: ${#WB_VIEW[@]}/${#WB_ROWS[@]}"
	wb_show_detail
}

wb_show_detail() {
	local row id title owner status
	tui.table.row tbl_tasks "" row
	if [[ -z $row ]]; then
		tui.update lbl_sel "Selected: -"
		tui.update lbl_title "Title: -"
		tui.update lbl_owner "Owner: -"
		tui.update lbl_status "Status: -"
		return
	fi
	IFS='|' read -r id title owner status <<<"$row"
	tui.update lbl_sel "Selected: $id"
	tui.update lbl_title "Title: $title"
	tui.update lbl_owner "Owner: $owner"
	tui.update lbl_status "Status: $status"
}

wb_delete_ask() {
	local row
	tui.table.row tbl_tasks "" row
	[[ -z $row ]] && return
	WB_DEL_ID="${row%%|*}"
	tui.confirm "Delete $WB_DEL_ID?" wb_delete_yes "" --danger
}

wb_delete_yes() {
	local i
	for i in "${!WB_ROWS[@]}"; do
		[[ ${WB_ROWS[i]} == "$WB_DEL_ID|"* ]] && unset 'WB_ROWS[i]'
	done
	WB_ROWS=("${WB_ROWS[@]}")
	wb_apply_filter
	tui.notify "Deleted $WB_DEL_ID" success
}

# ---- notes: markdown source on the left, rendered preview on the right ----------------------------------------
wb_notes_visit() {
	[[ -n ${WB_PLAIN_HEADINGS:-} ]] && tui.md.fonts off
	[[ -z $WB_NOTES ]] && WB_NOTES="$(<"$WB_DIR/../data/notes.md")"
	tui.update txt_notes "$WB_NOTES"
	wb_notes_changed
}

wb_notes_changed() {
	local text
	tui.get txt_notes text
	WB_NOTES="$text"
	local -a words=($text)
	tui.update lbl_words "Words: ${#words[@]}"
	tui.md.show preview "$text"
}

# ---- logs: a long list ------------------------------------------------------------------------------------------
wb_logs_visit() {
	wb_load_logs
	tui.list.set lst_logs "${WB_LOGS[@]}"
	tui.update lbl_lines "Lines: ${#WB_LOGS[@]}"
}

wb_logs_moved() {
	local idx
	idx="$(tui.list.selected lst_logs)"
	tui.update lbl_cursor "Line: $((idx + 1))"
}

wb_logs_append() {
	wb_load_logs
	WB_LOGS+=("${WB_LOGS_HEAD[@]}")
	tui.list.add lst_logs "${WB_LOGS_HEAD[@]}"
	tui.update lbl_lines "Lines: ${#WB_LOGS[@]}"
}

# ---- settings ---------------------------------------------------------------------------------------------------
wb_settings_visit() { :; }

wb_settings_apply() {
	local name level a b c
	tui.get inp_name name
	tui.get sel_level level
	tui.get chk_a a
	tui.get chk_b b
	tui.get chk_c c
	tui.update lbl_saved "Saved: name=${name:-anonymous} level=$level flags=$a$b$c"
	tui.notify "Settings saved" success 0 # stays until alt+k: the benchmark dismisses it between timed steps
}

# ---- admin: tabs, accordion, theme -------------------------------------------------------------------------------
wb_admin_visit() {
	tui.collapse d_disk on
	tui.collapse d_sec on
	tui.update lbl_tab "Tab: $WB_TAB"
	tui.update lbl_theme "Theme: $WB_THEME"
}

wb_tab_general() {
	WB_TAB=General
	tui.update lbl_tab "Tab: General"
}

wb_tab_appearance() {
	WB_TAB=Appearance
	tui.update lbl_tab "Tab: Appearance"
}

wb_goto_tab_general() {
	tui.focus tab_gen
	wb_tab_general
}

wb_goto_tab_appearance() {
	tui.focus tab_app
	wb_tab_appearance
}

wb_toggle_network() { tui.collapse d_net toggle; }

wb_theme_toggle() {
	if [[ $WB_THEME == dark ]]; then
		WB_THEME=light
		tui.theme.set "$WB_DIR/look_light.css"
	else
		WB_THEME=dark
		tui.theme.clear
	fi
}
