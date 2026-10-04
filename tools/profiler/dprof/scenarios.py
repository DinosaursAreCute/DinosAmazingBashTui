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
# alt+N bindings of the demo's nav template (_templates.xml) (alt+0 is the tenth page)
KEY_PAGE = {"1": "home", "2": "components", "3": "settings", "4": "monitor", "5": "terminal", "6": "scrolling",
            "7": "case_study", "8": "docs", "9": "layout", "0": "widgets"}

# Functions the trace breaks down in full (children, own time, source lines) for a page switch: the report's
# "page-switch floor" section. A call stack that contains one of them is attributed to it, unpruned.
FOCUS_ROOTS = ("tui.goto", "tui.reset_ui", "tui.load_cached", "tui.cache.replay", "_tui_cache_restore",
               "_tui_cache_run_on_visit", "_tui_cache_source", "tui.render", "_tui._draw_pane_buf",
               "_tui._draw_widget_buf", "_tui._render_output_buf", "_tui_overlay.draw_all", "_tui._flush")

REPEAT_S = 0.033        # key repeat of a held key: ~30 per second (X11 default 25/s, macOS/Windows ~30/s)
HELD_BUDGET_MS = 50     # key release to last frame painted
DOWN, UP, LEFT, RIGHT = ESC + b"[B", ESC + b"[A", ESC + b"[D", ESC + b"[C"
HOLD_SECONDS = (0.1, 0.3, 0.6, 1.0)   # how long a finger stays on the key: a tap to a long hold
HOLD_SECONDS_QUICK = (0.1, 0.6)
# (group, title, key there, key back, max repeats (rows to move before the widget ends), preparation): every widget or binding where holding a key
# does something. None = no limit. The preparation is a list of setup labels/keys to reach and focus the widget.
HELD = [
    ("held.nav", "Held Up/Down on the nav bar", DOWN, UP, None, ["Components"]),
    ("held.list", "Held Up/Down on a list", DOWN, UP, 9, ["Widgets", "User:", "\t" * 5]),
    ("held.table", "Held Up/Down on a table", DOWN, UP, 6, ["Widgets", "User:", "\t" * 6]),
    ("held.type", "Held character key in an input", b"a", b"\x7f", None, ["Widgets", "User:"]),
    ("held.cursor", "Held Left/Right in an input", LEFT, RIGHT, None, ["Widgets", "User:"]),
    ("held.tab", "Held Tab (focus cycling)", b"\t", ESC + b"[Z", None, ["Components"]),
    ("held.scroll", "Held Down/Up on a page of widgets (spatial focus)", DOWN, UP, None, ["Scrolling", "@mid"]),
    ("held.page", "Held PgDn/PgUp (queued pane render)", ESC + b"[6~", ESC + b"[5~", None, ["Scrolling"]),
]

