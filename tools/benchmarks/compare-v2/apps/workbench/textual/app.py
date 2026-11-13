"""Textual side of the workbench benchmark: five pages, behaviour contract in ../SPEC.md.

Written the way a Textual developer would: one Screen per page, built-in widgets (DataTable, Select, TextArea, Markdown,
OptionList, ProgressBar, ModalScreen, Footer, notify), reactive state on the App, set_interval for the job timer.
No cursor blink, no clocks: an idle app writes nothing, which the harness relies on."""
import os
import sys

from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical, VerticalScroll
from textual.screen import ModalScreen, Screen
from textual.app import SystemCommand
from textual.widgets import (Button, Checkbox, Collapsible, DataTable, Footer, Input, Label, Markdown, OptionList, ProgressBar, Select, Static,
                             TabbedContent, TabPane, TextArea)

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "data"))
from gen import logs, make_tasks  # noqa: E402
NOTES = open(os.path.join(HERE, "..", "data", "notes.md")).read()

CSS = """
Screen { layout: horizontal; }
#nav { width: 18%; border: solid white; padding: 0 1; }
#nav Button, .page Button { height: 1; min-width: 0; width: auto; border: none; padding: 0; content-align: left middle; text-align: left; background: transparent; }
#nav Button { width: 100%; }
Button:focus { text-style: reverse; }
.page { border: solid white; padding: 0 1; }
.page Static, .page Label { height: 1; }
.row { height: 1; }
.row Label { width: 8; }
Input { height: 1; border: none; padding: 0; }
Checkbox { height: 1; border: none; padding: 0; }
Select { height: 1; border: none; padding: 0; width: 24; }
SelectCurrent { height: 1; border: none; padding: 0; }
ProgressBar { height: 1; }
Bar { width: 1fr; }
DataTable { border: none; height: 1fr; }
OptionList { border: none; height: 1fr; padding: 0; }
TextArea { border: none; height: 1fr; padding: 0; }
Markdown { padding: 0; }
#dlg { width: 40; height: 5; border: solid white; padding: 0 1; align: center middle; background: $surface; }
ConfirmScreen { align: center middle; layout: vertical; }
"""


def chord(key: str, action: str, description: str) -> Binding:
    """App-level shortcut. Priority, so it also fires while an Input or TextArea has focus (otherwise the widget types the letter)."""
    return Binding(key, action, description, priority=True)


class ConfirmScreen(ModalScreen[bool]):
    BINDINGS = [Binding("y", "answer(True)", "Yes"), Binding("n,escape", "answer(False)", "No")]

    def __init__(self, message: str) -> None:
        super().__init__()
        self.message = message

    def compose(self) -> ComposeResult:
        with Vertical(id="dlg"):
            yield Static(self.message)
            with Horizontal(classes="row"):
                yield Button("[ Yes ]", id="yes")
                yield Button("[ No ]", id="no")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        self.dismiss(event.button.id == "yes")

    def action_answer(self, yes: bool) -> None:
        self.dismiss(yes)


class PageScreen(Screen):
    BINDINGS = [chord("alt+0", "focus_nav", "Menu")] + [chord(f"alt+{i}", f"goto('{p}')", t) for i, (p, t) in enumerate(
        [("overview", "Overview"), ("tasks", "Tasks"), ("notes", "Notes"), ("logs", "Logs"), ("settings", "Settings"), ("admin", "Admin")], 1)]

    def compose(self) -> ComposeResult:
        with Vertical(id="nav"):
            for page, title in (("overview", "Overview"), ("tasks", "Tasks"), ("notes", "Notes"), ("logs", "Logs"), ("settings", "Settings"), ("admin", "Admin")):
                yield Button(f"  {title}", id=f"nav_{page}")
            yield Static("")
            yield Button("  Quit", id="nav_quit")
        yield from self.page()
        yield Footer()

    def on_mount(self) -> None:
        self.query_one("#nav").border_title = "Menu"

    def action_focus_nav(self) -> None:
        self.query_one("#nav_overview").focus()

    def on_key(self, event) -> None:
        """Up/Down move between the menu buttons while one has the focus (Enter then presses it)."""
        f = self.focused
        if f is not None and (f.id or "").startswith("nav_") and event.key in ("up", "down"):
            (self.focus_previous if event.key == "up" else self.focus_next)()
            event.stop()

    def action_goto(self, page: str) -> None:
        self.app.show(page)

    def on_button_pressed(self, event: Button.Pressed) -> None:
        bid = event.button.id or ""
        if bid == "nav_quit":
            self.app.exit()
        elif bid.startswith("nav_"):
            self.app.show(bid[4:])
        else:
            self.pressed(bid)

    def pressed(self, bid: str) -> None:
        pass


