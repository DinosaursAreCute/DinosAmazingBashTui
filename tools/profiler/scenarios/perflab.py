"""Scenario file for perflab (tools/perflab): the framework profiled on its own terms, not through the demo.

Every feature is pushed along the axis its own code iterates over (tick listeners, tui.every jobs, key hook handlers,
table rows and columns, buttons, textarea lines, input characters, markdown paragraphs and tables, widgets per page
for navigation, palette commands), at a ladder of sizes. The ladder's first rung is the normal use, its last the extreme. One rung is
one unit: a fresh app that opens the feature page at that size, so rungs cannot disturb each other.

  profile.sh --scenarios perflab                         normal and extreme of every axis (latency + trace)
  profile.sh --scenarios perflab --scenario floor        normal use of every feature, traced: 5 rounds and 5 traced passes
                                                         (--quick: 1 and 1, like the demo's quick run)
  profile.sh --scenarios perflab --scenario table        one feature, normal and extreme
  profile.sh --scenarios perflab --scenario sweep        every rung of every axis: latency only, on demand
  profile.sh --scenarios perflab --scenario sweep-table --trace      one feature's sweep with the call-stack trace
  --set scale=0.1            every ladder scaled (a quick look); --set table.rows=100,1000,50000   one axis's rungs

Group ids are `feature.axis.N.action`; the report's LIMITS panel folds them per axis. Add a feature: one row in AXES,
a page in tools/perflab/pages (or a generator in `prepare`), its callbacks in perflab_callbacks.sh.
"""
import os
import shutil

from dprof.scenarios import (ESC, Step, click, group_id, ladder, option, parse_group, pointer, wheel)

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
APP_DIR = os.path.join(REPO, "tools", "perflab")
APP = "tools/perflab/bin/perflab.sh"
SHIM_PATTERN = '"$(dirname "$0")/../../../lib/tui.sh"'
SIZE = "150x45"
ENV = {"PERFLAB_PAGES": os.path.join(APP_DIR, "pages")}

OPEN = "[ Open page"

# action -> (kind, budget_ms): the perceived-instant lines the demo scenario uses, so a rung that goes over one is slow
# in the same sense
ACTIONS = {
    "open": ("nav", 150), "key": ("input", 50), "tab": ("input", 50), "hover": ("input", 30), "click": ("input", 100),
    "down": ("input", 50), "pgdn": ("input", 100), "wheel": ("input", 60),
    "idle": ("idle", 150),   # cpu ms the app uses in the 3 s window (5%)
    "type": ("input", 50), "enter": ("input", 50), "undo": ("input", 50), "selall": ("input", 100), "left": ("input", 50),
    "home": ("input", 50),
    "back": ("nav", 100), "revisit": ("nav", 100), "resize": ("resize", 250),
    "popen": ("input", 100), "ptype": ("input", 50), "pclose": ("input", 100),
}