GROUP_INFO = {
    # group: (title, kind, budget_ms)  budget = the perceived-instant line for that interaction
    "startup.cold": ("Cold start (empty cache)", "startup", 5000),
    "startup.warm": ("Warm start", "startup", 1000),
    "nav.first": ("Page switch, first visit", "nav", 150),
    "nav.revisit": ("Page switch, revisit", "nav", 100),
    "nav.key": ("Page switch by key (alt+1…0, every page)", "nav", 100),
    "nav.floor": ("Page switch, trivial pages (the floor)", "nav", 100),
    "focus.next": ("Focus next (Tab)", "input", 50),
    "focus.prev": ("Focus previous (Shift+Tab)", "input", 50),
    "hover.move": ("Mouse hover", "input", 30),
    "click": ("Mouse click", "input", 100),
    "scroll.step": ("Wheel scroll, single", "input", 60),
    "scroll.burst": ("Wheel scroll, burst", "input", 150),
    "scroll.page": ("Page Down", "input", 100),
    # a held key repeats at ~30/s (REPEAT_S). "done" = last repeat sent to the last frame painted: the lag the user sees
    # trailing behind their finger after releasing the key. A repeat interval plus a frame still reads as instant.
    **{group: (title, "held", HELD_BUDGET_MS) for group, title, *_ in HELD},
    "palette.open": ("Command palette open", "input", 100),
    "palette.type": ("Command palette typing", "input", 50),
    "palette.close": ("Command palette close", "input", 100),
    "theme.first": ("Theme switch, first use", "nav", 250),
    "theme.again": ("Theme switch, repeat", "nav", 150),
    # the Compose demo page: every change goes through an addon file and tui.page.refresh, so it gets the budget of a page
    # switch. "done" is click to the changed panes on screen.
    "compose.open": ("Compose page, open by command palette", "nav", 150),
    "compose.add": ("Compose: add a task card (template + <if>, tui.page.refresh)", "nav", 100),
    "compose.tab": ("Compose: switch tab (whole view swapped by tui.page.refresh)", "nav", 100),
    "compose.cond": ("Compose: change a conditional (environment, tui.page.refresh)", "nav", 100),
    "compose.addons": ("Compose: apply 5 example addons (tui.page.refresh)", "nav", 100),
    # the v2 pages: Workspace (fused panes, resizable dividers, collapsible Services pane), the page-state store, the scrolling form
    "workspace.open": ("Workspace page, first visit", "nav", 150),
    "workspace.hover_handle": ("Workspace: pointer onto / off a divider (hover repaint)", "input", 30),
    "workspace.drag": ("Workspace: divider drag, one pointer step (press, 12 moves, release)", "input", 60),
    "workspace.resize_key": ("Workspace: keyboard resize (alt+r, arrows, shift+arrow, Enter)", "input", 60),
    "workspace.collapse_click": ("Workspace: collapse / expand Services by its button", "input", 100),
    "workspace.collapse_key": ("Workspace: collapse / expand Services by alt+c", "input", 100),
    "workspace.tick": ("Workspace: idle 3 s while the log streams (tui.every refreshes)", "idle", 0),
    "state.plain_goto": ("Page switch without kept state (Monitor and back)", "nav", 100),
    "state.save_restore": ("Page switch with a kept input (Widgets and back: save, rebuild, restore)", "nav", 150),
    "state.reset": ("Reset the page layout (alt+shift+r after a resize and a collapse)", "input", 100),
    "scrollform.tab": ("Scroll form: Tab to the next field (scroll_into_view)", "input", 50),
    "scrollform.wheel": ("Scroll form: wheel over a widget", "input", 60),
    "scrollform.pgdn": ("Scroll form: Page Down", "input", 100),
    "scrollform.click": ("Scroll form: click after scrolling", "input", 100),
    "resize": ("Terminal resize", "resize", 250),
    "idle": ("Idle (3 s, nothing happening)", "idle", 0),
    "shutdown": ("Quit", "shutdown", 500),
}


class Step:
    def __init__(self, group, detail, kind, payload=None, quiet=0.12, timeout=6.0, all_work=False, expect=None):
        self.group, self.detail, self.kind, self.payload = group, detail, kind, payload
        self.quiet, self.timeout, self.all_work = quiet, timeout, all_work
        self.expect = expect   # text that must be on screen after the step, or the step is reported as failed
        self.wait = 0.5  # traced runs: fixed wait, set from the untraced medians (see runner)

    def describe(self):
        return f"{self.group} · {self.detail}"


def _pointer(needle, code, dx=0, dy=0, gap=0.03):
    """Payload of a "pointer" step: one mouse event (code: m move, p press, d drag, r release, w/W wheel down/up) placed at
    (dx, dy) cells from the first character of NEEDLE on screen, which is found when the step runs."""
    return (needle, [(code, dx, dy)], gap)


def _move(x, y):
    return b"\x1b[<35;%d;%dM" % (x, y)


def _click(x, y):
    return b"\x1b[<0;%d;%dM\x1b[<0;%d;%dm" % (x, y, x, y)


def _wheel(x, y, down=True, n=1):
    return (b"\x1b[<%d;%d;%dM" % (65 if down else 64, x, y)) * n