class OverviewPage(PageScreen):
    AUTO_FOCUS = "#btn_start"
    BINDINGS = [chord("alt+s", "start", "Start jobs"), chord("alt+r", "reset", "Reset")]

    def page(self) -> ComposeResult:
        with Vertical(classes="page", id="main"):
            yield Static("Page 1: Overview")
            yield Static("")
            for key, label in (("build", "Build: "), ("test", "Test:  "), ("deploy", "Deploy:")):
                with Horizontal(classes="row"):
                    yield Label(label)
                    yield ProgressBar(total=100, show_eta=False, id=f"prg_{key}")
            yield Static("")
            yield Static("Jobs: idle", id="lbl_jobs")
            yield Static("")
            yield Button("[ Start jobs ]", id="btn_start")
            yield Button("[ Reset ]", id="btn_reset")

    def on_mount(self) -> None:
        super().on_mount()
        self.query_one("#main").border_title = "Overview"
        self.show()
        self.timer = self.set_interval(0.1, self.tick, pause=self.app.job_state != "running")

    def show(self) -> None:
        a = self.app
        for key, value in (("build", a.job_b), ("test", a.job_t), ("deploy", a.job_d)):
            self.query_one(f"#prg_{key}", ProgressBar).progress = value
        self.query_one("#lbl_jobs", Static).update(f"Jobs: {a.job_state}")

    def pressed(self, bid: str) -> None:
        if bid == "btn_start":
            self.action_start()
        elif bid == "btn_reset":
            self.action_reset()

    def action_reset(self) -> None:
        self.timer.pause()
        a = self.app
        a.job_b = a.job_t = a.job_d = 0
        a.job_state = "idle"
        self.show()

    def action_start(self) -> None:
        a = self.app
        if a.job_state == "running":
            return
        a.job_b = a.job_t = a.job_d = 0
        a.job_state = "running"
        self.show()
        self.timer.resume()

    def tick(self) -> None:
        a = self.app
        a.job_b, a.job_t, a.job_d = min(100, a.job_b + 10), min(100, a.job_t + 8), min(100, a.job_d + 5)
        if a.job_b == a.job_t == a.job_d == 100:
            self.timer.pause()
            a.job_state = "done"
            a.notify("All jobs finished", severity="information")
        self.show()


class TasksPage(PageScreen):
    AUTO_FOCUS = "#tbl_tasks"
    BINDINGS = [chord("alt+i", "focus_filter", "Filter"), chord("alt+t", "focus_table", "Table"), chord("alt+d", "delete", "Delete")]

    def page(self) -> ComposeResult:
        with Horizontal(id="main"):
            with Vertical(classes="page", id="left"):
                yield Static("Page 2: Tasks")
                yield Static("")
                with Horizontal(classes="row"):
                    yield Label("Filter:")
                    yield Input(placeholder="type to filter", id="inp_filter")
                with Horizontal(classes="row"):
                    yield Label("Status:")
                    yield Select([(s, s) for s in ("all", "open", "done", "blocked")], value="all", allow_blank=False, id="sel_status")
                yield Static("Rows: 0/0", id="lbl_count")
                yield DataTable(id="tbl_tasks", cursor_type="row", zebra_stripes=False)
            with Vertical(classes="page", id="right"):
                yield Static("Selected: -", id="lbl_sel")
                yield Static("")
                yield Static("Title: -", id="lbl_title")
                yield Static("Owner: -", id="lbl_owner")
                yield Static("Status: -", id="lbl_status")
                yield Static("")
                yield Checkbox("Flagged", id="chk_flag")
                yield Static("")
                yield Button("[ Delete ]", id="btn_delete")

    def on_mount(self) -> None:
        super().on_mount()
        self.query_one("#left").border_title = "Tasks"
        self.query_one("#right").border_title = "Detail"
        self.query_one("#left").styles.width = "65%"
        self.query_one("#right").styles.width = "35%"
        self.query_one("#tbl_tasks", DataTable).add_columns("ID", "Title", "Owner", "Status")
        self.refill()

    def refill(self) -> None:
        needle = self.query_one("#inp_filter", Input).value.lower()
        status = self.query_one("#sel_status", Select).value
        rows = [r for r in self.app.tasks
                if (status == "all" or r[3] == status) and (not needle or needle in "|".join(r).lower())]
        table = self.query_one("#tbl_tasks", DataTable)
        table.clear()
        table.add_rows(rows)
        self.query_one("#lbl_count", Static).update(f"Rows: {len(rows)}/{len(self.app.tasks)}")
        if not rows:
            self.detail(None)

    def detail(self, row) -> None:
        id_, title, owner, status = row or ("-", "-", "-", "-")
        self.query_one("#lbl_sel", Static).update(f"Selected: {id_}")
        self.query_one("#lbl_title", Static).update(f"Title: {title}")
        self.query_one("#lbl_owner", Static).update(f"Owner: {owner}")
        self.query_one("#lbl_status", Static).update(f"Status: {status}")

    def on_input_changed(self, event: Input.Changed) -> None:
        self.refill()

    def on_select_changed(self, event: Select.Changed) -> None:
        self.refill()

    def on_data_table_row_highlighted(self, event: DataTable.RowHighlighted) -> None:
        table = self.query_one("#tbl_tasks", DataTable)
        self.detail(table.get_row_at(event.cursor_row) if table.row_count else None)

    def action_focus_filter(self) -> None:
        self.query_one("#inp_filter").focus()

    def action_focus_table(self) -> None:
        self.query_one("#tbl_tasks").focus()

    def pressed(self, bid: str) -> None:
        if bid == "btn_delete":
            self.action_delete()

    def action_delete(self) -> None:
        table = self.query_one("#tbl_tasks", DataTable)
        if not table.row_count:
            return
        task_id = table.get_row_at(table.cursor_row)[0]

        def done(yes: bool | None) -> None:
            if yes:
                self.app.tasks = [r for r in self.app.tasks if r[0] != task_id]
                self.refill()
                self.app.notify(f"Deleted {task_id}", severity="information")

        self.app.push_screen(ConfirmScreen(f"Delete {task_id}?"), done)