# feature, axis, rungs (first = normal, last = extreme), page (a file in tools/perflab/pages, or a template the
# generator fills), what a rung's N sets in the environment, actions, ready text on the page
AXES = [
    dict(feature="ticks", axis="listeners", rungs=[3, 30, 300, 3000], page="ticks.xml", env={"PERFLAB_N": "{n}"},
         actions=["open", "key", "idle"], ready="PERFLAB ticks ready", per_item_s=0.01),
    dict(feature="every", axis="jobs", rungs=[3, 30, 300, 3000], page="every.xml", env={"PERFLAB_N": "{n}"},
         actions=["open", "key", "idle"], ready="PERFLAB every ready", per_item_s=0.01),
    dict(feature="hooks", axis="handlers", rungs=[2, 20, 200, 2000], page="hooks.xml", env={"PERFLAB_N": "{n}"},
         actions=["open", "key"], ready="PERFLAB hooks ready", per_item_s=0.01),
    dict(feature="table", axis="rows", rungs=[100, 1000, 10000, 100000], page="table.xml",
         env={"PERFLAB_N": "{n}", "PERFLAB_COLS": "6"}, actions=["open", "down", "pgdn", "wheel"],
         ready="PERFLAB table ready", per_item_s=0.0015, focus_click="r1"),
    dict(feature="table", axis="cols", rungs=[3, 12, 48, 192], page="table.xml",
         env={"PERFLAB_N": "200", "PERFLAB_COLS": "{n}"}, actions=["open", "down", "pgdn", "wheel"],
         ready="PERFLAB table ready", per_item_s=0.02, focus_click="r1"),
    dict(feature="textarea", axis="lines", rungs=[50, 500, 5000, 50000], page="textarea.xml", env={"PERFLAB_N": "{n}"},
         actions=["open", "type", "enter", "undo", "down", "pgdn", "selall"], ready="PERFLAB textarea ready",
         per_item_s=0.001, focus_click="line 1:"),
    dict(feature="input", axis="chars", rungs=[80, 1000, 10000, 100000], page="input.xml", env={"PERFLAB_N": "{n}"},
         actions=["open", "type", "left", "home"], ready="PERFLAB input ready", per_item_s=0.0001, focus_click="text:"),
    dict(feature="markdown", axis="paragraphs", rungs=[5, 50, 500, 5000], page="markdown_paragraphs_{n}.xml",
         gen="markdown_paragraphs", env={"PERFLAB_N": "{n}"}, actions=["open", "pgdn", "wheel", "resize"],
         ready="PERFLAB markdown page", per_item_s=0.05),
    dict(feature="markdown", axis="tables", rungs=[1, 10, 100, 1000], page="markdown_tables_{n}.xml",
         gen="markdown_tables", env={"PERFLAB_N": "{n}"}, actions=["open", "pgdn", "wheel", "resize"],
         ready="PERFLAB markdown page", per_item_s=0.3),
    dict(feature="nav", axis="widgets", rungs=[10, 100, 1000, 5000], page="nav_{n}.xml", gen="nav",
         env={"PERFLAB_N": "{n}"}, actions=["open", "back", "revisit"], ready="PERFLAB nav ready", per_item_s=0.01),
    dict(feature="palette", axis="commands", rungs=[20, 200, 2000, 20000], page="palette.xml",
         env={"PERFLAB_N": "{n}"}, actions=["open", "popen", "ptype", "pclose"], ready="PERFLAB palette ready",
         per_item_s=0.002),
    dict(feature="buttons", axis="count", rungs=[10, 100, 1000, 3000], page="buttons_{n}.xml",
         env={"PERFLAB_N": "{n}"}, actions=["open", "tab", "hover", "click"], ready="PERFLAB buttons ready",
         per_item_s=0.01, gen="buttons"),
]
TITLE = {
    "open": "first visit", "key": "keypress", "tab": "Tab", "hover": "hover", "click": "click", "down": "Down",
    "pgdn": "Page Down", "wheel": "wheel", "idle": "idle cpu per 3 s", "type": "typing", "enter": "Enter",
    "undo": "undo", "selall": "select all", "left": "Left", "home": "Home", "back": "back to the cached start page",
    "revisit": "revisit", "resize": "terminal resize", "popen": "palette open", "ptype": "palette typing",
    "pclose": "palette close",
}

HEAD = ('<tui xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="tui.xsd">\n'
        '  <script src="perflab_callbacks.sh"/>\n')
BUTTONS_PAGE = HEAD + '''  <pane id="root" title="perflab buttons" border="single" scroll="v">
    <label id="lbl_ready" text="PERFLAB buttons ready"/>
%s  </pane>
</tui>
'''
NAV_PAGE = HEAD + '''  <pane id="root" title="perflab nav" border="single" scroll="v">
    <label id="lbl_ready" text="PERFLAB nav ready"/>
    <button id="btn_back" text="[ Back ]" action="perflab_back"/>
%s  </pane>
</tui>
'''
MARKDOWN_PAGE = HEAD + '''  <pane id="root" split="v" border="none">
    <pane id="hdr" height="3" title="perflab markdown" border="single">
      <label id="lbl_page" text="PERFLAB markdown page"/>
    </pane>
    <pane id="md" border="single" scroll="v"/>
  </pane>
  <markdown pane="md" src="%s"/>
</tui>
'''
PARAGRAPH = ("Paragraph %d has **bold**, *italic*, `code` and a [link](https://example.com/%d) in a sentence long "
             "enough to wrap over a line or two of the pane.\n\n")
TABLE = ("| name | size | kind | note |\n|---|---:|---|---|\n" + "".join(
    f"| item {r} | {r * 7} | k{r % 3} | text {r} |\n" for r in range(1, 6)) + "\n")


def _write(workdir, name, text):
    with open(os.path.join(workdir, name), "w") as f:
        f.write(text)


def _gen_buttons(ax, n, workdir):
    body = "".join(f'    <button id="b{i}" text="[ B{i} ]" action="perflab_noop"/>\n' for i in range(1, n + 1))
    _write(workdir, ax["page"].replace("{n}", str(n)), BUTTONS_PAGE % body)


def _gen_nav(ax, n, workdir):
    body = "".join(f'    <label id="r{i}" text="row {i}: the quick brown fox"/>\n' for i in range(1, n + 1))
    _write(workdir, ax["page"].replace("{n}", str(n)), NAV_PAGE % body)


