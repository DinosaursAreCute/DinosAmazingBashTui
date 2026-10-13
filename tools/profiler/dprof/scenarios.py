"""Scenario files: what a profiler run is based on.

A scenario file is a Python module that says which app interactions to replay, how they are grouped and what each
group's budget is (the bundled one is scenarios/demo.py; its docstring lists the names a file defines). This module
is the engine side: the step vocabulary a file builds on, the loader, and the selection of what to run.

The registries below (GROUP_INFO, FOCUS_ROOTS, SCENARIOS, ENV, DEFAULTS) are filled in place by `load`, so the
modules that imported them by name (analyze, live, trace, profile) see the loaded file without further wiring.
"""
import atexit
import importlib.util
import os
import shutil
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PROFILER_DIR = os.path.dirname(HERE)
SCENARIO_DIR = os.path.join(PROFILER_DIR, "scenarios")
DEFAULT_FILE = "demo"

ESC = b"\x1b"
DOWN, UP, LEFT, RIGHT = ESC + b"[B", ESC + b"[A", ESC + b"[D", ESC + b"[C"
REPEAT_S = 0.033        # key repeat of a held key: ~30 per second (X11 default 25/s, macOS/Windows ~30/s)

GROUP_INFO = {}         # group: (title, kind, budget_ms)
FOCUS_ROOTS = []        # functions the trace breaks down in full
SCENARIOS = []          # (name, description, groups | None)
UNIT_GROUPS = []        # (unit name, [groups])
ENV = {}                # extra environment of the profiled app
DEFAULTS = {"app": None, "size": "150x45", "shim_pattern": '"$(dirname "$0")/../lib/tui.sh"'}
DEFAULT_PAGE = None
UNIT_ENV = {}           # unit name -> extra environment of that unit's app (a sweep rung carries its N here)
SWEEP = set()           # scenario names that are sweeps: on demand, and latency only unless --trace
RUNS = {}               # scenario name -> {rounds, trace_runs, quick_rounds, quick_trace_runs}: how many passes it wants
OPTIONS = {}            # --set NAME=VALUE, read by a scenario file with option()
WORKDIR = {"path": None}
SOURCE = {"name": "", "path": ""}   # which file is loaded (recorded in the report)
_steps = None
_prepare = None


class Step:
    def __init__(self, group, detail, kind, payload=None, quiet=0.12, timeout=6.0, all_work=False, expect=None):
        self.group, self.detail, self.kind, self.payload = group, detail, kind, payload
        self.quiet, self.timeout, self.all_work = quiet, timeout, all_work
        self.expect = expect   # text that must be on screen after the step, or the step is reported as failed
        self.wait = 0.5  # traced runs: fixed wait, set from the untraced medians (see runner)

    def describe(self):
        return f"{self.group} · {self.detail}"


class Unit:
    """One independent profiling unit: a fresh app started from the same warmed cache on the default page, then its steps.
    The steps are `setup` steps (navigate to the page, put it in its start state; not measured) followed by the
    measured ones. Units share nothing, so they can run side by side."""

    def __init__(self, name, groups, steps, env=None):
        self.name, self.groups, self.steps = name, set(groups), steps
        self.env = dict(env or {})   # environment on top of the run's: what makes this unit's page this size


# ── step vocabulary for scenario files ───────────────────────────────────────
def pointer(needle, code, dx=0, dy=0, gap=0.03):
    """Payload of a "pointer" step: one mouse event (code: m move, p press, d drag, r release, w/W wheel down/up) placed at
    (dx, dy) cells from the first character of NEEDLE on screen, which is found when the step runs."""
    return (needle, [(code, dx, dy)], gap)


def move(x, y):
    return b"\x1b[<35;%d;%dM" % (x, y)


def click(x, y):
    return b"\x1b[<0;%d;%dM\x1b[<0;%d;%dm" % (x, y, x, y)


def wheel(x, y, down=True, n=1):
    return (b"\x1b[<%d;%d;%dM" % (65 if down else 64, x, y)) * n


def setup(label):
    """An unmeasured step that clicks the text LABEL (navigate, focus a field)."""
    return Step("setup", label, "click_text", label, quiet=0.15)


def palette_goto(word):
    """Setup steps that reach a page the nav does not list: ctrl+p, the first letters of its command, but not Enter
    (the caller sends Enter as the measured step)."""
    S = [Step("setup", "palette", "key", b"\x10", quiet=0.2)]
    S += [Step("setup", f"type {ch}", "key", ch.encode(), quiet=0.08) for ch in word]
    return S


