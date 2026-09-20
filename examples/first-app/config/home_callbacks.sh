        eval "_task_tgl_$i() { on_toggle $i \"\$1\"; }"       # a checkbox action only receives the new value: one fn per task carries the index
        tui.factory.checkbox tk tasks "$i" "${t#*|}" "$([[ ${t%%|*} == 1 ]] && echo true || echo false)" "_task_tgl_$i"
#!/usr/bin/env bash
# home_callbacks.sh - the behaviour of home.xml. Only public tui.* calls.

declare -ga TASKS=()                               # the app's state: one array, one task per element: "0|text" (open) or "1|text" (done)
TASKS_FILE="$TUI_APP_CONF/tasks.txt"               # $TUI_APP_CONF = ~/.config/DABT/apps/tasks (yours to keep files in)

_tasks_save() { printf '%s\n' "${TASKS[@]}" > "$TASKS_FILE"; }

# put the array on the screen: one checkbox per task (class "task": white when open, grey + strike when done), and the counter
_tasks_show() {
    local i t done_n=0
    tui.factory.clear tk
    for i in "${!TASKS[@]}"; do
        t="${TASKS[i]}"
        eval "_task_tgl_$i() { on_toggle $i \"\$1\"; }"     # a checkbox action only receives the new value: one fn per task carries the index
        tui.factory.checkbox tk tasks "$i" "${t#*|}" "$([[ ${t%%|*} == 1 ]] && echo true || echo false)" "_task_tgl_$i"
        tui.class "$_TUI_FACTORY_LAST_ID" task
        [[ ${t%%|*} == 1 ]] && (( done_n++ ))
    done
    tui.update lbl_count "${#TASKS[@]} task(s), $done_n done"
}

tasks_visit() {                                    # runs every time the page opens (on_visit=)
    TASKS=()
    if [[ -r "$TASKS_FILE" ]]; then
        local line
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            [[ "$line" == [01]\|* ]] || line="0|$line"      # older files: plain text = open task
            TASKS+=("$line")
        done < "$TASKS_FILE"
    fi
    _tasks_show
    tui.focus inp_task
}

on_toggle() {                                      # INDEX 0|1 (from _task_tgl_N)
    TASKS[$1]="$2|${TASKS[$1]#*|}"
    _tasks_save; _tasks_show; tui.relayout
}

on_add() {                                         # button click, or Enter inside the input
    local text; text="$(tui.get inp_task)"
    if [[ -z "${text// }" ]]; then tui.notify "Type something first" warn 2; return; fi
    TASKS+=("0|$text")
    _tasks_save; _tasks_show; tui.relayout
    tui.update inp_task ""
    tui.notify "Added: $text" success 2
}

on_remove() {                                      # drop every checked task
    local t; local -a keep=()
    for t in "${TASKS[@]}"; do [[ ${t%%|*} == 1 ]] || keep+=("$t"); done
    (( ${#keep[@]} == ${#TASKS[@]} )) && { tui.notify "Check a task first" warn 2; return; }
    TASKS=("${keep[@]}")
    _tasks_save; _tasks_show; tui.relayout
}

on_clear() { (( ${#TASKS[@]} )) && tui.confirm "Delete all ${#TASKS[@]} tasks?" do_clear --danger --yes Delete --no Keep --title "Clear all"; }
do_clear() { TASKS=(); _tasks_save; _tasks_show; }