# Scenario presets: what `--scenario` selects. `groups=None` means everything. Steps the chosen groups
# need as preparation (navigate to a page, return to the start page) run too but are labelled "setup" and not reported.
SCENARIOS = [
    ("full", "Everything: start, navigation, input, scrolling, palette, themes, resize, idle, quit", None),
    ("startup", "Cold start (empty cache) and warm start", {"startup.cold", "startup.warm"}),
    ("nav", "Page navigation: first visit, revisit, key binding", {"nav.first", "nav.revisit", "nav.key"}),
    ("floor", "Warm switches between the three lightest pages, repeated: what a page switch costs with no page code (read the \"Page-switch floor\" section of the trace)", {"nav.floor"}),
    ("input", "Focus, hover and click", {"focus.next", "focus.prev", "hover.move", "click"}),
    ("scroll", "Wheel, burst and Page Down scrolling", {"scroll.step", "scroll.burst", "scroll.page"}),
    ("held", "Held keys at the real repeat rate (~30/s): arrows on nav bar, list, table, inputs, scrolling; Tab. Measures key release to last frame", {h[0] for h in HELD}),
    ("palette", "Command palette open, typing, close", {"palette.open", "palette.type", "palette.close"}),
    ("theme", "Theme switching on the Settings page", {"theme.first", "theme.again"}),
    ("resize", "Terminal resize", {"resize"}),
    ("compose", "Compose demo page: open it, add a task, switch tabs, change a conditional, apply the five example addons (tui.page.refresh: only the changed panes are rebuilt)", {"compose.open", "compose.add", "compose.tab", "compose.cond", "compose.addons"}),
    ("workspace", "Workspace demo page: first visit, hover and drag of the resize dividers, keyboard resize, collapsing the Services pane by button and alt+c, the page's tui.every ticks", {g for g in GROUP_INFO if g.startswith("workspace.")}),
    ("state", "Page-state store (keep_value): a page switch with a kept input vs. a plain switch, and alt+shift+r reset on the Workspace page", {"state.plain_goto", "state.save_restore", "state.reset"}),
    ("scrollform", "Scrolling demo's form (scroll='v' pane): Tab through every field, wheel over a widget, Page Down, click after scrolling", {g for g in GROUP_INFO if g.startswith("scrollform.")}),
    ("idle", "Idle: what the app does when nothing happens", {"idle"}),
]
SCENARIO_NAMES = [n for n, _, _ in SCENARIOS]
FLOOR_LAPS = ["Layout", "Case Study", "Debug"]   # nav labels of the trivial pages (no on_visit work)
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


def _palette_goto(word):
    """Setup steps that reach a page the nav does not list: ctrl+p, the first letters of its command, but not Enter
    (the caller sends Enter as the measured step)."""
    S = [Step("setup", "palette", "key", b"\x10", quiet=0.2)]
    S += [Step("setup", f"type {ch}", "key", ch.encode(), quiet=0.08) for ch in word]
    return S


def _fill(label, value):
    """Setup steps that put VALUE into the input labelled LABEL: click it, go to the end, erase, type."""
    S = [_setup(label), Step("setup", f"end {label}", "key", ESC + b"[F", quiet=0.08),
         Step("setup", f"clear {label}", "key", b"\x7f" * 8, quiet=0.1)]
    S += [Step("setup", f"{label} {ch}", "key", ch.encode(), quiet=0.06) for ch in str(value)]
    return S


# Needles that find the demo's own labels on screen (the profiler clicks the text it sees)
ADDON_BOXES = ["banner  - prepend", "toolbar - append", "retitle - set", "shout   - set", "tidy    - remove"]
APPLY = "[ Apply and rebuild"
ADD_TASK = "[ Add task"
REMOVE_TASK = "[ Remove last"
CYCLE_ENV = "[ Cycle environment"


WORKSPACE_GROUPS = ["workspace.open", "workspace.hover_handle", "workspace.drag", "workspace.resize_key",
                    "workspace.collapse_click", "workspace.collapse_key", "workspace.tick"]
STATE_GROUPS = ["state.plain_goto", "state.save_restore", "state.reset"]
SCROLLFORM_GROUPS = ["scrollform.tab", "scrollform.wheel", "scrollform.pgdn", "scrollform.click"]
# Needles on the Workspace page: pane titles locate the dividers (a fused border is the next pane's title row; a column border
# is two cells left of the next pane's title), the collapse buttons are the glyphs the Services pane draws (◀ open, ▶ collapsed)
WS_LIST = "api-gateway"
WS_EVENTS, WS_LOGS = "Events", "Logs"
WS_COLLAPSE, WS_EXPAND = "◀", "▶"
KEEP_PAGE, KEEP_LABEL, KEEP_VALUE = "Widgets", "User:", "keepme42"   # widgets.xml: wx_user has keep_value="true"
ALT_R, ALT_SHIFT_R, ALT_C = ESC + b"r", ESC + b"R", ESC + b"c"


