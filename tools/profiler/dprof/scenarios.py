"""The scripted user session the profiler replays.

Each Step is one user action. `group` is what the report aggregates on; `detail` names the
individual action (page, coordinate). The order follows a realistic visit: start, look
around every page, use the keyboard, the mouse, the palette, resize, sit idle, quit.
"""

ESC = b"\x1b"
# (page, nav label clicked to reach it). Clicking is what a mouse user does and does not depend on
# which keys a page binds.
PAGES = [("home", "Home"), ("components", "Components"), ("settings", "Settings"), ("monitor", "Monitor"),
         ("terminal", "Terminal"), ("scrolling", "Scrolling"), ("case_study", "Case Study"), ("docs", "Docs"),
         ("layout", "Layout"), ("widgets", "Widgets")]
LABEL = dict(PAGES)
# alt+N bindings of the demo's _nav.xml (alt+0 is the tenth page)
KEY_PAGE = {"1": "home", "2": "components", "3": "settings", "4": "monitor", "5": "terminal", "6": "scrolling",
            "7": "case_study", "8": "docs", "9": "layout", "0": "widgets"}

GROUP_INFO = {
    # group: (title, kind, budget_ms)  budget = the perceived-instant line for that interaction
    "startup.cold": ("Cold start (empty cache)", "startup", 5000),
    "startup.warm": ("Warm start", "startup", 1000),
    "nav.first": ("Page switch, first visit", "nav", 150),
    "nav.revisit": ("Page switch, revisit", "nav", 100),
    "nav.key": ("Page switch by key (alt+1…0, every page)", "nav", 100),
    "focus.next": ("Focus next (Tab)", "input", 50),
    "focus.prev": ("Focus previous (Shift+Tab)", "input", 50),
    "hover.move": ("Mouse hover", "input", 30),
    "click": ("Mouse click", "input", 100),
    "scroll.step": ("Wheel scroll, single", "input", 60),
    "scroll.burst": ("Wheel scroll, burst", "input", 150),
    "scroll.page": ("Page Down", "input", 100),
    "palette.open": ("Command palette open", "input", 100),
    "palette.type": ("Command palette typing", "input", 50),
    "palette.close": ("Command palette close", "input", 100),
    "theme.first": ("Theme switch, first use", "nav", 250),
    "theme.again": ("Theme switch, repeat", "nav", 150),
    "resize": ("Terminal resize", "resize", 250),
    "idle": ("Idle (3 s, nothing happening)", "idle", 0),
    "shutdown": ("Quit", "shutdown", 500),
}


class Step:
    def __init__(self, group, detail, kind, payload=None, quiet=0.12, timeout=6.0, all_work=False):
        self.group, self.detail, self.kind, self.payload = group, detail, kind, payload
        self.quiet, self.timeout, self.all_work = quiet, timeout, all_work
        self.wait = 0.5  # traced runs: fixed wait, set from the untraced medians (see runner)

    def describe(self):
        return f"{self.group} · {self.detail}"


def _move(x, y):
    return b"\x1b[<35;%d;%dM" % (x, y)


def _click(x, y):
    return b"\x1b[<0;%d;%dM\x1b[<0;%d;%dm" % (x, y, x, y)


def _wheel(x, y, down=True, n=1):
    return (b"\x1b[<%d;%d;%dM" % (65 if down else 64, x, y)) * n


# Scenario presets: what `--scenario` selects. `groups=None` means everything. Steps the chosen groups
# need as preparation (navigate to a page, return home) run too but are labelled "setup" and not reported.
SCENARIOS = [
    ("full", "Everything: start, navigation, input, scrolling, palette, themes, resize, idle, quit", None),
    ("startup", "Cold start (empty cache) and warm start", {"startup.cold", "startup.warm"}),
    ("nav", "Page navigation: first visit, revisit, key binding", {"nav.first", "nav.revisit", "nav.key"}),
    ("input", "Focus, hover and click", {"focus.next", "focus.prev", "hover.move", "click"}),
    ("scroll", "Wheel, burst and Page Down scrolling", {"scroll.step", "scroll.burst", "scroll.page"}),
    ("palette", "Command palette open, typing, close", {"palette.open", "palette.type", "palette.close"}),
    ("theme", "Theme switching on the Settings page", {"theme.first", "theme.again"}),
    ("resize", "Terminal resize", {"resize"}),
    ("idle", "Idle: what the app does when nothing happens", {"idle"}),
]
SCENARIO_NAMES = [n for n, _, _ in SCENARIOS]
THEME_BUTTONS = ["ocean", "forest", "sunset", "light", "default"]   # Settings page rows (the page lowercases them); default last restores the look