def _gen_markdown(ax, n, workdir, block):
    doc = "# PERFLAB markdown ready\n\n" + "".join(block(i) for i in range(1, n + 1))
    md = f"md_{ax['axis']}_{n}.md"
    _write(workdir, md, doc)
    _write(workdir, ax["page"].replace("{n}", str(n)), MARKDOWN_PAGE % md)


GENERATORS = {
    "buttons": _gen_buttons,
    "nav": _gen_nav,
    "markdown_paragraphs": lambda ax, n, d: _gen_markdown(ax, n, d, lambda i: PARAGRAPH % (i, i)),
    "markdown_tables": lambda ax, n, d: _gen_markdown(ax, n, d, lambda i: TABLE),
}


def _rungs(ax):
    return ladder(f"{ax['feature']}.{ax['axis']}", ax["rungs"])


def _gid(ax, n, action):
    return group_id(ax["feature"], ax["axis"], n, action)


def _unit_name(ax, n):
    return f"{ax['feature']}.{ax['axis']}.{n}"


def _build_tables():
    info, units, unit_env, rung_of = {}, [], {}, {}
    for ax in AXES:
        ns = _rungs(ax)
        for n in ns:
            groups = []
            for action in ax["actions"]:
                kind, budget = ACTIONS[action]
                gid = _gid(ax, n, action)
                info[gid] = (f"{ax['feature']}: {TITLE[action]} at {n} {ax['axis']}", kind, budget)
                groups.append(gid)
                rung_of[gid] = (ax, n)
            units.append((_unit_name(ax, n), groups))
            env = {k: v.replace("{n}", str(n)) for k, v in ax["env"].items()}
            env["PERFLAB_PAGE"] = ax["page"].replace("{n}", str(n))
            unit_env[_unit_name(ax, n)] = env
    return info, units, unit_env, rung_of


GROUP_INFO, UNIT_GROUPS, UNIT_ENV, _RUNG_OF = _build_tables()


def _ends(ax):
    ns = _rungs(ax)
    return {ns[0], ns[-1]}


def _groups_of(select):
    return {g for g, (ax, n) in _RUNG_OF.items() if select(ax, n)}


def _scenarios():
    out = [("full", "Every axis at its normal and its extreme rung (the ladder's ends)",
            _groups_of(lambda ax, n: n in _ends(ax)))]
    out.append(("floor", "Normal use of every feature (each ladder's first rung): the cost of the framework with nothing "
                "pushed. Traced; 5 rounds and 5 traced passes, --quick 1 and 1",
                _groups_of(lambda ax, n: n == _rungs(ax)[0])))
    features = []
    for ax in AXES:
        if ax["feature"] not in features:
            features.append(ax["feature"])
    for f in features:
        out.append((f, f"{f}: normal and extreme of each axis", _groups_of(lambda ax, n, f=f: ax["feature"] == f and n in _ends(ax))))
    out.append(("sweep", "Every rung of every axis: where each feature stops being instant (on demand, latency only)",
                set(GROUP_INFO)))
    for f in features:
        out.append((f"sweep-{f}", f"{f}: every rung of each axis",
                    _groups_of(lambda ax, n, f=f: ax["feature"] == f)))
    return out


SCENARIOS = _scenarios()
RUNS = {"floor": {"rounds": 5, "trace_runs": 5, "quick_rounds": 1, "quick_trace_runs": 1}}
SWEEP_SCENARIOS = {n for n, _, _ in SCENARIOS if n.startswith("sweep")}


def prepare(wanted, workdir):
    """One generated page per wanted rung of a generated axis, next to a copy of the callbacks they load."""
    shutil.copy(os.path.join(ENV["PERFLAB_PAGES"], "perflab_callbacks.sh"), workdir)
    for ax in AXES:
        if not ax.get("gen"):
            continue
        for n in _rungs(ax):
            if wanted is not None and not any(_gid(ax, n, a) in wanted for a in ax["actions"]):
                continue
            GENERATORS[ax["gen"]](ax, n, workdir)
    return {"PERFLAB_GEN": workdir}


