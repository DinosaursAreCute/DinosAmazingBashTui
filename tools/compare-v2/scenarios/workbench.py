"""The workbench benchmark: five pages (Overview, Tasks, Notes, Logs, Settings) exercising a timer-driven progress animation, a filtered
table with detail pane and confirm dialog, a markdown editor with live preview, a 2000-line list and a form. Spec: apps/workbench/SPEC.md.
Everything after the page switches is keyboard driven, so both apps need no pixel-exact layout."""
import os
import sys

from harness.expect import absent, regex, text, where
from harness.keys import CTRL_HOME, DOWN, END, ENTER, HOME, PGDN, alt, chars, click, ctrl, wheel
from harness.scenario import scenario

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "apps", "workbench", "data"))
from gen import filter_count, make_tasks  # noqa: E402

NOTES_WORDS = len(open(os.path.join(os.path.dirname(__file__), "..", "apps", "workbench", "data", "notes.md")).read().split())
# Human input timing. A harness must not deliver input faster than a person can: one write of many keys is a backlog, not a use case.
HELD_KEY_MS = 33   # auto-repeat of a held key (about 30 per second)
TYPING_MS = 60     # a brisk typist (about 200 characters per minute)
WHEEL_MS = 25      # notches of one wheel flick
PAGES = ("overview", "tasks", "notes", "logs", "settings", "admin")
ARRIVE = {"overview": "Page 1: Overview", "tasks": "Rows: 200/200", "notes": regex(r"Version 2\.4 brings a faster renderer"), "logs": "Lines: 2000", "settings": "Page 5: Settings", "admin": "Page 6: Admin"}


TASKS = make_tasks()


def selected(n):
    """The cursor is on task n AND the whole detail pane shows it (DABT updates the labels one after another)."""
    return text(f"Selected: T-{n:04d}") & text(f"Title: {TASKS[n - 1][1]}") & text(f"Status: {TASKS[n - 1][3]}")


def go(c, name, page, arrive=None):
    c.step(name, click(5, 2 + PAGES.index(page)), arrive or ARRIVE[page])


@scenario("workbench", ready="Page 1: Overview", title="Workbench: animation, filtered table + dialog, markdown editor, 2000-line list, form", apps=("wb-dabt", "wb-dabt-plain", "wb-textual"), default_apps=("wb-dabt", "wb-textual"))
def workbench(c):
    rows, cols = c.rows, c.cols
    # -- overview: timer-driven progress ----------------------------------------------------------------
    c.step("jobs.run", alt("s"), text("Jobs: done") & text("All jobs finished"), timeout=10, snap=True)  # first_paint = the button's feedback
    c.step("jobs.reset", alt("r"), "Jobs: idle")
    # -- tasks -------------------------------------------------------------------------------------------
    go(c, "nav.tasks", "tasks")
    c.step("table.down", DOWN, selected(2))
    c.step("table.down_held", [DOWN] * 10, selected(12), gap_ms=HELD_KEY_MS)
    c.step("table.pagedown", PGDN, regex(r"Selected: T-00(1[3-9]|[2-9]\d)"))
    c.step("table.top", HOME if c.app.name.startswith("wb-dabt") else CTRL_HOME, selected(1))  # each framework's own key for "first row"
    c.step("focus.filter", alt("i"))
    for i, ch in enumerate("cache"):
        typed = "cache"[:i + 1]  # the count alone stops changing after "ca": the typed text must show too
        c.step("filter.char", ch.encode(), text(f"Rows: {filter_count(typed)}/200") & regex(r"Filter:\s*" + typed + r"(?![a-z])"))
    c.step("focus.table2", alt("t"), snap=True)
    c.step("dialog.open", alt("d"), "Delete T-0006?")
    c.step("dialog.confirm", b"y", text("Deleted T-0006") & text("Rows: 35/199"))
    c.step("focus.filter2", alt("i"))
    c.step("filter.clear", ctrl("u"), "Rows: 199/199")
    # -- notes -------------------------------------------------------------------------------------------
    go(c, "nav.notes", "notes")
    for i, word in enumerate(("alpha", "beta", "gamma")):
        c.step("editor.word", chars(word + " "), text(f"Words: {NOTES_WORDS + i + 1}") & where(lambda v, w=word: v.text.count(w) >= 2, f"{word!r} in editor and preview"), gap_ms=TYPING_MS, snap=(i == 2))
    # -- logs --------------------------------------------------------------------------------------------
    go(c, "nav.logs", "logs")
    c.step("list.pagedown", PGDN, regex(r"Line: ([2-9]|\d\d+)\b"))
    c.step("list.end", END, text("Line: 2000") & text("event number 2000"))
    c.step("list.append", alt("a"), "Lines: 2200")
    c.step("list.home", HOME, regex(r"Line: 1\b") & regex(r"svc-1 event number 1(?!\d)"))
    c.step("list.wheel", [wheel(60, 20, up=False)] * 5, gap_ms=WHEEL_MS)
    c.step("resize.small", resize=(max(rows - 5, 20), max(cols - 30, 60)))
    c.step("resize.back", resize=(rows, cols), snap=True)
    # -- settings ----------------------------------------------------------------------------------------
    go(c, "nav.settings", "settings")
    c.step("form.type", chars("Ada"), regex(r"Name:\s*Ada"), gap_ms=TYPING_MS)
    c.step("form.apply", alt("p"), text("Saved: name=Ada level=info flags=100") & text("Settings saved"))
    # -- admin: tabs, collapsible sections, theme switch, command palette ----------------------------------
    go(c, "nav.admin", "admin")
    c.step("tab.appearance", alt("v"), "Tab: Appearance")
    c.step("tab.general", alt("g"), "Tab: General")
    c.step("collapse.close", alt("z"), absent("Network: 3 interfaces up"))
    c.step("collapse.open", alt("z"), "Network: 3 interfaces up")
    c.step("theme.light", alt("m"), "Theme: light", timeout=15, snap=True)
    c.step("theme.dark", alt("m"), "Theme: dark", timeout=15)
    c.step("palette.open", ctrl("p"), text("Command palette") | text("Search for commands"))
    c.step("palette.type", chars("logs"), "logs", gap_ms=TYPING_MS)
    c.step("palette.run", ENTER, "Lines: 2200", timeout=15)
    # -- revisit: every page again (DABT: page cache; Textual: screen rebuild) ----------------------------
    for page in ("overview", "tasks", "notes", "settings", "admin"):
        go(c, f"revisit.{page}", page, {"tasks": "Rows: 199/199"}.get(page))
    c.pause(5)  # untimed: DABT's background page-cache rebuild after the theme switch has to finish, or "idle" measures that work
    c.idle("idle.3s", 3)
    c.memory("memory")