def resolve_scenarios(spec):
    """'2,theme' / 'nav input' -> (names, wanted group set or None for everything). Raises ValueError."""
    names = []
    for tok in spec.replace(",", " ").split():
        if tok.isdigit() and 1 <= int(tok) <= len(SCENARIOS):
            names.append(SCENARIOS[int(tok) - 1][0])
        elif tok in SCENARIO_NAMES:
            names.append(tok)
        else:
            raise ValueError(f"unknown scenario '{tok}' (try: {', '.join(SCENARIO_NAMES)} or 1-{len(SCENARIOS)})")
    if not names or "full" in names:
        return ["full"], None
    wanted = set()
    for n in names:
        wanted |= dict((a, g) for a, _, g in SCENARIOS)[n]
    return names, wanted


def _setup(label):
    return Step("setup", label, "click_text", label, quiet=0.15)


def interaction_steps(rows, cols, quick=False, wanted=None):
    """Everything after startup. Coordinates scale with the terminal size.
    wanted: set of groups to keep (None = all); needed preparation is added automatically."""
    want = (lambda *gs: True) if wanted is None else (lambda *gs: any(g in wanted for g in gs))
    mx, my = cols // 2, rows // 2
    S = []
    add = S.append
    if want("nav.first", "nav.revisit", "nav.key"):
        for group in ("nav.first", "nav.revisit"):
            if want(group):
                for name, label in PAGES:
                    add(Step(group, name, "click_text", label, quiet=0.15))
                add(Step(group, "home", "click_text", "Home", quiet=0.15))
        if want("nav.key"):
            # alt+1..9 and alt+0 are bound in _nav.xml: every page once by key, so the median is over all pages and each
            # can be compared with clicking the same page (nav.first/nav.revisit details). The run before ends on home, so
            # the sequence starts at alt+2 (alt+1 would be a switch to the page already shown) and ends with alt+1.
            keys = ("2", "7") if quick else ("2", "3", "4", "5", "6", "7", "8", "9", "0", "1")
            for k in keys:
                add(Step("nav.key", f"alt+{k} {KEY_PAGE[k]}", "key", ESC + k.encode(), quiet=0.15, timeout=1.0))
    if want("focus.next", "focus.prev", "hover.move", "click"):
        add(_setup("Components"))
        for i in range(6 if quick else 10):
            if want("focus.next"):
                add(Step("focus.next", f"tab {i + 1}", "key", b"\t", quiet=0.08))
        for i in range(3 if quick else 5):
            if want("focus.prev"):
                add(Step("focus.prev", f"shift+tab {i + 1}", "key", ESC + b"[Z", quiet=0.08))
        pts = [(6 + (cols - 12) * i // 11, 4 + (rows - 8) * ((i * 5) % 7) // 6) for i in range(12 if quick else 24)]
        if want("hover.move"):
            for x, y in pts:
                add(Step("hover.move", f"{x},{y}", "key", _move(x, y), quiet=0.06, timeout=1.5))
        if want("click"):   # clicks stay right of the nav column: its bottom row is the Quit button
            for i in range(3 if quick else 5):
                x, y = int(cols * (0.4 + 0.1 * i)), 6 + 5 * i
                add(Step("click", f"{x},{y}", "key", _click(x, y), quiet=0.15))
            add(_setup("Components"))   # a click may have moved us elsewhere
    if want("scroll.step", "scroll.burst", "scroll.page"):
        add(_setup("Scrolling"))
        for i in range(4 if quick else 8):
            if want("scroll.step"):
                add(Step("scroll.step", f"tick {i + 1}", "key", _wheel(mx, my), quiet=0.2))
        for i in range(2 if quick else 4):
            if want("scroll.burst"):
                add(Step("scroll.burst", f"burst {i + 1}", "key", _wheel(mx, my, True, 12), quiet=0.3))
        for i in range(3):
            if want("scroll.page"):
                add(Step("scroll.page", f"pgdn {i + 1}", "key", ESC + b"[6~", quiet=0.15))
    if want("palette.open", "palette.type", "palette.close"):
        add(_setup("Home"))
        add(Step("palette.open", "ctrl+p", "key", b"\x10", quiet=0.15))
        for ch in "set":
            add(Step("palette.type", ch, "key", ch.encode(), quiet=0.1))
        add(Step("palette.close", "esc", "key", ESC, quiet=0.2))
    if want("theme.first", "theme.again"):
        add(_setup("Settings"))
        for lap, group in enumerate(("theme.first", "theme.again")):
            if want(group):
                for label in THEME_BUTTONS:
                    add(Step(group, label, "click_text", label, quiet=0.2, timeout=8.0))
        add(_setup("Home"))
    if want("resize"):
        for r, c in ((max(20, rows - 6), max(70, cols - 24)), (rows + 8, cols + 30), (rows, cols)):
            add(Step("resize", f"{c}x{r}", "resize", (r, c), quiet=0.3, timeout=8.0))
    if want("idle"):
        add(_setup("Home"))
        add(Step("idle", "3 s", "idle", 1.5 if quick else 3.0, all_work=False))
    if wanted is None:
        add(Step("shutdown", "ctrl+q", "key", b"\x11", quiet=0.05, timeout=8.0, all_work=True))
    return S