def _workspace_steps(want, quick):
    """The Workspace page (share/demo/workspace.xml). Order: open, hover, drags, keyboard resize, collapse by button and key, idle."""
    S = []
    add = S.append
    if want("workspace.open"):
        add(Step("workspace.open", "click", "click_text", "Workspace", quiet=0.4, timeout=8.0, expect="Services"))
    else:
        add(Step("setup", "Workspace", "click_text", "Workspace", quiet=0.4, timeout=8.0))
    add(Step("setup", "workspace settles", "idle", 0.5))
    if want("workspace.hover_handle"):
        for i in range(3 if quick else 5):
            add(Step("workspace.hover_handle", f"onto divider {i + 1}", "pointer", _pointer(WS_EVENTS, "m", 12, 0), quiet=0.08, timeout=1.5))
            add(Step("workspace.hover_handle", f"off divider {i + 1}", "pointer", _pointer(WS_EVENTS, "m", 12, 4), quiet=0.08, timeout=1.5))
    if want("workspace.drag"):
        # the title the divider sits next to moves with it, so every step is placed one cell beyond where the divider is now
        for name, needle, dx, dy, mx, my in (("logs/events", WS_EVENTS, 12, 0, 0, 1), ("services/logs", WS_LOGS, -3, 2, 1, 0)):
            add(Step("workspace.drag", f"{name} press", "pointer", _pointer(needle, "p", dx, dy), quiet=0.08, timeout=3.0))
            for k in range(12):
                add(Step("workspace.drag", f"{name} move {k + 1}", "pointer", _pointer(needle, "d", dx + mx, dy + my), quiet=0.08, timeout=3.0))
            add(Step("workspace.drag", f"{name} release", "pointer", _pointer(needle, "r", dx, dy), quiet=0.1, timeout=3.0))
    if want("workspace.resize_key"):
        add(_setup(WS_LIST))   # focus inside the resizable Services pane
        add(Step("workspace.resize_key", "alt+r", "key", ALT_R, quiet=0.1, timeout=3.0))
        for i in range(5):
            add(Step("workspace.resize_key", f"right {i + 1}", "key", ESC + b"[C", quiet=0.08, timeout=3.0))
        add(Step("workspace.resize_key", "shift+right", "key", ESC + b"[1;2C", quiet=0.1, timeout=3.0))
        add(Step("workspace.resize_key", "enter", "key", b"\r", quiet=0.1, timeout=3.0))
    if want("workspace.collapse_click"):
        add(Step("workspace.collapse_click", "collapse", "click_text", WS_COLLAPSE, quiet=0.2, timeout=5.0))
        add(Step("workspace.collapse_click", "expand", "click_text", WS_EXPAND, quiet=0.2, timeout=5.0))
    if want("workspace.collapse_key"):
        add(_setup(WS_LIST))
        add(Step("workspace.collapse_key", "alt+c collapse", "key", ALT_C, quiet=0.2, timeout=5.0))
        add(Step("workspace.collapse_key", "alt+c expand", "key", ALT_C, quiet=0.2, timeout=5.0))
    if want("workspace.tick"):
        add(Step("workspace.tick", "3 s", "idle", 1.5 if quick else 3.0))
    return S


def _state_steps(want, quick):
    """keep_value round trip (Widgets, with the User input kept) next to a plain switch, then the page reset on Workspace."""
    S = []
    add = S.append
    laps = 2 if quick else 4
    if want("state.plain_goto", "state.save_restore"):
        add(_setup("Monitor"))
        for i in range(laps):
            add(Step("state.plain_goto", f"lap {i + 1} components", "click_text", "Components", quiet=0.15))
            add(Step("state.plain_goto", f"lap {i + 1} monitor", "click_text", "Monitor", quiet=0.15))
    if want("state.save_restore"):
        add(_setup(KEEP_PAGE))
        S.extend(_fill(KEEP_LABEL, KEEP_VALUE))
        for i in range(laps):
            add(Step("state.save_restore", f"lap {i + 1} away (save)", "click_text", "Components", quiet=0.15))
            add(Step("state.save_restore", f"lap {i + 1} back (restore)", "click_text", KEEP_PAGE, quiet=0.15, expect=KEEP_VALUE))
    if want("state.reset"):
        add(_setup("Workspace"))
        add(Step("setup", "workspace settles", "idle", 0.5))
        add(_setup(WS_LIST))
        add(Step("setup", "alt+r", "key", ALT_R, quiet=0.1))
        for i in range(3):
            add(Step("setup", f"right {i + 1}", "key", ESC + b"[C", quiet=0.08))
        add(Step("setup", "enter", "key", b"\r", quiet=0.1))
        add(Step("setup", "collapse", "click_text", WS_COLLAPSE, quiet=0.2))
        add(Step("state.reset", "alt+shift+r", "key", ALT_SHIFT_R, quiet=0.2, timeout=5.0))
    return S


