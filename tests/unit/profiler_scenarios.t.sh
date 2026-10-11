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

ti_profiler_compose_scenario_exists_and_probes_the_refresh() {
	command -v python3 >/dev/null || return 0
	local out
	out="$(cd "$REPO/tools/profiler" && python3 -c '
from dprof import scenarios as sc, session
names = [n for n, _, _ in sc.SCENARIOS]
need = {"compose"} - set(names)
probes = {n for n, _ in session.WRAP}
need |= {"tui.page.refresh", "_tui_job.finish"} - probes
print(" ".join(sorted(need)))')"
	eq "" "$out"
}

ti_profiler_compose_groups_have_the_page_switch_budget() {
	command -v python3 >/dev/null || return 0
	local out
	out="$(cd "$REPO/tools/profiler" && python3 -c '
from dprof import scenarios as sc
bad = [g for g in ("compose.add", "compose.tab", "compose.cond", "compose.addons") if sc.GROUP_INFO[g][2] != 100]
print(" ".join(bad))')"
	eq "" "$out" # a refresh is allowed what a page switch is allowed: 100 ms
}

ti_profiler_locate_matches_whole_words_so_default_is_not_defaults() {
	command -v python3 >/dev/null || return 0
	local out
	out="$(cd "$REPO/tools/profiler" && python3 -c '
from dprof.session import Session
class S(Session):
    def __init__(self, raw): self.raw = bytearray(raw)
page = b"\x1b[3;1H  default\x1b[18;1H[ Reset to defaults ]"
print(S(page).locate("default"), S(b"\x1b[18;1H[ Reset to defaults ]").locate("default"), S(page).locate("[ Reset"))')"
	eq "(3, 3) None (1, 18)" "$out" # the Reset button must never answer for the theme button
}

ti_profiler_failed_steps_become_warnings_and_a_failed_group_is_never_rated_good() {
	command -v python3 >/dev/null || return 0
	local out
	out="$(cd "$REPO/tools/profiler" && python3 -c '
from dprof import analyze, runner, scenarios as sc
class UI:
    def warn(self, m): pass
w = []
step = sc.Step("compose.add", "new task", "click_text", "[ Add task")
runner._failed(step, {"ok": False, "note": "x not on screen"}, w, UI())
runner._failed(step, {"ok": False, "note": "x not on screen"}, w, UI())
runner._failed(step, {"ok": True}, w, UI())
act = {"group": "compose.add", "detail": "d", "ok": False, "note": "x not on screen", "settle_ms": 5.0, "paint_ms": 5.0, "busy_ms": 5.0}
g = [x for x in analyze.latency_groups([{"startup": {}, "actions": [act]}]) if x["id"] == "compose.add"][0]
su = analyze.setup_view([{"setup": [{"unit": "u", "steps": [{"detail": "start", "ms": 300.0, "ok": True}, {"detail": "Settings", "ms": 100.0, "ok": True}]}]}])[0]
print(len(w), g["rating"], g["failed"], su["total_ms"], su["start_ms"])')"
	eq "1 slow 1 400.0 300.0" "$out" # one warning per distinct failure; a failed group is red, not "good"
}

ti_profiler_compose_open_must_land_on_the_page() {
	command -v python3 >/dev/null || return 0
	local out
	out="$(cd "$REPO/tools/profiler" && python3 -c '
from dprof import scenarios as sc
st = sc.interaction_steps(45, 150, False, {"compose.open"})
print([s.expect for s in st if s.group == "compose.open"][0])')"
	eq "[ Add task" "$out" # a palette Enter that closed a dialog instead of opening the page is a failure
}

ti_profiler_units_are_independent_setup_then_measure_blocks() {
	command -v python3 >/dev/null || return 0
	local out
	out="$(
		cd "$REPO/tools/profiler" && python3 - <<'PY'
from dprof import scenarios as sc
bad, seen = [], {}
for u in sc.units(45, 150, False, None):
    for g in u.groups:
        if g in seen:
            bad.append(f"{g} is in {seen[g]} and {u.name}")
        seen[g] = u.name
    for s in u.steps:   # a unit reports only its own groups; everything else is setup
        if s.group != "setup" and s.group not in u.groups:
            bad.append(f"{u.name} reports {s.group}")
    if u.steps and u.steps[0].detail == sc.DEFAULT_PAGE and u.steps[0].group == "setup":   # no navigating to where it already is
        bad.append(f"{u.name}: first step goes to the default page")
    if not u.steps or u.steps[-1].group == "setup":   # it starts on the default page and ends on a measured step
        bad.append(f"{u.name}: empty or ends on a setup step")
missing = set(sc.GROUP_INFO) - set(seen) - {"startup.cold", "startup.warm"}
bad += [f"no unit for {g}" for g in sorted(missing)]
bad.append(",".join(u.name for u in sc.units(45, 150, True, {"palette.open", "compose.add"})))
print("\n".join(bad))
PY
	)"
	eq "palette,compose" "$out" # every group in exactly one unit; --scenario picks whole units only
}

