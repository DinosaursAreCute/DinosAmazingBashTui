# profiler_startup.t.sh - the startup timeline of tools/benchmarks/profiler: which phases have a probe, what stays unprobed.
# Reads the definitions with python3 only; it starts no app.

ti_profiler_startup_phases_are_probed_and_the_functions_exist() {
	command -v python3 >/dev/null || return 0
	local out
	out="$(cd "$REPO/tools/benchmarks/profiler" && python3 -c '
import re
from dprof import session
need = {"_tui_cache_warm_prelude", "_tui_cache_lazy.start", "_tui_cache_lazy.announce", "_tui_cache_lazy.finish",
        "_tui_store.restore_page", "_tui_store.enter_focus", "_tui_cache_warm_worker", "_tui_validate.begin", "_tui_validate.finish"}
probes = {n for n, _ in session.WRAP}
src = "".join(open(f, errors="ignore").read() for f in __import__("glob").glob("../../../lib/**/*.sh", recursive=True))
missing = sorted(need - probes) + sorted(n for n in need if not re.search(r"^" + re.escape(n) + r"\(\)", src, re.M))
print(" ".join(missing))')"
	eq "" "$out"
}

ti_profiler_startup_gaps_name_what_is_not_covered_by_a_probe() {
	command -v python3 >/dev/null || return 0
	local out
	out="$(cd "$REPO/tools/benchmarks/profiler" && python3 -c '
from dprof.runner import unprobed_gaps
spans = [("boot", 0.0, 5.0), ("lib", 5.0, 100.0), ("nested", 20.0, 40.0), ("page", 400.0, 450.0)]
for label, s, e in unprobed_gaps(spans, 455.0, 10.0):
    print(f"{label} {s:.0f} {e:.0f}")')"
	eq "unprobed after lib 100 400" "$out" # the nested span adds nothing, the 5 ms tail after page is under the threshold
}

ti_profiler_startup_worker_stats_count_every_cache_build() {
	command -v python3 >/dev/null || return 0
	local out
	out="$(cd "$REPO/tools/benchmarks/profiler" && python3 -c '
from types import SimpleNamespace as E
from dprof.runner import worker_stats
evs = [E(kind="E", name="_tui_cache_warm_worker", t0=1.0, t1=1.5), E(kind="E", name="_tui_cache_warm_worker", t0=1.1, t1=1.9),
       E(kind="E", name="tui.init", t0=0.0, t1=9.0)]
w = worker_stats(evs)
print(w["count"], round(w["max_ms"]), round(w["sum_ms"]), round(w["span_ms"]))')"
	eq "2 800 1300 900" "$out" # span: first start to last end
}
