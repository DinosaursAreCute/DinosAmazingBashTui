"""Scenarios for the tools/compare apps (4 pages: Buttons, Form, Data, Layout). Click coordinates are 1-based terminal cells."""
from harness.expect import regex
from harness.keys import DOWN, PGDN, chars, click
from harness.scenario import scenario

READY = "Page 1: Buttons"


def nav(i):
    """Menu button i (1..4); both apps draw them on rows 2..5 of the menu pane."""
    return click(5, 1 + i)


def go(c, name, page, label):
    c.step(name, nav(page), label)


@scenario("session", ready=READY, default_apps=("dabt", "textual"), title="Full scripted session: navigation, clicks, typing, list scrolling, resize, idle, memory")
def session(c):
    rows, cols = c.rows, c.cols
    go(c, "nav.form", 2, "Page 2: Form")
    go(c, "nav.data", 3, "Page 3: Data")
    go(c, "nav.layout", 4, "Page 4: Layout")
    go(c, "nav.buttons", 1, "Page 1: Buttons")
    go(c, "nav.revisit", 2, "Page 2: Form")
    go(c, "nav.revisit2", 1, "Page 1: Buttons")
    c.step("click.button", click(35, 6), "Clicks: 1")
    go(c, "nav.form2", 2, "Page 2: Form")
    c.step("click.focus_input", click(40, 4))
    c.step("type.char", b"A", regex(r"Name:\s*A"))
    c.step("type.word", chars("lice"), regex(r"Name:\s*Alice"), gap_ms=60)
    c.step("click.submit", click(35, 9), "Hello, Alice", snap=True)
    go(c, "nav.data2", 3, "Page 3: Data")
    c.step("click.list", click(34, 4))
    c.step("key.down", DOWN, "Selected: Item 02")
    c.step("key.down_held", [DOWN] * 10, "Selected: Item 12", gap_ms=33)  # a held key repeats about every 33 ms
    c.step("key.pagedown", PGDN, snap=True)
    go(c, "nav.layout2", 4, "Page 4: Layout")
    c.step("click.advance", click(82, 4), "Progress: 10%")
    c.step("resize.small", resize=(max(rows - 5, 20), max(cols - 30, 60)))
    c.step("resize.back", resize=(rows, cols), snap=True)
    c.idle("idle.3s", 3)
    c.memory("memory")


@scenario("quick", ready=READY, default_apps=("dabt", "textual"), title="Short smoke run: three page switches, one click, one list key, memory")
def quick(c):
    go(c, "nav.form", 2, "Page 2: Form")
    go(c, "nav.data", 3, "Page 3: Data")
    c.step("click.list", click(34, 4))
    c.step("key.down", DOWN, "Selected: Item 02")
    go(c, "nav.buttons", 1, "Page 1: Buttons")
    c.step("click.button", click(35, 6), "Clicks: 1")
    c.memory("memory")