def _rung_steps(ax, n, want, quick, rows, cols):
    """The steps of one rung, starting on the start page of a fresh app."""
    S = []
    add = S.append
    open_timeout = min(180.0, 10.0 + n * ax["per_item_s"] * 4)
    gid = lambda a: _gid(ax, n, a)
    has = lambda a: a in ax["actions"] and want(gid(a))
    reps = 3 if quick else 5
    mx, my = cols // 2, rows // 2

    def keys(action, label, data, count, quiet=0.1, timeout=15.0):
        for i in range(count):
            add(Step(gid(action), f"{label} {i + 1}", "key", data, quiet=quiet, timeout=timeout))

    add(Step("setup", "start page settles", "idle", 0.5))   # the first frame may still be on its way to the profiler
    add(Step(gid("open") if has("open") else "setup", "open" if has("open") else "open page", "click_text", OPEN,
             quiet=0.4, timeout=open_timeout, expect=ax["ready"]))
    if "key" in ax["actions"] and has("key"):   # any key goes through the hooks and the per-frame loops
        keys("key", "tab", b"\t", reps)
    if has("tab"):
        keys("tab", "tab", b"\t", reps + 3)
    focus = ax.get("focus_click")   # a click, not Tab: where focus is after a goto depends on the page the app came from
    if focus and any(has(a) for a in ax["actions"] if a not in ("open", "idle", "resize", "key")):
        add(Step("setup", "focus the widget", "click_text", focus, quiet=0.2, timeout=15.0))
    # text editing: the order matters (edits first, then undo of them, then moving over the long text)
    if has("type"):
        keys("type", "char", b"a", reps, quiet=0.08)
    if has("enter"):
        keys("enter", "newline", b"\r", 3, quiet=0.1)
    if has("undo"):
        # alt+z, the documented alias: a pty with the Terminal shortcuts plugin's defaults does not deliver ctrl+z (0x1a)
        keys("undo", "alt+z", ESC + b"z", 3, quiet=0.1, timeout=4.0)
    if has("left"):
        keys("left", "left", ESC + b"[D", reps, quiet=0.08)
    if has("home"):
        keys("home", "home", ESC + b"[H", 2, quiet=0.1)
    if has("down"):
        keys("down", "down", ESC + b"[B", reps + 3, quiet=0.08)
    if has("pgdn"):
        keys("pgdn", "pgdn", ESC + b"[6~", 3, quiet=0.15)
    if has("selall"):
        keys("selall", "ctrl+a", b"\x01", 2, quiet=0.2)
    if has("wheel"):
        for i in range(reps):
            add(Step(gid("wheel"), f"tick {i + 1}", "key", wheel(mx, my), quiet=0.2, timeout=15.0))
    if has("hover"):
        for i in range(reps):
            add(Step(gid("hover"), f"B{i + 1}", "pointer", pointer(f"[ B{i + 1} ]", "m", 2, 0), quiet=0.06, timeout=5.0))
    if has("click"):
        for i in range(3):
            add(Step(gid("click"), f"B{i + 1}", "click_text", f"[ B{i + 1} ]", quiet=0.15, timeout=10.0))
    if has("resize"):   # the document re-wraps when the pane's width changes: narrower, then back
        add(Step(gid("resize"), f"{cols - 40}x{rows}", "resize", (rows, cols - 40), quiet=0.3, timeout=60.0))
        add(Step(gid("resize"), f"{cols}x{rows}", "resize", (rows, cols), quiet=0.3, timeout=60.0))
    if has("back"):   # to the cached start page and into the page again: replays, no build
        add(Step(gid("back"), "back", "click_text", "[ Back ]", quiet=0.2, timeout=open_timeout, expect="PERFLAB start"))
        add(Step(gid("revisit") if has("revisit") else "setup", "revisit", "click_text", OPEN, quiet=0.2,
                 timeout=open_timeout, expect=ax["ready"]))
    if has("popen"):
        add(Step(gid("popen"), "ctrl+p", "key", b"\x10", quiet=0.2, timeout=30.0))
        if has("ptype"):
            for ch in "perf":
                add(Step(gid("ptype"), ch, "key", ch.encode(), quiet=0.1, timeout=30.0))
        add(Step(gid("pclose") if has("pclose") else "setup", "esc", "key", ESC, quiet=0.2, timeout=30.0))
    if has("idle"):
        add(Step(gid("idle"), "3 s", "idle", 3.0))   # the budget is per 3 s: the window is not shortened by --quick
    return S


def steps(rows, cols, quick=False, wanted=None):
    """The steps of every rung that has a wanted group (None = all), one after the other. The engine asks for one unit
    at a time, so the result is that unit's rung."""
    want = (lambda g: True) if wanted is None else (lambda g: g in wanted)
    S = []
    for ax in AXES:
        for n in _rungs(ax):
            if any(want(_gid(ax, n, a)) for a in ax["actions"]):
                S += _rung_steps(ax, n, want, quick, rows, cols)
    return S