ti_profiler_machine_info_has_specs_only_and_the_sampler_reports_load() {
	command -v python3 >/dev/null || return 0
	local out
	out="$(cd "$REPO/tools/profiler" && python3 -c '
import getpass, json, os, socket, time
from dprof import sysinfo
m = sysinfo.machine(45, 150)
blob = json.dumps(m)
bad = [w for w in {socket.gethostname(), getpass.getuser(), os.path.expanduser("~"), os.getcwd()} if w and len(w) > 2 and w in blob]
bad += ["missing:" + k for k in ("cpu_model", "logical_cpus", "ram_gb", "kernel", "id") if not m.get(k)]
s = sysinfo.Sampler(0.04).start(); t0 = time.time(); time.sleep(0.15); s.stop()
r = s.summary(t0, time.time(), app_cpu_s=0.0, app_rss_kb=2048)
bad += [k for k in ("sys_cpu_pct_mean", "other_cores") if k not in r]
print(" ".join(bad))')"
	eq "" "$out" # no host name, user name or path in the machine record
}

ti_profiler_explorer_data_is_generated_for_every_run_without_manual_steps() {
	command -v python3 >/dev/null || return 0
	local out d
	d="$(mktemp -d)"
	mkdir -p "$d/20260101-010101" "$d/20260102-020202"
	echo '{"meta":{"when":"x","commit":"abc","scenario":"full"},"latency":[{"id":"nav.first","value":12.5,"rating":"good","n":3,"budget_ms":150}],"startup":{"warm":{"ready_ms":300}},"insights":[{"sev":"crit"}]}' >"$d/20260101-010101/report.json"
	echo '{"meta":{"when":"y"},"latency":[]}' >"$d/20260102-020202/report.json"
	ln -s 20260102-020202 "$d/latest"
	out="$(cd "$REPO/tools/profiler" && python3 -c '
import json, os, sys
import explore
d = sys.argv[1]
n = explore.update(d)
idx = json.loads(open(d + "/index.js").read().split("=", 1)[1].rstrip(";\n"))
js = open(d + "/20260101-010101/report.js").read()
print(n, [r["id"] for r in idx], idx[0]["groups"]["nav.first"][0], idx[0]["startup"]["warm"], idx[0]["insights"], js.startswith("DPROF.run(\"20260101-010101\","),
      all(os.path.exists(os.path.join("explorer", f)) for f in ("index.html", "app.js", "lib.js", "app.css")))' "$d")"
	rm -rf "$d"
	eq '2 [\x2720260101-010101\x27, \x2720260102-020202\x27] 12.5 300 {\x27crit\x27: 1} True True' "$(printf '%s' "$out" | sed "s/'/\\\\x27/g")" # `latest` is skipped; new runs need no manual step
}

ti_profiler_flags_noisy_runs_and_the_html_report_script_parses() {
	command -v python3 >/dev/null || return 0
	local out
	out="$(
		cd "$REPO/tools/profiler" && python3 - <<'PY'
import json, re, subprocess, tempfile
from dprof import analyze, report_html, report_term
bad = []
res = [{"unit": "a", "jobs": 1, "other_cores": 0.2}, {"unit": "b", "jobs": 1, "other_cores": 1.4}, {"unit": "c", "jobs": 4, "other_cores": 9.0}]
if analyze.noise(res) != 1.4:
    bad.append("noise: single-job units only, the maximum")
if analyze.noise([]) is not None or analyze.noise([{"jobs": 4, "other_cores": 3}]) is not None:
    bad.append("noise: unknown without a single-job unit")
rep = {"latency": [{"id": "nav.first", "title": "T", "value": 20.0}], "resources": res}
base = {"latency": [{"id": "nav.first", "value": 10.0}], "resources": [{"unit": "a", "jobs": 1, "other_cores": 0.1}], "meta": {}}
cmp_ = analyze.compare(rep, base)
if (cmp_["new_noise"], cmp_["old_noise"]) != (1.4, 0.1):
    bad.append("compare: noise of both runs")
if "inflated" not in "\n".join(report_term.compare_block({"compare": cmp_}, 100)):
    bad.append("terminal compare: no warning for the noisy run")
src = report_html.TEMPLATE.replace("__DATA__", "{}")   # the page's script is static: a duplicate declaration blanks the whole report
js = re.findall(r"<script[^>]*>([\s\S]*?)</script>", src)[-1]
if subprocess.run(["bash", "-c", "command -v node >/dev/null"]).returncode == 0:
    with tempfile.NamedTemporaryFile("w", suffix=".js") as f:
        f.write(js); f.flush()
        if subprocess.run(["node", "--check", f.name], capture_output=True).returncode:
            bad.append("html report script has a syntax error")
print(" ".join(bad))
PY
	)"
	eq "" "$out"
}