def _scrollform_steps(want, quick):
    """The form on the Scrolling page: a scroll='v' pane of 7 inputs, a select, 4 checkboxes, 5 inputs and a list."""
    S = []
    add = S.append
    add(_setup("Scrolling"))
    add(Step("setup", "scroll data loads", "idle", 0.5))
    add(_setup("First name:"))   # focus the first field
    if want("scrollform.tab"):
        for i in range(8 if quick else 18):
            add(Step("scrollform.tab", f"tab {i + 1}", "key", b"\t", quiet=0.08))
    if want("scrollform.wheel"):
        for i in range(2 if quick else 4):
            add(Step("scrollform.wheel", f"up {i + 1}", "pointer", _pointer("Last name:", "W", 4, 0), quiet=0.15, timeout=3.0))
        for i in range(2 if quick else 4):
            add(Step("scrollform.wheel", f"down {i + 1}", "pointer", _pointer("Last name:", "w", 4, 0), quiet=0.15, timeout=3.0))
    if want("scrollform.pgdn"):
        for i in range(3):
            add(Step("scrollform.pgdn", f"pgdn {i + 1}", "key", ESC + b"[6~", quiet=0.15))
    if want("scrollform.click"):
        for label in ("Last name:", "Email:", "Phone:"):
            add(Step("scrollform.click", label, "click_text", label, quiet=0.15, timeout=4.0))
    return S


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
                add(Step(group, "components", "click_text", "Components", quiet=0.15))   # back to the start page
        if want("nav.key"):
            # alt+1..9 and alt+0 are bound in the nav template (_templates.xml): every page once by key, so the median is over all pages and each
            # can be compared with clicking the same page (nav.first/nav.revisit details). The run before ends on the start page (components), so
            # the sequence starts at alt+1 (alt+2 would be a switch to the page already shown) and ends with alt+2.
            keys = ("1", "7") if quick else ("1", "3", "4", "5", "6", "7", "8", "9", "0", "2")
            for k in keys:
                add(Step("nav.key", f"alt+{k} {KEY_PAGE[k]}", "key", ESC + k.encode(), quiet=0.15, timeout=1.0))
    if want("nav.floor"):
        # layout, case study and debug carry no on_visit work: every millisecond here is the framework. One priming lap
        # (labelled setup, not reported) takes the first-visit costs out; the measured laps are all warm switches.
        for label in FLOOR_LAPS:
            add(_setup(label))
        for lap in range(3 if quick else 10):
            for label in FLOOR_LAPS:
                add(Step("nav.floor", f"lap {lap + 1} {label.lower()}", "click_text", label, quiet=0.15))
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
    for group, _title, there, back, count, prep in HELD:
        if not want(group):
            continue
        for label in prep:
            if label == "@mid":
                add(Step("setup", "focus pane", "key", _click(mx, my), quiet=0.15))
            elif label.startswith("\t"):
                for i in range(len(label)):   # one Tab per step: five in one write would be coalesced into fewer moves
                    add(Step("setup", f"tab {i + 1}", "key", b"\t", quiet=0.08))
            else:
                add(_setup(label))
        for secs in (HOLD_SECONDS_QUICK if quick else HOLD_SECONDS):
            n = 1 + int(secs / REPEAT_S)   # the first press lands at once, then one per repeat interval
            if count:
                n = min(n, count)
            add(Step(group, f"{secs:g}s hold", "repeat", (there, n, REPEAT_S), quiet=0.1, timeout=8.0))
            add(Step(group, f"{secs:g}s back", "repeat", (back, n, REPEAT_S), quiet=0.1, timeout=8.0))
        add(_setup("Components"))
    if want("palette.open", "palette.type", "palette.close"):
        add(_setup("Components"))
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
        add(_setup("Components"))
    if want("compose.open", "compose.add", "compose.tab", "compose.cond", "compose.addons"):
        add(Step("setup", "close dialogs", "key", ESC, quiet=0.1))   # an earlier step may have left a dialog open; it would swallow every key below
        S.extend(_palette_goto("Compose"))
        if want("compose.open"):
            add(Step("compose.open", "palette", "key", b"\r", quiet=0.4, timeout=8.0, expect=ADD_TASK))
        else:
            add(Step("setup", "open Compose", "key", b"\r", quiet=0.4, timeout=8.0, expect=ADD_TASK))
        if want("compose.add"):
            S.extend(_fill("Title:", "Review"))
            add(Step("compose.add", "new task", "click_text", ADD_TASK, quiet=0.3, timeout=10.0))
            add(_setup(REMOVE_TASK))   # leave the board as found
        if want("compose.cond", "compose.tab", "compose.addons"):
            add(Step("compose.tab" if want("compose.tab") else "setup", "conditionals", "click_text", "Conditionals", quiet=0.3, timeout=10.0))
            if want("compose.cond"):
                for i in range(3):   # dev -> staging -> prod -> dev
                    add(Step("compose.cond", f"environment {i + 1}", "click_text", CYCLE_ENV, quiet=0.3, timeout=10.0))
            if want("compose.addons"):
                add(Step("compose.tab" if want("compose.tab") else "setup", "addons", "click_text", "Addons", quiet=0.3, timeout=10.0))
                for needle in ADDON_BOXES:
                    add(_setup(needle))
                add(Step("compose.addons", "all five", "click_text", APPLY, quiet=0.3, timeout=10.0))
                for needle in ADDON_BOXES:   # leave the page as found: every addon off
                    add(_setup(needle))
                add(Step("setup", "apply none", "click_text", APPLY, quiet=0.3, timeout=10.0))
            if want("compose.tab"):
                add(Step("compose.tab", "board", "click_text", "Board", quiet=0.3, timeout=10.0))
        add(Step("setup", "cache refresh ends", "idle", 1.0))   # the quiet rebuild of the cached page runs in the background
        add(_setup("Components"))
    if want(*WORKSPACE_GROUPS):
        S.extend(_workspace_steps(want, quick))
    if want("state.plain_goto", "state.save_restore", "state.reset"):
        S.extend(_state_steps(want, quick))
    if want(*SCROLLFORM_GROUPS):
        S.extend(_scrollform_steps(want, quick))
    if want("resize"):
        for r, c in ((max(20, rows - 6), max(70, cols - 24)), (rows + 8, cols + 30), (rows, cols)):
            add(Step("resize", f"{c}x{r}", "resize", (r, c), quiet=0.3, timeout=8.0))
    if want("idle"):
        add(_setup("Components"))
        add(Step("idle", "3 s", "idle", 1.5 if quick else 3.0, all_work=False))
    if wanted is None:
        add(Step("shutdown", "ctrl+q", "key", b"\x11", quiet=0.05, timeout=8.0, all_work=True))
    return S


