# renderer_profiler.t.sh - tools/benchmarks/renderers: every public renderer has cases, and rows become a report.
# Reads definitions and a fixed TSV with python3 and grep; it measures nothing and starts no app.

ti_renderer_profiler_every_public_renderer_has_a_case() {
	local lib="$REPO/lib/terminal_renderer.sh" cases="$REPO/tools/benchmarks/renderers/scenarios/cases.sh" name missing=""
	while IFS= read -r name; do
		name="${name%_string}"
		grep -qE "rc_case[[:space:]]+$name[[:space:]]" "$cases" || missing+="$name "
	done < <(grep -oE '^[a-z][a-z_0-9]*_string\(\)' "$lib" | tr -d '()')
	eq "" "$missing"
}

ti_renderer_profiler_rows_become_one_group_per_renderer_with_a_case_each() {
	command -v python3 >/dev/null || return 0
	local out
	out="$(cd "$REPO/tools/benchmarks/renderers" && python3 -I -c '
import importlib.util, sys
sys.path.insert(0, "..")
spec = importlib.util.spec_from_file_location("rp", "profile.py"); rp = importlib.util.module_from_spec(spec); spec.loader.exec_module(rp)
tsv = "box/short/plain\tbox\tshort\tplain\t5\t3\t1000,2000,3000\t120\t0\nbox/long/plain\tbox\tlong\tplain\t5\t3\t9000,8000,7000\t900\t2\ngauge/v/plain\tgauge\tv\tplain\t5\t3\t100,100,100\t48\t0\n"
rows = [rp.parse_row(l) for l in tsv.splitlines()]
rep = rp.build_report(rp.merge_rounds([rows]), {"title": "T", "rounds": 1}, None)
g = {x["id"]: x for x in rep["latency"]}
print(sorted(g), len(g["box"]["details"]), g["box"]["details"][1]["forks"], round(g["box"]["value"], 2), g["box"]["rating"], g["gauge"]["rating"])
from reporting import default_reporter, term
term.init(False)
print("box" in "\n".join(default_reporter.render(rep, 100)))')"
	eq "['box', 'gauge'] 2 2 5.0 good good
True" "$out"
}
