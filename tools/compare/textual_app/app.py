"""Textual side of the comparison: the same four pages as tools/compare/dabt_app.

Pages (menu clicks): Buttons, Form, Data, Layout. Fixed text, plain borders, no clocks or blinking cursors,
so an idle app writes nothing to the terminal (the harness relies on that to find the end of a frame).
"""

from textual.app import App, ComposeResult
from textual.containers import Horizontal, Vertical
from textual.screen import Screen
from textual.widgets import Button, Checkbox, DataTable, Input, Label, ListItem, ListView, ProgressBar, Static

CSS = """
Screen { layout: horizontal; }
#nav { width: 18%; border: solid white; padding: 0 1; }
#nav Button, .page Button { height: 1; min-width: 0; width: 100%; border: none; padding: 0; content-align: left middle; text-align: left; background: transparent; }
#nav Button:focus, .page Button:focus { text-style: reverse; }
.page { border: solid white; padding: 0 1; }
.page Static, .page Label { height: 1; }
.row { height: 1; }
.row Label { width: 7; }
Input { height: 1; border: none; padding: 0; }
Checkbox { height: 1; border: none; padding: 0; }
ListView { height: 20; border: none; padding: 0; }
ListItem { height: 1; padding: 0; }
DataTable { border: none; height: 1fr; }
ProgressBar { height: 1; }
.panel { border: solid white; padding: 0 1; }
"""

ITEMS = [f"Item {i:02d}" for i in range(1, 41)]
ROWS = [(f"file{i:02d}.txt", f"{i * 3}k", "text") for i in range(1, 13)]


class PageScreen(Screen):
    """Menu on the left, the page's own widgets on the right."""

    def compose(self) -> ComposeResult:
        with Vertical(id="nav"):
            yield Button("  Buttons", id="nav_buttons")
            yield Button("  Form", id="nav_form")
            yield Button("  Data", id="nav_data")
            yield Button("  Layout", id="nav_layout")
            yield Static("")
            yield Button("  Quit", id="nav_quit")
        yield from self.page()

    def on_mount(self) -> None:
        self.query_one("#nav").border_title = "Menu"

    def on_button_pressed(self, event: Button.Pressed) -> None:
        bid = event.button.id or ""
        if bid == "nav_quit":
            self.app.exit()
        elif bid.startswith("nav_"):
            self.app.show(bid[4:])
        else:
            self.page_pressed(bid)

    def page_pressed(self, bid: str) -> None:
        pass


class ButtonsPage(PageScreen):
    def page(self) -> ComposeResult:
        with Vertical(classes="page", id="main"):
            yield Static("Page 1: Buttons")
            yield Static("")
            yield Static(f"Clicks: {self.app.clicks}", id="lbl_clicks")
            yield Static("")
            yield Button("[ Increment ]", id="btn_inc")
            yield Button("[ Decrement ]", id="btn_dec")
            yield Button("[ Reset ]", id="btn_reset")

    def on_mount(self) -> None:
        super().on_mount()
        self.query_one("#main").border_title = "Buttons"

    def page_pressed(self, bid: str) -> None:
        app = self.app
        app.clicks = {"btn_inc": app.clicks + 1, "btn_dec": app.clicks - 1, "btn_reset": 0}.get(bid, app.clicks)
        self.query_one("#lbl_clicks", Static).update(f"Clicks: {app.clicks}")


