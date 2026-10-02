#!/usr/bin/env bash
# home_callbacks.sh - the behaviour of home.xml. Only public tui.* calls.

declare -ga TASKS=()                 # the app's state: one array, one task per element
TASKS_FILE="$TUI_APP_CONF/tasks.txt" # $TUI_APP_CONF = ~/.config/DABT/apps/tasks (yours to keep files in)

_tasks_save() { printf '%s\n' "${TASKS[@]}" >"$TASKS_FILE"; }

# put the array on the screen: the list widget and the counter
_tasks_show() {
	if ((${#TASKS[@]})); then tui.list.set lst_tasks "${TASKS[@]}"; else tui.list.clear lst_tasks; fi
	tui.update lbl_count "${#TASKS[@]} task(s)"
}

tasks_visit() { # runs every time the page opens (on_visit=)
	TASKS=()
	[[ -r "$TASKS_FILE" ]] && mapfile -t TASKS <"$TASKS_FILE"
	_tasks_show
	tui.focus inp_task
}

on_add() { # [ Add ] clicked, or Enter pressed in the field
	local text
	tui.get inp_task text # into a variable: no subshell
	if [[ -z "${text// /}" ]]; then
		tui.notify "Type something first" warn 2
		return
	fi
	TASKS+=("$text")
	_tasks_save
	_tasks_show
	tui.update inp_task ""
	tui.notify "Added: $text" success 2
}

on_remove() {
	local i
	tui.list.selected lst_tasks i # -1 = nothing selected
	((i >= 0)) || {
		tui.notify "Select a task first" warn 2
		return
	}
	unset 'TASKS[i]'
	TASKS=("${TASKS[@]}") # close the gap in the array
	_tasks_save
	_tasks_show
}

on_clear() { # ask first: a confirmation dialog
	((${#TASKS[@]})) && tui.confirm "Delete all ${#TASKS[@]} tasks?" do_clear --danger --yes Delete --no Keep --title "Clear all"
}
do_clear() { # called only if the user chose "Delete"
	TASKS=()
	_tasks_save
	_tasks_show
}