class NotesPage(PageScreen):
    AUTO_FOCUS = "#txt_notes"
    BINDINGS = [chord("alt+e", "focus_editor", "Editor")]

    def page(self) -> ComposeResult:
        with Horizontal(id="main"):
            with Vertical(classes="page", id="edit"):
                yield Static("Page 3: Notes")
                yield Static("Words: 0", id="lbl_words")
                yield TextArea(self.app.notes, id="txt_notes")
            with VerticalScroll(classes="page", id="preview"):
                yield Markdown(self.app.notes, id="md")

    def on_mount(self) -> None:
        super().on_mount()
        self.query_one("#edit").border_title = "Editor"
        self.query_one("#preview").border_title = "Preview"
        self.query_one("#lbl_words", Static).update(f"Words: {len(self.app.notes.split())}")

    async def on_text_area_changed(self, event: TextArea.Changed) -> None:
        text = event.text_area.text
        self.app.notes = text
        self.query_one("#lbl_words", Static).update(f"Words: {len(text.split())}")
        await self.query_one("#md", Markdown).update(text)

    def action_focus_editor(self) -> None:
        self.query_one("#txt_notes").focus()


class LogsPage(PageScreen):
    AUTO_FOCUS = "#lst_logs"
    BINDINGS = [chord("alt+a", "append", "Append"), chord("alt+l", "focus_list", "List")]

    def page(self) -> ComposeResult:
        with Vertical(classes="page", id="main"):
            yield Static("Page 4: Logs")
            yield Static("")
            yield Static(f"Lines: {len(self.app.logs)}", id="lbl_lines")
            yield Static("Line: 1", id="lbl_cursor")
            yield Button("[ Append 200 ]", id="btn_append")
            yield OptionList(*self.app.logs, id="lst_logs")

    def on_mount(self) -> None:
        super().on_mount()
        self.query_one("#main").border_title = "Logs"

    def on_option_list_option_highlighted(self, event: OptionList.OptionHighlighted) -> None:
        self.query_one("#lbl_cursor", Static).update(f"Line: {event.option_index + 1}")

    def pressed(self, bid: str) -> None:
        if bid == "btn_append":
            self.action_append()

    def action_append(self) -> None:
        new = self.app.logs[:200]
        self.app.logs.extend(new)
        self.query_one("#lst_logs", OptionList).add_options(new)
        self.query_one("#lbl_lines", Static).update(f"Lines: {len(self.app.logs)}")

    def action_focus_list(self) -> None:
        self.query_one("#lst_logs").focus()