class FormPage(PageScreen):
    def page(self) -> ComposeResult:
        with Vertical(classes="page", id="main"):
            yield Static("Page 2: Form")
            yield Static("")
            with Horizontal(classes="row"):
                yield Label("Name:")
                yield Input(placeholder="your name", id="inp_name")
            yield Static("")
            yield Checkbox("Subscribe to news", False, id="chk_news")
            yield Checkbox("Dark mode", True, id="chk_dark")
            yield Static("")
            yield Button("[ Submit ]", id="btn_submit")
            yield Static("")
            yield Static("Status: waiting", id="lbl_status")

    def on_mount(self) -> None:
        super().on_mount()
        self.query_one("#main").border_title = "Form"
        self.query_one("#inp_name", Input).cursor_blink = False

    def on_input_submitted(self, event: Input.Submitted) -> None:
        self.submit()

    def page_pressed(self, bid: str) -> None:
        if bid == "btn_submit":
            self.submit()

    def submit(self) -> None:
        name = self.query_one("#inp_name", Input).value or "stranger"
        news = "1" if self.query_one("#chk_news", Checkbox).value else "0"
        dark = "1" if self.query_one("#chk_dark", Checkbox).value else "0"
        self.query_one("#lbl_status", Static).update(f"Hello, {name}! news={news} dark={dark}")


class DataPage(PageScreen):
    def page(self) -> ComposeResult:
        with Horizontal(id="main"):
            with Vertical(classes="panel", id="left"):
                yield Static("Page 3: Data")
                yield Static("")
                yield ListView(*[ListItem(Label(text), name=text) for text in ITEMS], id="lst_items")
                yield Static("Selected: Item 01", id="lbl_sel")
            with Vertical(classes="panel", id="right"):
                yield DataTable(id="tbl_files")

    def on_mount(self) -> None:
        super().on_mount()
        self.query_one("#left").border_title = "List"
        self.query_one("#right").border_title = "Table"
        self.query_one("#left").styles.width = "40%"
        self.query_one("#right").styles.width = "60%"
        table = self.query_one("#tbl_files", DataTable)
        table.add_columns("File", "Size", "Kind")
        table.add_rows(ROWS)

    def on_list_view_highlighted(self, event: ListView.Highlighted) -> None:
        if event.item is not None:
            self.query_one("#lbl_sel", Static).update(f"Selected: {event.item.name}")


class LayoutPage(PageScreen):
    def page(self) -> ComposeResult:
        with Horizontal(id="main"):
            with Vertical(classes="panel", id="left"):
                yield Static("Page 4: Layout")
                yield Static("")
                yield Static("Three panes: one tall,")
                yield Static("two stacked.")
            with Vertical(id="right"):
                with Vertical(classes="panel", id="top"):
                    yield ProgressBar(total=100, show_eta=False, id="prg")
                    yield Static("")
                    yield Button("[ Advance 10% ]", id="btn_adv")
                with Vertical(classes="panel", id="bottom"):
                    yield Static("Progress: 0%", id="lbl_stat")

    def on_mount(self) -> None:
        super().on_mount()
        self.query_one("#left").border_title = "Info"
        self.query_one("#top").border_title = "Progress"
        self.query_one("#bottom").border_title = "Status"
        self.query_one("#left").styles.width = "40%"
        self.query_one("#right").styles.width = "60%"
        self.query_one("#prg", ProgressBar).update(progress=self.app.progress)

    def page_pressed(self, bid: str) -> None:
        if bid != "btn_adv":
            return
        app = self.app
        app.progress = 0 if app.progress >= 100 else app.progress + 10
        self.query_one("#prg", ProgressBar).update(progress=app.progress)
        self.query_one("#lbl_stat", Static).update(f"Progress: {app.progress}%")


PAGES = {"buttons": ButtonsPage, "form": FormPage, "data": DataPage, "layout": LayoutPage}


class CompareApp(App):
    CSS = CSS

    def __init__(self) -> None:
        super().__init__()
        self.clicks = 0
        self.progress = 0
        self.current = ""

    def on_mount(self) -> None:
        self.show("buttons")

    def show(self, page: str) -> None:
        if page == self.current:
            return
        self.current = page
        if len(self.screen_stack) > 1:
            self.switch_screen(PAGES[page]())
        else:
            self.push_screen(PAGES[page]())


if __name__ == "__main__":
    CompareApp().run()
