#!/usr/bin/env bash
# perflab_callbacks.sh - callbacks of the perflab fixture pages. The size of a page comes from the environment of the
# unit (PERFLAB_N, PERFLAB_COLS), so one page serves every rung of a sweep. Everything is deterministic: no clock, no
# random data.

perflab_noop() { :; }

# The start page's button: open the page this unit is about. Generated pages (one per rung) are in PERFLAB_GEN,
# the frozen ones next to the start page.
perflab_open() {
	local f="${PERFLAB_GEN:-}/${PERFLAB_PAGE:-}"
	[[ -n "${PERFLAB_PAGE:-}" && -f "$f" ]] || f="$PERFLAB_PAGES/${PERFLAB_PAGE:?PERFLAB_PAGE is not set}"
	tui.goto "$f"
}

# N listeners on every frame: each its own function, because tui.tick.add ignores a name it already has.
perflab_ticks_visit() {
	local i n="${PERFLAB_N:-3}"
	PERFLAB_TICKS=0
	for ((i = 1; i <= n; i++)); do
		eval "perflab_tick_$i() { PERFLAB_TICKS=\$((PERFLAB_TICKS + 1)); }"
		tui.tick.add "perflab_tick_$i"
	done
}

# N tui.every jobs, one second apart, all running the same function under their own ids.
perflab_every_visit() {
	local i n="${PERFLAB_N:-3}"
	for ((i = 1; i <= n; i++)); do
		tui.every 1 perflab_noop "perflab_job_$i"
	done
}

# N handlers on the key event; none consumes the key, so every handler runs for every key.
perflab_hooks_visit() {
	local i n="${PERFLAB_N:-2}"
	for ((i = 1; i <= n; i++)); do
		eval "perflab_hook_$i() { return 1; }"
		tui.hook.on key "perflab_hook_$i"
	done
}

# A table of PERFLAB_N rows and PERFLAB_COLS columns.
perflab_table_visit() {
	local n="${PERFLAB_N:-100}" c="${PERFLAB_COLS:-6}" i j row hdr=""
	local -a rows=()
	for ((j = 1; j <= c; j++)); do hdr+="${hdr:+|}col$j"; done
	for ((i = 1; i <= n; i++)); do
		row="r$i"
		for ((j = 2; j <= c; j++)); do row+="|v$i.$j"; done
		rows+=("$row")
	done
	tui.table.set perflab_table "$hdr" "${rows[@]}"
}

# A textarea of PERFLAB_N lines.
perflab_textarea_visit() {
	local n="${PERFLAB_N:-50}" i text
	local -a lines=()
	for ((i = 1; i <= n; i++)); do lines+=("line $i: the quick brown fox jumps over the lazy dog"); done
	printf -v text '%s\n' "${lines[@]}"
	tui.set perflab_ta "${text%$'\n'}"
}

# A single-line input holding PERFLAB_N characters.
perflab_input_visit() {
	local n="${PERFLAB_N:-80}" s
	printf -v s '%*s' "$n" ''
	tui.set perflab_in "${s// /x}"
}

# PERFLAB_N commands in the palette's registry.
perflab_palette_visit() {
	local i n="${PERFLAB_N:-20}"
	for ((i = 1; i <= n; i++)); do
		tui.cmd.add "perflab_c$i" "Perflab command $i" perflab_noop
	done
}

perflab_back() { tui.goto "$PERFLAB_PAGES/start.xml"; }
