# profiler_scenarios.t.sh - the profiler's scenario list (tools/profiler/dprof/scenarios.py) stays consistent.
# Only reads the definitions with python3; it starts no app and measures nothing (that is tools/profiler/profile.sh).

ti_profiler_every_scenario_group_has_a_title_and_a_budget_and_steps() {
	command -v python3 >/dev/null || return 0
	local out
	out="$(
		cd "$REPO/tools/profiler" && python3 - <<'PY'
from dprof import scenarios as sc
bad = []
for name, _, groups in sc.SCENARIOS:
    if groups is None:
        continue
    for g in groups:
        if g not in sc.GROUP_INFO:
            bad.append(f"{name}: group {g} has no GROUP_INFO")
    names, wanted = sc.resolve_scenarios(name)
    steps = sc.interaction_steps(45, 150, False, wanted)
    reported = {s.group for s in steps}
    if not name.startswith("startup"):
        for g in groups:
            if g not in reported:
                bad.append(f"{name}: no step reports group {g}")
print("\\n".join(bad))
PY
	)"
	eq "" "$out"
}

ti_profiler_addon_and_generated_scenarios_exist_and_probe_the_refresh() {
	command -v python3 >/dev/null || return 0
	local out
	out="$(cd "$REPO/tools/profiler" && python3 -c '
from dprof import scenarios as sc, session
names = [n for n, _, _ in sc.SCENARIOS]
need = {"addons", "generated"} - set(names)
probes = {n for n, _ in session.WRAP}
need |= {"tui.page.refresh", "_tui_job.finish"} - probes
print(" ".join(sorted(need)))')"
	eq "" "$out"
}

ti_profiler_apply_groups_have_the_page_switch_budget() {
	command -v python3 >/dev/null || return 0
	local out
	out="$(cd "$REPO/tools/profiler" && python3 -c '
from dprof import scenarios as sc
bad = [g for g in ("addons.apply1", "addons.apply5", "generate.small", "generate.big") if sc.GROUP_INFO[g][2] != 100]
print(" ".join(bad))')"
	eq "" "$out" # an addon is allowed what a page switch is allowed: 100 ms
}