def fill(label, value):
    """Setup steps that put VALUE into the input labelled LABEL: click it, go to the end, erase, type."""
    S = [setup(label), Step("setup", f"end {label}", "key", ESC + b"[F", quiet=0.08),
         Step("setup", f"clear {label}", "key", b"\x7f" * 8, quiet=0.1)]
    S += [Step("setup", f"{label} {ch}", "key", ch.encode(), quiet=0.06) for ch in str(value)]
    return S


# ── options and sweeps ───────────────────────────────────────────────────────
def set_options(pairs):
    """['a=1', 'b.c=2,3'] -> OPTIONS. Raises ValueError on an item without '='."""
    for item in pairs or ():
        key, eq, value = item.partition("=")
        if not eq or not key:
            raise ValueError(f"--set wants NAME=VALUE, got '{item}'")
        OPTIONS[key.strip()] = value.strip()


def option(name, default=None):
    """The --set value of NAME, converted like DEFAULT (bool, int, float, list of ints for a list default)."""
    v = OPTIONS.get(name)
    if v is None:
        return default
    if isinstance(default, bool):
        return v.lower() in ("1", "true", "yes", "on")
    if isinstance(default, int):
        return int(v)
    if isinstance(default, float):
        return float(v)
    if isinstance(default, (list, tuple)):
        return [int(x) for x in v.replace(" ", "").split(",") if x]
    return v


def ladder(name, values, floor=1):
    """The rungs of an axis: `--set NAME=a,b,c` replaces them, `--set scale=F` multiplies the defaults. Sorted, unique."""
    given = option(name, None)
    if given is not None:
        vals = option(name, list(values))
    else:
        k = option("scale", 1.0)
        vals = [max(floor, int(round(v * k))) for v in values]
    return sorted(set(vals))


def group_id(feature, axis, n, action):
    """Group of one sweep rung: `table.rows.1000.pgdn`. Feature, axis and action carry no dots."""
    return f"{feature}.{axis}.{n}.{action}"


def parse_group(gid):
    """-> (feature, axis, n, action) for a sweep group id, else None."""
    parts = gid.split(".")
    if len(parts) == 4 and parts[2].isdigit():
        return parts[0], parts[1], int(parts[2]), parts[3]
    return None


def prepare(wanted):
    """Lets the file write what the wanted groups need (a page per rung) into a run-private directory before any app
    starts; its returned dict is added to the apps' environment. Without a hook: nothing."""
    if _prepare is None:
        return None
    path = tempfile.mkdtemp(prefix="dprof-scenario-")
    WORKDIR["path"] = path
    atexit.register(shutil.rmtree, path, True)
    ENV.update(_prepare(wanted, path) or {})
    return path


# ── loading ──────────────────────────────────────────────────────────────────
class ScenarioFileError(Exception):
    pass


def find(spec=None):
    """A file path, or a bare name looked up in scenarios/ (with or without .py)."""
    spec = spec or DEFAULT_FILE
    for cand in (spec, os.path.join(SCENARIO_DIR, spec), os.path.join(SCENARIO_DIR, spec + ".py")):
        if os.path.isfile(cand):
            return os.path.abspath(cand)
    raise ScenarioFileError(f"scenario file '{spec}' not found (looked for it as a path and in {SCENARIO_DIR})")


def load(spec=None):
    """Load a scenario file and fill the registries. Returns the module."""
    path = find(spec)
    name = os.path.splitext(os.path.basename(path))[0]
    mod_spec = importlib.util.spec_from_file_location("dprof_scenario_" + name, path)
    mod = importlib.util.module_from_spec(mod_spec)
    try:
        mod_spec.loader.exec_module(mod)
    except Exception as e:   # a broken scenario file is the user's to fix: say which and why
        raise ScenarioFileError(f"{path}: {type(e).__name__}: {e}") from e
    missing = [n for n in ("GROUP_INFO", "SCENARIOS", "UNIT_GROUPS", "steps") if not hasattr(mod, n)]
    if missing:
        raise ScenarioFileError(f"{path}: missing {', '.join(missing)} (see the docstring of scenarios/demo.py)")
    problems = check(mod)
    if problems:
        raise ScenarioFileError(f"{path}: " + "; ".join(problems))

    global DEFAULT_PAGE, _steps, _prepare
    GROUP_INFO.clear()
    GROUP_INFO.update(mod.GROUP_INFO)
    FOCUS_ROOTS[:] = list(getattr(mod, "FOCUS_ROOTS", ()))
    SCENARIOS[:] = list(mod.SCENARIOS)
    UNIT_GROUPS[:] = list(mod.UNIT_GROUPS)
    ENV.clear()
    ENV.update(getattr(mod, "ENV", {}))
    DEFAULTS["app"] = getattr(mod, "APP", None)
    DEFAULTS["size"] = getattr(mod, "SIZE", "150x45")
    DEFAULTS["shim_pattern"] = getattr(mod, "SHIM_PATTERN", '"$(dirname "$0")/../lib/tui.sh"')
    DEFAULT_PAGE = getattr(mod, "DEFAULT_PAGE", None)
    _steps = mod.steps
    _prepare = getattr(mod, "prepare", None)
    UNIT_ENV.clear()
    UNIT_ENV.update(getattr(mod, "UNIT_ENV", {}))
    SWEEP.clear()
    SWEEP.update(getattr(mod, "SWEEP_SCENARIOS", ()))
    RUNS.clear()
    RUNS.update(getattr(mod, "RUNS", {}))
    SOURCE.update(name=name, path=path)
    return mod


