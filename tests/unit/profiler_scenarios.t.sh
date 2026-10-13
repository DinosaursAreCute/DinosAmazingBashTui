# profiler_scenarios.t.sh - the profiler's scenario list (tools/profiler/scenarios/demo.py, loaded by tools/profiler/dprof/scenarios.py) stays consistent.
# Only reads the definitions with python3; it starts no app and measures nothing (that is tools/profiler/profile.sh).

ti_profiler_every_scenario_group_has_a_title_and_a_budget_and_steps() {
	command -v python3 >/dev/null || return 0
	local out
	out="$(
		cd "$REPO/tools/profiler" && python3 - <<'PY'
from dprof import scenarios as sc
sc.load()
bad = []
for name, _, groups in sc.SCENARIOS:
    if groups is None:
        continue
    for g in groups:
        if g not in sc.GROUP_INFO:
            bad.append(f"{name}: group {g} has no GROUP_INFO")
    names, wanted = sc.resolve_scenarios(name)
    steps = sc.steps(45, 150, False, wanted)
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
sc.load()
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
sc.load()
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
sc.load()
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
sc.load()
st = sc.steps(45, 150, False, {"compose.open"})
print([s.expect for s in st if s.group == "compose.open"][0])')"
	eq "[ Add task" "$out" # a palette Enter that closed a dialog instead of opening the page is a failure
}