class Unit:
    """One independent profiling unit: a fresh app started from the same warmed cache on the default page, then its steps.
    The steps are `setup` steps (navigate to the page, put it in its start state; not measured) followed by the
    measured ones. Units share nothing, so they can run side by side."""

    def __init__(self, name, groups, steps):
        self.name, self.groups, self.steps = name, set(groups), steps


DEFAULT_PAGE = "Components"   # nav label of the page the profiled demo opens on (DABT_DEMO_PAGE, see session.py): Home is the heaviest page and has no menu


# Which groups share a start state. Every group is in exactly one unit; startup.* is measured on its own (see runner).
UNIT_GROUPS = [
    ("nav", ["nav.first", "nav.revisit", "nav.key"]),
    ("floor", ["nav.floor"]),
    ("input", ["focus.next", "focus.prev", "hover.move", "click"]),
    ("scroll", ["scroll.step", "scroll.burst", "scroll.page"]),
] + [(h[0], [h[0]]) for h in HELD] + [
    ("palette", ["palette.open", "palette.type", "palette.close"]),
    ("theme", ["theme.first", "theme.again"]),
    ("compose", ["compose.open", "compose.add", "compose.tab", "compose.cond", "compose.addons"]),
    ("workspace", WORKSPACE_GROUPS),
    ("state", STATE_GROUPS),
    ("scrollform", SCROLLFORM_GROUPS),
    ("resize", ["resize"]),
    ("idle", ["idle"]),
    ("shutdown", ["shutdown"]),
]


def units(rows, cols, quick=False, wanted=None):
    """The units a run needs for the wanted groups (None = all), in a fixed order."""
    out = []
    for name, groups in UNIT_GROUPS:
        gs = set(groups) if wanted is None else set(groups) & wanted
        if not gs:
            continue
        if name == "shutdown":
            steps = [Step("shutdown", "ctrl+q", "key", b"\x11", quiet=0.05, timeout=8.0, all_work=True)]
        else:
            steps = interaction_steps(rows, cols, quick, gs)
            while steps and steps[0].group == "setup" and steps[0].detail == DEFAULT_PAGE:   # the unit already starts there
                steps.pop(0)
            while steps and steps[-1].group == "setup":   # putting the page back is for the next step of one long run; a unit just ends
                steps.pop()
        out.append(Unit(name, gs, steps))
    return out