def check(mod):
    """Consistency of a scenario file's tables; a list of problems (empty = fine)."""
    bad = []
    info = mod.GROUP_INFO
    for g, v in info.items():
        if not (isinstance(v, tuple) and len(v) == 3):
            bad.append(f"GROUP_INFO[{g!r}] must be (title, kind, budget_ms)")
    names = [n for n, _, _ in mod.SCENARIOS]
    if len(set(names)) != len(names):
        bad.append("SCENARIOS has a duplicate name")
    for n, _, groups in mod.SCENARIOS:
        for g in groups or ():
            if g not in info:
                bad.append(f"scenario {n}: group {g} is not in GROUP_INFO")
    for n in getattr(mod, "SWEEP_SCENARIOS", ()):
        if n not in names:
            bad.append(f"SWEEP_SCENARIOS names {n}, which is not in SCENARIOS")
    for n, r in getattr(mod, "RUNS", {}).items():
        if n not in names:
            bad.append(f"RUNS names {n}, which is not in SCENARIOS")
        missing = {"rounds", "trace_runs", "quick_rounds", "quick_trace_runs"} - set(r)
        if missing:
            bad.append(f"RUNS[{n!r}] lacks {', '.join(sorted(missing))}")
    seen = {}
    for unit, groups in mod.UNIT_GROUPS:
        for g in groups:
            if g not in info:
                bad.append(f"unit {unit}: group {g} is not in GROUP_INFO")
            if g in seen:
                bad.append(f"group {g} is in units {seen[g]} and {unit}")
            seen[g] = unit
    return bad


def steps(rows, cols, quick=False, wanted=None):
    """The loaded file's user session for the wanted groups (None = all)."""
    return _steps(rows, cols, quick, wanted)


# ── selection ────────────────────────────────────────────────────────────────
def resolve_scenarios(spec):
    """'2,theme' / 'nav input' -> (names, wanted group set or None for everything). Raises ValueError."""
    scenario_names = [n for n, _, _ in SCENARIOS]
    names = []
    for tok in spec.replace(",", " ").split():
        if tok.isdigit() and 1 <= int(tok) <= len(SCENARIOS):
            names.append(SCENARIOS[int(tok) - 1][0])
        elif tok in scenario_names:
            names.append(tok)
        else:
            raise ValueError(f"unknown scenario '{tok}' (try: {', '.join(scenario_names)} or 1-{len(SCENARIOS)})")
    if not names:
        names = [SCENARIOS[0][0]]
    everything = [n for n, _, g in SCENARIOS if n in names and g is None]
    if everything:
        return [everything[0]], None
    wanted = set()
    for n in names:
        wanted |= dict((a, g) for a, _, g in SCENARIOS)[n]
    return names, wanted


def units(rows, cols, quick=False, wanted=None):
    """The units a run needs for the wanted groups (None = all), in the file's order."""
    out = []
    for name, groups in UNIT_GROUPS:
        gs = set(groups) if wanted is None else set(groups) & wanted
        if not gs:
            continue
        unit_steps = steps(rows, cols, quick, gs)
        while unit_steps and unit_steps[0].group == "setup" and unit_steps[0].detail == DEFAULT_PAGE:   # the unit already starts there
            unit_steps.pop(0)
        while unit_steps and unit_steps[-1].group == "setup":   # putting the page back is for the next step of one long run; a unit just ends
            unit_steps.pop()
        out.append(Unit(name, gs, unit_steps, UNIT_ENV.get(name)))
    return out