ti_profiler_units_are_independent_setup_then_measure_blocks() {
	command -v python3 >/dev/null || return 0
	local out
	out="$(
		cd "$REPO/tools/profiler" && python3 - <<'PY'
from dprof import scenarios as sc
sc.load()
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

ti_profiler_a_scenario_file_replaces_the_groups_the_units_and_the_app_defaults() {
	command -v python3 >/dev/null || return 0
	local out d
	d="$(mktemp -d)"
	cat >"$d/other.py" <<'PY'
from dprof.scenarios import Step, setup
APP = "bin/other.sh"
ENV = {"OTHER": "1"}
SIZE = "100x30"
GROUP_INFO = {"x.open": ("Open X", "nav", 80), "x.idle": ("Idle", "idle", 0)}
SCENARIOS = [("all", "everything", None), ("open", "just open", {"x.open"})]
UNIT_GROUPS = [("x", ["x.open"]), ("idle", ["x.idle"])]
def steps(rows, cols, quick=False, wanted=None):
    want = (lambda *g: True) if wanted is None else (lambda *g: any(x in wanted for x in g))
    S = [setup("Start")]
    if want("x.open"): S.append(Step("x.open", "click", "click_text", "X"))
    if want("x.idle"): S.append(Step("x.idle", "1 s", "idle", 1.0))
    return S
PY
	out="$(cd "$REPO/tools/profiler" && python3 -c '
import sys
from dprof import scenarios as sc
sc.load()
n_demo = len(sc.GROUP_INFO)
sc.load(sys.argv[1])
names, wanted = sc.resolve_scenarios("open")
u = sc.units(30, 100, False, wanted)
print(n_demo > 20, sorted(sc.GROUP_INFO), names, sorted(wanted), [x.name for x in u], [s.group for s in u[0].steps],
      sc.DEFAULTS["app"], sc.DEFAULTS["size"], sc.ENV, sc.FOCUS_ROOTS, sc.SOURCE["name"])' "$d/other.py")"
	rm -rf "$d"
	eq "True ['x.idle', 'x.open'] ['open'] ['x.open'] ['x'] ['setup', 'x.open'] bin/other.sh 100x30 {'OTHER': '1'} [] other" "$out" # nothing of the demo file survives a load
}

ti_profiler_a_scenario_file_with_missing_or_inconsistent_tables_is_refused_with_the_reason() {
	command -v python3 >/dev/null || return 0
	local out d
	d="$(mktemp -d)"
	printf 'GROUP_INFO = {}\n' >"$d/missing.py"
	printf 'from dprof.scenarios import Step\nGROUP_INFO = {"a": ("A", "nav", 1)}\nSCENARIOS = [("s", "d", {"b"})]\nUNIT_GROUPS = [("u", ["a"]), ("v", ["a"])]\ndef steps(r, c, q=False, w=None): return []\n' >"$d/bad.py"
	out="$(cd "$REPO/tools/profiler" && python3 -c '
import sys
from dprof import scenarios as sc
for f in sys.argv[1:]:
    try:
        sc.load(f)
    except sc.ScenarioFileError as e:
        print(str(e).replace(f + ": ", ""))' "$d/missing.py" "$d/bad.py" "$d/none.py" 2>&1 | head -5)"
	rm -rf "$d"
	eq "missing SCENARIOS, UNIT_GROUPS, steps (see the docstring of scenarios/demo.py)
scenario s: group b is not in GROUP_INFO; group a is in units u and v
scenario file '$d/none.py' not found (looked for it as a path and in $REPO/tools/profiler/scenarios)" "$out"
}

ti_profiler_an_app_that_does_not_source_the_library_the_expected_way_is_an_error_not_an_unprobed_run() {
	command -v python3 >/dev/null || return 0
	local out d
	d="$(mktemp -d)"
	printf '#!/usr/bin/env bash\nsource "$HOME/lib/tui.sh"\n' >"$d/app.sh"
	out="$(cd "$REPO/tools/profiler" && python3 -c '
import sys
from dprof import scenarios as sc
sc.load()
from dprof.session import Session
try:
    Session("/tmp", 45, 150, app=sys.argv[1])._write_app_copy()
    print("no error")
except RuntimeError as e:
    print("probes" in str(e) and "SHIM_PATTERN" in str(e))' "$d/app.sh" 2>&1 | tail -1)"
	rm -rf "$d"
	eq "True" "$out"
}

ti_profiler_perflab_scenario_file_is_consistent_and_every_rung_is_a_unit_with_its_own_size() {
	command -v python3 >/dev/null || return 0
	local out
	out="$(cd "$REPO/tools/profiler" && python3 -c '
from dprof import scenarios as sc
sc.load("perflab")
bad = []
for u in sc.units(45, 150, False, None):
    p = sc.parse_group(sorted(u.groups)[0])
    if not u.env.get("PERFLAB_PAGE") or not u.env.get("PERFLAB_N"):
        bad.append(u.name + ": no page or size in its environment")
    if u.steps[0].group != "setup" or all(s.group == "setup" for s in u.steps):
        bad.append(u.name + ": no setup start or nothing measured")
    for s in u.steps:
        if s.group != "setup" and s.group not in u.groups:
            bad.append(u.name + " reports " + s.group)
full = dict((n, g) for n, _, g in sc.SCENARIOS)
if not full["full"] < set(sc.GROUP_INFO):
    bad.append("full must be the ends of the ladders, not every rung")
if not sc.SWEEP or any(n in sc.SWEEP for n in ("full", "table")):
    bad.append("sweep scenarios are exactly the sweep-* ones")
print("\n".join(bad))')"
	eq "" "$out"
}

ti_profiler_ladders_take_set_overrides_and_scale_and_sweeps_default_to_latency_only() {
	command -v python3 >/dev/null || return 0
	local out
	out="$(cd "$REPO/tools/profiler" && python3 -c '
from dprof import scenarios as sc
sc.set_options(["table.rows=7,70", "scale=0.5"])
sc.load("perflab")
rows = sorted(g for g in sc.GROUP_INFO if g.startswith("table.rows.") and g.endswith(".open"))
ticks = sorted(int(g.split(".")[2]) for g in sc.GROUP_INFO if g.startswith("ticks.listeners.") and g.endswith(".open"))
print(rows, ticks, sc.parse_group("table.rows.7.open"), sc.parse_group("nav.first"))')"
	eq "['table.rows.7.open', 'table.rows.70.open'] [2, 15, 150, 1500] ('table', 'rows', 7, 'open') None" "$out" # --set replaces an axis; scale multiplies the others (the floor is 1)
}

ti_profiler_limits_name_the_largest_n_inside_the_budget_the_first_over_and_the_rung_that_never_ran() {
	command -v python3 >/dev/null || return 0
	local out
	out="$(cd "$REPO/tools/profiler" && python3 -c '
from dprof import analyze, scenarios as sc
sc.load("perflab")
def g(n, v, failed=0):
    return {"id": "table.rows.%d.down" % n, "title": "t", "kind": "input", "budget_ms": 50, "value": v, "rating": "good", "failed": failed}
rows = analyze.limits([g(100, 10.0), g(1000, 40.0), g(10000, 400.0)], {"table.rows.100.down", "table.rows.1000.down", "table.rows.10000.down", "table.rows.100000.down"})
r = rows[0]
print(r["within"], r["first_over"], r["hard"], round(r["slope"], 2), r["slope_at"], [p["rating"] for p in r["points"]][-1])')"
	eq "1000 10000 100000 0.8 10000 missing" "$out"
}

ti_profiler_perflab_generates_one_page_per_wanted_button_rung_with_its_callbacks() {
	command -v python3 >/dev/null || return 0
	local out
	out="$(cd "$REPO/tools/profiler" && python3 -c '
import os
from dprof import scenarios as sc
sc.set_options(["buttons.count=3,5"])
sc.load("perflab")
n, wanted = sc.resolve_scenarios("sweep-buttons")
d = sc.prepare(wanted)
files = sorted(os.listdir(d))
page = open(os.path.join(d, "buttons_5.xml")).read()
print(files, page.count("<button"), sc.ENV["PERFLAB_GEN"] == d)')"
	eq "['buttons_3.xml', 'buttons_5.xml', 'perflab_callbacks.sh'] 5 True" "$out"
}

ti_profiler_perflab_static_pages_pass_the_validator() {
	local f
	for f in start ticks every hooks table; do
		tui.validate.files "$REPO/tools/perflab/pages/$f.xml"
		eq "0" "$TUI_V_ERRORS"
	done
}

ti_profiler_the_same_group_traced_twice_adds_up_and_floor_wants_five_passes_quick_one() {
	command -v python3 >/dev/null || return 0
	local out
	out="$(cd "$REPO/tools/profiler" && python3 -c '
from dprof import analyze, scenarios as sc
a = {"stacks": {(("f",), "sh"): [100, 2]}, "lines": {"x:1": [1, 2, 3, 4]}, "calls": {"f": 1}, "edges": {}, "forks": {}, "focus": {}, "execs": {}, "tot": {"sh": 10, "ex": 1}, "nlines": 5, "pids": 2}
b = {"stacks": {(("f",), "sh"): [50, 1], (("g",), "sh"): [7, 1]}, "lines": {"x:1": [1, 1, 1, 1]}, "calls": {"f": 2, "g": 1}, "edges": {}, "forks": {}, "focus": {}, "execs": {}, "tot": {"sh": 5, "ex": 0}, "nlines": 3, "pids": 3}
m = analyze.merge_buckets(a, b)
sc.load("perflab")
names, wanted = sc.resolve_scenarios("floor")
print(m["stacks"][(("f",), "sh")], m["stacks"][(("g",), "sh")], m["lines"]["x:1"], m["calls"], m["tot"], m["nlines"], m["pids"], a["tot"]["sh"],
      sc.RUNS["floor"]["trace_runs"], sc.RUNS["floor"]["quick_trace_runs"], sorted({sc.parse_group(g)[2] for g in wanted if sc.parse_group(g)[1] == "rows"}))')"
	eq "[150, 3] [7, 1] [2, 3, 4, 5] {'f': 3, 'g': 1} {'sh': 15, 'ex': 1} 8 3 10 5 1 [100]" "$out" # the inputs are left alone
}

ti_profiler_parallel_units_print_as_one_block_each_and_problems_come_back_at_the_end() {
	command -v python3 >/dev/null || return 0
	local out
	out="$(cd "$REPO/tools/profiler" && python3 -c '
import io
from dprof import scenarios as sc, term
sc.load()
from dprof.live import LiveUI
term.init(False)
ok = {"group": "nav.first", "settle_ms": 20.0, "paint_ms": 5.0, "frames": 1, "bytes": 100, "ok": True}
bad = {"group": "nav.first", "ok": False, "note": "x not on screen"}
def run(tty):
    o = io.StringIO()
    ui = LiveUI([("latency", "Latency", 1, 8)], out=o, tty=tty)
    ui.phase("latency", "round 1/1", 8)
    ui.unit_begin("a", 2); ui.unit_begin("b", 2)
    ui.unit_step_begin("a", "a.s1"); ui.unit_step_begin("b", "b.s1")
    ui.unit_step_end("b", "b.s1", bad); ui.unit_warn("b", "step b.s1 failed: x not on screen")
    ui.unit_step_end("a", "a.s1", ok)
    ui.unit_step_begin("a", "a.s2"); ui.unit_step_end("a", "a.s2", ok)
    if tty:
        ui.unit_step_begin("b", "b.s2")
        ui._clear_footer(); ui._draw_footer()   # mid-run: b is still running
    ui.unit_done("a")
    if not tty:
        ui.unit_step_begin("b", "b.s2")
    ui.unit_step_end("b", "b.s2", ok); ui.unit_done("b")
    ui.finish()
    return o.getvalue()
plain = run(False)
live = run(True)
lines = [l for l in plain.splitlines() if l.strip()]
ia = [i for i, l in enumerate(lines) if "a.s1" in l or "a.s2" in l]
ib = [i for i, l in enumerate(lines) if "b.s1" in l or "b.s2" in l]
head_a = next(i for i, l in enumerate(lines) if l.startswith("▍") and " a " in l + " ")
print(max(ia) - min(ia) == 1, max(ib) - min(ib) >= 1, "\x1b" not in plain, "1 problem(s)" in plain,
      lines[-1].strip().startswith("✗ b"), "2 steps" in plain, "b.s1" in live and "1/2" in live and "\x1b[" in live)')"
	eq "True True True True True True True" "$out" # each unit is contiguous under its header; no escapes without a tty; problems repeated last
}

ti_profiler_an_app_still_gets_its_probe_pipe_when_the_parent_pipe_already_sits_on_fd_8() {
	command -v python3 >/dev/null || return 0
	local out
	out="$(cd "$REPO/tools/profiler" && python3 -c '
import os
from dprof.session import inherit_pipes
held = []
while True:   # occupy fds until the next pipe() hands out (7, 8): the write end lands on 8, as it does when units start side by side
    fd = os.open(os.devnull, os.O_RDONLY)
    held.append(fd)
    if fd == 6:
        break
r, w = os.pipe()
tr, tw = os.pipe()
pid = os.fork()
if pid == 0:
    inherit_pipes(w, tw)
    os.execvp("sh", ["sh", "-c", "echo probe >&8; echo trace >&9"])
os.close(w); os.close(tw)
os.waitpid(pid, 0)
print(w, os.read(r, 20).decode().strip(), os.read(tr, 20).decode().strip())
for fd in held: os.close(fd)')"
	eq "8 probe trace" "$out" # dup2(8, 8) keeps close-on-exec: without the move the app has no probe pipe
}
