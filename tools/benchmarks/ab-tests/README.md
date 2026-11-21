# ab-tests

Traceable A/B timing. A scenario file defines two or more sides (functions or commands); `ab.sh` runs them interleaved, compares them and saves everything needed to reproduce and re-compare the result.

```
ab.sh run scenarios/example.sh [-n ROUNDS] [-w WARMUP]
ab.sh list
ab.sh show RUN
ab.sh compare RUN_A RUN_B [SIDE_A [SIDE_B]]   # e.g. last week's run vs today's, per shared side
```

Scenario variables, hooks and the run-dir contents are documented in the header of [ab.sh](ab.sh). A run is `runs/<UTC>_<name>/` with `scenario.sh`, `meta.txt` (git rev + dirty flag, host, cpu governor, load, hashes/bodies of A and B), `samples.tsv`, `report.txt`; `runs/index.tsv` lists all runs.

Optional scenario knobs: `AB_CONTROL` (side subtracted as overhead, e.g. the empty loop), `AB_UNITS` (calls per sample -> ns/unit columns), `AB_X` (numeric x per side -> slope/intercept, e.g. cost per call layer).

Scenarios:

| File | Question |
|---|---|
| `calls-depth.sh` | cost of one function-call layer: depth 0/1/2/4/8/16, empty body, slope per layer |
| `calls-variants.sh` | call overhead with args, `local`, and realistic bodies (arithmetic, `[[ ]]`) vs inline twins |
| `calls-subshell.sh` | direct call vs `$(...)`: the fork is the real cost |
| `calls-all.sh` | suite: runs the three calls-* scenarios and selfcheck in one go |
| `selfcheck.sh` | A vs A, must say `~noise`; a clear verdict means the runner is biased |
| `example.sh` | two-side shorthand (`A_CMD`/`B_CMD`) |

Verdict: Welch t-statistic on the samples, `|t| < 2` means "within noise". Rounds alternate which side goes first to cancel order bias and drift.

Reporting: `ab.sh` prints through the shared reporter of [../reporting](../reporting/README.md) via [ab_report.py](ab_report.py): header, a RESULT panel in plain words (median, slowest, fastest per side; "X is FASTER/SLOWER than base by N% / time"), the scorecard (sides rated against the base side's median) and a diff against the previous run of the same scenario. `report.txt` is the same text without colour. Without `python3` (or with `AB_PLAIN=1`) it falls back to the plain awk table. `ab_report.py RUN_DIR [--vs RUN_DIR|none]` re-renders any saved run.

Live view: while a run is going, `ab_report.py --live` follows `warmup.tsv` / `samples.tsv` with the shared `LiveUI`: one line per finished sample (its time, and its median so far against the base side), a footer with the sample running now, phase, progress and ETA. Measured on the call scenarios, it does not change the medians (live on/off within 1%); `AB_LIVE=0` turns it off if you suspect it on a small machine. `warmup.tsv` is kept in the run dir with the raw warmup samples.

Suites: when a suite (`AB_SUITE`, e.g. `scenarios/calls-all.sh`) finishes, a SUITE SUMMARY table lists every side of every run (median, slowest, fastest, gross ns/unit, verdict against that run's base). The plain text is saved as `runs/<UTC>_suite_<file>.txt` together with the list of run dirs it covers.

## What do the framework's function calls cost?

1. Price list: `ab.sh run scenarios/calls-all.sh` (marginal cost of the L-th nested call, of a `local`, of an argument).
2. Count the calls:
   - **headless command** (bench scripts, tests): `callcount.py -- tools/bench/hit.sh` copies the repo, puts a counter into every function of `lib/`, runs the command in the copy and counts exactly (names, call depth, subshells included) with a live footer. It first runs the command untouched to get the real duration. Results in `callcounts/<UTC>_<name>/`.
   - **the real app**: `profiler/profile.sh` (trace pass). The profiler's report now carries calls per call depth and interaction (`attr.functions[].depths_by_group`).
3. Cross-reference: `callmodel.py callcounts/<run>` or `callmodel.py ../profiler/reports/latest` prints, per function (or per interaction for the profiler), the call overhead as a low–high range and its share of the run, using the shared reporter. `callcount.py` runs it automatically when a calls-depth run exists.
4. Validate a finding by inlining the hot chain and A/B-ing the two versions with `ab.sh`.

Validating a call-model finding: `ab.sh run scenarios/inline-attr-get.sh` A/Bs `page_switch.sh` against a patched copy of the repo where `_tui_build.attrv` no longer calls `tui_node.attr_get` (copies under a temp dir, the working tree is untouched).