class SettingsPage(PageScreen):
    AUTO_FOCUS = "#inp_name"
    BINDINGS = [chord("alt+n", "focus_name", "Name"), chord("alt+p", "apply", "Apply")]

    def action_focus_name(self) -> None:
        self.query_one("#inp_name").focus()

    def page(self) -> ComposeResult:
        with Vertical(classes="page", id="main"):
            yield Static("Page 5: Settings")
            yield Static("")
            with Horizontal(classes="row"):
                yield Label("Name:")
                yield Input(placeholder="display name", id="inp_name")
            with Horizontal(classes="row"):
                yield Label("Level:")
                yield Select([(s, s) for s in ("info", "warn", "debug")], value="info", allow_blank=False, id="sel_level")
            yield Static("")
            yield Checkbox("Notifications", True, id="chk_a")
            yield Checkbox("Auto-save", False, id="chk_b")
            yield Checkbox("Telemetry", False, id="chk_c")
            yield Static("")
            yield Button("[ Apply ]", id="btn_apply")
            yield Static("")
            yield Static("Saved: nothing yet", id="lbl_saved")

    def on_mount(self) -> None:
        super().on_mount()
        self.query_one("#main").border_title = "Settings"

    def pressed(self, bid: str) -> None:
        if bid == "btn_apply":
            self.action_apply()

    def action_apply(self) -> None:
        name = self.query_one("#inp_name", Input).value or "anonymous"
        level = self.query_one("#sel_level", Select).value
        flags = "".join(str(int(self.query_one(f"#chk_{k}", Checkbox).value)) for k in "abc")
        self.query_one("#lbl_saved", Static).update(f"Saved: name={name} level={level} flags={flags}")
        self.app.notify("Settings saved", severity="information")


class AdminPage(PageScreen):
    BINDINGS = [chord("alt+g", "tab('gen')", "General"), chord("alt+v", "tab('app')", "Appearance"),
                chord("alt+z", "toggle_network", "Network"), chord("alt+m", "theme", "Theme")]

    def page(self) -> ComposeResult:
        with Vertical(id="main"):
            with Vertical(classes="page", id="adm_body"):
                yield Static("Page 6: Admin")
                with TabbedContent(initial="gen", id="tabs"):
                    with TabPane("General", id="gen"):
                        yield Static("Tab: General")
                    with TabPane("Appearance", id="app"):
                        yield Static("Tab: Appearance")
                yield Static(f"Theme: {self.app.theme_name}", id="lbl_theme")
            with Collapsible(title="Network", collapsed=False, id="d_net"):
                yield Static("Network: 3 interfaces up")
            with Collapsible(title="Storage", collapsed=True, id="d_disk"):
                yield Static("Storage: 62% used")
            with Collapsible(title="Security", collapsed=True, id="d_sec"):
                yield Static("Security: no findings")

    def on_mount(self) -> None:
        super().on_mount()
        self.query_one("#adm_body").border_title = "Admin"

    def action_tab(self, name: str) -> None:
        self.query_one("#tabs", TabbedContent).active = name

    def action_toggle_network(self) -> None:
        net = self.query_one("#d_net", Collapsible)
        net.collapsed = not net.collapsed

    def action_theme(self) -> None:
        self.app.toggle_theme()
        self.query_one("#lbl_theme", Static).update(f"Theme: {self.app.theme_name}")


PAGES = {"overview": OverviewPage, "tasks": TasksPage, "notes": NotesPage, "logs": LogsPage, "settings": SettingsPage, "admin": AdminPage}


class WorkbenchApp(App):
    CSS = CSS

    def __init__(self) -> None:
        super().__init__()
        self.current = ""
        self.job_b = self.job_t = self.job_d = 0
        self.job_state = "idle"
        self.tasks = make_tasks()
        self.logs = logs()
        self.notes = NOTES
        self.theme_name = "dark"

    def on_mount(self) -> None:
        self.show("overview")

    def get_system_commands(self, screen):
        yield from super().get_system_commands(screen)
        yield SystemCommand("Go to Logs", "Open the Logs page", lambda: self.show("logs"))

    def toggle_theme(self) -> None:
        self.theme_name = "light" if self.theme_name == "dark" else "dark"
        self.theme = "textual-light" if self.theme_name == "light" else "textual-dark"

    def show(self, page: str) -> None:
        if page == self.current:
            return
        self.current = page
        if len(self.screen_stack) > 1:
            self.switch_screen(PAGES[page]())
        else:
            self.push_screen(PAGES[page]())


if __name__ == "__main__":
    WorkbenchApp().run()
