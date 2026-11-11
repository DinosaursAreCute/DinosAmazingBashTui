// Bubble Tea side of the workbench benchmark: six pages, behaviour contract = the Textual app (../textual/app.py) and the scenario
// (../../../scenarios/workbench.py).
//
// Written the way a Bubble Tea developer would: one root model (Elm architecture), the stock bubbles components (table, textinput,
// textarea, list, progress, viewport) plus glamour for the markdown preview, tea.Tick for the job timer and toast expiry.
// No cursor blink and no clocks: an idle app writes nothing, which the harness relies on.
package main

import (
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/cursor"
	"github.com/charmbracelet/bubbles/list"
	"github.com/charmbracelet/bubbles/progress"
	"github.com/charmbracelet/bubbles/table"
	"github.com/charmbracelet/bubbles/textarea"
	"github.com/charmbracelet/bubbles/textinput"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/glamour"
	"github.com/charmbracelet/lipgloss"
)

type page int

const (
	pOverview page = iota
	pTasks
	pNotes
	pLogs
	pSettings
	pAdmin
)

var pageNames = [...]string{"Overview", "Tasks", "Notes", "Logs", "Settings", "Admin"}

// focus targets per page
const (
	tfTable = iota
	tfFilter
	tfStatus
)

type logLine string

func (l logLine) Title() string       { return string(l) }
func (l logLine) Description() string { return "" }
func (l logLine) FilterValue() string { return string(l) }

type (
	jobTick   struct{ gen int }
	toastGone int
)

type toast struct {
	id  int
	msg string
}

type dialog struct {
	msg string
	yes func() tea.Cmd
}

type command struct {
	name string
	run  func(m *model) tea.Cmd
}

type palette struct {
	in  textinput.Model
	sel int
}

type model struct {
	w, h, navW, mainW int
	th                theme
	dark              bool
	page              page

	toasts   []toast
	toastSeq int
	dlg      *dialog
	pal      *palette

	// overview
	job      [3]int
	jobState string
	jobGen   int
	ovFocus  int
	bar      progress.Model

	// tasks
	tasks   []task
	rows    []task
	filter  textinput.Model
	status  selectBox
	tbl     table.Model
	tfocus  int
	flagged bool

	// notes
	notes textarea.Model
	words int
	md    *glamour.TermRenderer
	mdW   int
	prev  viewport.Model

	// logs
	logs []string
	lst  list.Model

	// settings
	name   textinput.Model
	level  selectBox
	checks [3]bool
	sfocus int
	saved  string

	// admin
	tab       int
	collapsed [3]bool
}

func staticInput(placeholder string) textinput.Model {
	in := textinput.New()
	in.Prompt = ""
	in.Placeholder = placeholder
	in.Cursor.SetMode(cursor.CursorStatic)
	return in
}

func newModel() *model {
	m := &model{th: darkTheme, dark: true, jobState: "idle", saved: "nothing yet"}
	m.bar = progress.New(progress.WithSolidFill(string(m.th.accent)))

	m.tasks = makeTasks()
	m.filter = staticInput("type to filter")
	m.status = selectBox{items: []string{"all", "open", "done", "blocked"}}
	m.tbl = table.New(table.WithFocused(true), table.WithColumns([]table.Column{{Title: "ID", Width: 8}, {Title: "Title", Width: 20}, {Title: "Owner", Width: 8}, {Title: "Status", Width: 9}}))
	m.applyTableStyles()

	text := readData("notes.md")
	m.notes = textarea.New()
	m.notes.ShowLineNumbers = false
	m.notes.Prompt = ""
	m.notes.CharLimit = 0 // the default (400) would reject typing into the 600-character document
	m.notes.Cursor.SetMode(cursor.CursorStatic)
	m.notes.SetValue(text)
	for m.notes.Line() > 0 { // SetValue leaves the cursor at the end; Textual's TextArea starts at the top
		m.notes.CursorUp()
	}
	m.notes.CursorStart()
	m.words = len(strings.Fields(text))
	m.prev = viewport.New(10, 10)

	m.logs = readLogs()
	items := make([]list.Item, len(m.logs))
	for i, l := range m.logs {
		items[i] = logLine(l)
	}
	d := list.NewDefaultDelegate()
	d.ShowDescription = false
	d.SetSpacing(0)
	m.lst = list.New(items, d, 10, 10)
	m.lst.SetShowTitle(false)
	m.lst.SetShowStatusBar(false)
	m.lst.SetShowHelp(false)
	m.lst.SetShowPagination(false)
	m.lst.SetFilteringEnabled(false)

	m.name = staticInput("display name")
	m.level = selectBox{items: []string{"info", "warn", "debug"}}
	m.checks = [3]bool{true, false, false}

	m.collapsed = [3]bool{false, true, true}
	m.refill()
	return m
}

func (m *model) Init() tea.Cmd { return nil }

// ---- layout ---------------------------------------------------------------------------------------------------------------------

func (m *model) layout() {
	bh := m.h - 1
	m.navW = max(m.w*18/100, 14)
	m.mainW = m.w - m.navW
	iw := m.mainW - 4

	m.bar.Width = max(iw-8, 10)

	lw := m.mainW * 65 / 100
	tw := lw - 4
	m.filter.Width = max(tw-9, 5)
	title := max(tw-25-8, 8)
	m.tbl.SetColumns([]table.Column{{Title: "ID", Width: 8}, {Title: "Title", Width: title}, {Title: "Owner", Width: 8}, {Title: "Status", Width: 9}})
	m.tbl.SetWidth(tw)
	m.tbl.SetHeight(max(bh-2-5, 3))

	ew := m.mainW / 2
	m.notes.SetWidth(ew - 4)
	m.notes.SetHeight(max(bh-4, 3))
	pw := m.mainW - ew - 4
	if pw != m.mdW {
		m.mdW = pw
		m.makeRenderer()
	}
	m.prev.Width, m.prev.Height = pw, bh-2

	m.lst.SetSize(iw, max(bh-2-5, 3))
	m.name.Width = max(iw-9, 5)
}

func (m *model) makeRenderer() {
	style := "dark"
	if !m.dark {
		style = "light"
	}
	m.md, _ = glamour.NewTermRenderer(glamour.WithStandardStyle(style), glamour.WithWordWrap(m.mdW))
	m.renderMarkdown()
}

func (m *model) renderMarkdown() {
	if m.md == nil {
		return
	}
	out, err := m.md.Render(m.notes.Value())
	if err != nil {
		out = err.Error()
	}
	m.prev.SetContent(strings.TrimRight(out, "\n"))
}

func (m *model) applyTableStyles() {
	s := table.DefaultStyles()
	s.Header = lipgloss.NewStyle().Bold(true).Foreground(m.th.accent).Padding(0, 1)
	s.Cell = lipgloss.NewStyle().Foreground(m.th.fg).Padding(0, 1)
	s.Selected = lipgloss.NewStyle().Foreground(m.th.selFg).Background(m.th.selBg)
	m.tbl.SetStyles(s)
}

func (m *model) setDark(dark bool) {
	m.dark = dark
	lipgloss.SetHasDarkBackground(dark) // the bubbles components' adaptive colours follow
	if dark {
		m.th = darkTheme
	} else {
		m.th = lightTheme
	}
	m.bar = progress.New(progress.WithSolidFill(string(m.th.accent)), progress.WithWidth(m.bar.Width))
	m.applyTableStyles()
	m.makeRenderer()
}

// ---- state changes ----------------------------------------------------------------------------------------------------------------

func (m *model) refill() {
	needle := strings.ToLower(m.filter.Value())
	status := m.status.value()
	m.rows = m.rows[:0]
	var rows []table.Row
	for _, t := range m.tasks {
		if (status == "all" || t.status == status) && (needle == "" || strings.Contains(t.searchable(), needle)) {
			m.rows = append(m.rows, t)
			rows = append(rows, table.Row{t.id, t.title, t.owner, t.status})
		}
	}
	m.tbl.SetRows(rows)
	m.tbl.SetCursor(0)
	m.tbl.GotoTop()
}

func (m *model) current() (task, bool) {
	c := m.tbl.Cursor()
	if c < 0 || c >= len(m.rows) {
		return task{}, false
	}
	return m.rows[c], true
}

func (m *model) notify(msg string) tea.Cmd {
	m.toastSeq++
	id := m.toastSeq
	m.toasts = append(m.toasts, toast{id, msg})
	return tea.Tick(3*time.Second, func(time.Time) tea.Msg { return toastGone(id) })
}

func (m *model) goTo(p page) tea.Cmd {
	m.page = p
	m.notes.Blur()
	m.filter.Blur()
	m.name.Blur()
	switch p {
	case pOverview:
		m.ovFocus = 0
	case pTasks:
		m.tfocus = tfTable
	case pNotes:
		return m.notes.Focus()
	case pSettings:
		m.sfocus = 0
		return m.name.Focus()
	}
	return nil
}

func (m *model) setTasksFocus(f int) tea.Cmd {
	m.tfocus = f
	m.filter.Blur()
	if f == tfFilter {
		return m.filter.Focus()
	}
	return nil
}

func (m *model) setSettingsFocus(f int) tea.Cmd {
	m.sfocus = (f + 6) % 6
	m.name.Blur()
	if m.sfocus == 0 {
		return m.name.Focus()
	}
	return nil
}

func (m *model) startJobs() tea.Cmd {
	if m.jobState == "running" {
		return nil
	}
	m.job = [3]int{}
	m.jobState = "running"
	m.jobGen++
	return m.jobTimer()
}

func (m *model) jobTimer() tea.Cmd {
	gen := m.jobGen
	return tea.Tick(100*time.Millisecond, func(time.Time) tea.Msg { return jobTick{gen} })
}

func (m *model) resetJobs() {
	m.jobGen++
	m.job = [3]int{}
	m.jobState = "idle"
}

func (m *model) askDelete() tea.Cmd {
	t, ok := m.current()
	if !ok {
		return nil
	}
	m.dlg = &dialog{msg: "Delete " + t.id + "?", yes: func() tea.Cmd {
		for i, x := range m.tasks {
			if x.id == t.id {
				m.tasks = append(m.tasks[:i], m.tasks[i+1:]...)
				break
			}
		}
		m.refill()
		return m.notify("Deleted " + t.id)
	}}
	return nil
}

func (m *model) applySettings() tea.Cmd {
	name := m.name.Value()
	if name == "" {
		name = "anonymous"
	}
	flags := ""
	for _, c := range m.checks {
		if c {
			flags += "1"
		} else {
			flags += "0"
		}
	}
	m.saved = fmt.Sprintf("name=%s level=%s flags=%s", name, m.level.value(), flags)
	return m.notify("Settings saved")
}

func (m *model) appendLogs() {
	add := m.logs[:200:200]
	m.logs = append(m.logs, add...)
	items := make([]list.Item, len(add))
	for i, l := range add {
		items[i] = logLine(l)
	}
	idx := m.lst.Index()
	m.lst.SetItems(append(m.lst.Items(), items...))
	m.lst.Select(idx)
}

func (m *model) commands() []command {
	var cs []command
	for i, n := range pageNames {
		p := page(i)
		cs = append(cs, command{"Go to " + n, func(m *model) tea.Cmd { return m.goTo(p) }})
	}
	cs = append(cs,
		command{"Toggle theme", func(m *model) tea.Cmd { m.setDark(!m.dark); return nil }},
		command{"Quit", func(m *model) tea.Cmd { return tea.Quit }})
	return cs
}

func (p *palette) matches(all []command) []command {
	needle := strings.ToLower(p.in.Value())
	var out []command
	for _, c := range all {
		if strings.Contains(strings.ToLower(c.name), needle) {
			out = append(out, c)
		}
	}
	return out
}

// ---- update -----------------------------------------------------------------------------------------------------------------------

func (m *model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.w, m.h = msg.Width, msg.Height
		m.layout()
		return m, nil
	case jobTick:
		if msg.gen != m.jobGen || m.jobState != "running" {
			return m, nil
		}
		m.job[0], m.job[1], m.job[2] = min(100, m.job[0]+10), min(100, m.job[1]+8), min(100, m.job[2]+5)
		if m.job == [3]int{100, 100, 100} {
			m.jobState = "done"
			return m, m.notify("All jobs finished")
		}
		return m, m.jobTimer()
	case toastGone:
		for i, t := range m.toasts {
			if t.id == int(msg) {
				m.toasts = append(m.toasts[:i], m.toasts[i+1:]...)
				break
			}
		}
		return m, nil
	case tea.MouseMsg:
		return m, m.mouse(msg)
	case tea.KeyMsg:
		return m, m.key(msg)
	}
	return m, nil
}

func (m *model) mouse(msg tea.MouseMsg) tea.Cmd {
	if msg.Action != tea.MouseActionPress || m.pal != nil {
		return nil
	}
	if m.dlg != nil {
		if msg.Button == tea.MouseButtonLeft {
			return m.clickDialog(msg.X, msg.Y)
		}
		return nil
	}
	switch msg.Button {
	case tea.MouseButtonLeft:
		if msg.X < m.navW {
			switch i := msg.Y - 1; {
			case i >= 0 && i < len(pageNames):
				return m.goTo(page(i))
			case i == len(pageNames)+1:
				return tea.Quit
			}
		} else {
			return m.clickPage(msg.X, msg.Y)
		}
	case tea.MouseButtonWheelDown, tea.MouseButtonWheelUp:
		n := 3
		if msg.Button == tea.MouseButtonWheelUp {
			n = -3
		}
		switch m.page {
		case pLogs:
			for ; n > 0; n-- {
				m.lst.CursorDown()
			}
			for ; n < 0; n++ {
				m.lst.CursorUp()
			}
		case pTasks:
			if n > 0 {
				m.tbl.MoveDown(n)
			} else {
				m.tbl.MoveUp(-n)
			}
		case pNotes:
			if n > 0 {
				m.prev.LineDown(n)
			} else {
				m.prev.LineUp(-n)
			}
		}
	}
	return nil
}

func (m *model) key(msg tea.KeyMsg) tea.Cmd {
	s := msg.String()
	if s == "ctrl+c" || s == "ctrl+q" {
		return tea.Quit
	}
	if m.dlg != nil {
		switch s {
		case "y":
			d := m.dlg
			m.dlg = nil
			return d.yes()
		case "n", "esc":
			m.dlg = nil
		}
		return nil
	}
	if m.pal != nil {
		return m.paletteKey(msg)
	}
	// chords come first: a focused input would otherwise type the letter
	if s == "ctrl+p" {
		in := staticInput("Search for commands…")
		in.Prompt = "> "
		in.Width = 54
		m.pal = &palette{in: in}
		return m.pal.in.Focus()
	}
	if len(s) == 5 && strings.HasPrefix(s, "alt+") && s[4] >= '1' && s[4] <= '6' {
		return m.goTo(page(s[4] - '1'))
	}
	if cmd, ok := m.pageChord(s); ok {
		return cmd
	}
	switch m.page {
	case pOverview:
		return m.overviewKey(s)
	case pTasks:
		return m.tasksKey(msg)
	case pNotes:
		before := m.notes.Value()
		var cmd tea.Cmd
		m.notes, cmd = m.notes.Update(msg)
		if v := m.notes.Value(); v != before {
			m.words = len(strings.Fields(v))
			m.renderMarkdown()
		}
		return cmd
	case pLogs:
		var cmd tea.Cmd
		m.lst, cmd = m.lst.Update(msg)
		return cmd
	case pSettings:
		return m.settingsKey(msg)
	case pAdmin:
		switch s {
		case "left", "right":
			m.tab = 1 - m.tab
		}
	}
	return nil
}

func (m *model) pageChord(s string) (tea.Cmd, bool) {
	switch m.page {
	case pOverview:
		switch s {
		case "alt+s":
			return m.startJobs(), true
		case "alt+r":
			m.resetJobs()
			return nil, true
		}
	case pTasks:
		switch s {
		case "alt+i":
			return m.setTasksFocus(tfFilter), true
		case "alt+t":
			return m.setTasksFocus(tfTable), true
		case "alt+d":
			return m.askDelete(), true
		case "alt+f":
			m.flagged = !m.flagged
			return nil, true
		}
	case pNotes:
		if s == "alt+e" {
			return m.notes.Focus(), true
		}
	case pLogs:
		switch s {
		case "alt+a":
			m.appendLogs()
			return nil, true
		case "alt+l":
			return nil, true
		}
	case pSettings:
		switch s {
		case "alt+n":
			return m.setSettingsFocus(0), true
		case "alt+p":
			return m.applySettings(), true
		}
	case pAdmin:
		switch s {
		case "alt+g":
			m.tab = 0
			return nil, true
		case "alt+v":
			m.tab = 1
			return nil, true
		case "alt+z":
			m.collapsed[0] = !m.collapsed[0]
			return nil, true
		case "alt+m":
			m.setDark(!m.dark)
			return nil, true
		}
	}
	return nil, false
}

func (m *model) overviewKey(s string) tea.Cmd {
	switch s {
	case "tab", "shift+tab", "up", "down":
		m.ovFocus = 1 - m.ovFocus
	case "enter", " ":
		if m.ovFocus == 0 {
			return m.startJobs()
		}
		m.resetJobs()
	}
	return nil
}

func (m *model) tasksKey(msg tea.KeyMsg) tea.Cmd {
	switch s := msg.String(); s {
	case "tab":
		return m.setTasksFocus((m.tfocus + 1) % 3)
	case "shift+tab":
		return m.setTasksFocus((m.tfocus + 2) % 3)
	}
	var cmd tea.Cmd
	switch m.tfocus {
	case tfTable:
		m.tbl, cmd = m.tbl.Update(msg)
	case tfFilter:
		before := m.filter.Value()
		m.filter, cmd = m.filter.Update(msg)
		if m.filter.Value() != before {
			m.refill()
		}
	case tfStatus:
		switch msg.String() {
		case "left":
			m.status.step(-1)
			m.refill()
		case "right", "enter", " ":
			m.status.step(1)
			m.refill()
		}
	}
	return cmd
}

func (m *model) settingsKey(msg tea.KeyMsg) tea.Cmd {
	s := msg.String()
	switch s {
	case "tab", "down":
		return m.setSettingsFocus(m.sfocus + 1)
	case "shift+tab", "up":
		return m.setSettingsFocus(m.sfocus - 1)
	}
	switch {
	case m.sfocus == 0:
		var cmd tea.Cmd
		m.name, cmd = m.name.Update(msg)
		return cmd
	case m.sfocus == 1:
		switch s {
		case "left":
			m.level.step(-1)
		case "right", "enter", " ":
			m.level.step(1)
		}
	case m.sfocus <= 4:
		if s == "enter" || s == " " {
			m.checks[m.sfocus-2] = !m.checks[m.sfocus-2]
		}
	case s == "enter":
		return m.applySettings()
	}
	return nil
}

func (m *model) paletteKey(msg tea.KeyMsg) tea.Cmd {
	p := m.pal
	matches := p.matches(m.commands())
	switch msg.String() {
	case "esc":
		m.pal = nil
		return nil
	case "up":
		p.sel = max(p.sel-1, 0)
		return nil
	case "down":
		p.sel = min(p.sel+1, max(len(matches)-1, 0))
		return nil
	case "enter":
		m.pal = nil
		if p.sel < len(matches) {
			return matches[p.sel].run(m)
		}
		return nil
	}
	var cmd tea.Cmd
	before := p.in.Value()
	p.in, cmd = p.in.Update(msg)
	if p.in.Value() != before {
		p.sel = 0
	}
	return cmd
}

// ---- view -------------------------------------------------------------------------------------------------------------------------

func (m *model) View() string {
	if m.w == 0 {
		return ""
	}
	bh := m.h - 1
	rows := joinH(m.navView(bh), m.pageView(bh))
	rows = append(rows, fit(m.footer(), m.w))
	for i := len(m.toasts) - 1; i >= 0; i-- { // newest at the bottom, stacked upwards above the footer
		b := box(m.th, "", []string{m.th.text(m.toasts[i].msg)})
		y := m.h - 1 - 3*(len(m.toasts)-i)
		overlay(rows, b, m.w-lipgloss.Width(b[0])-1, y)
	}
	if m.dlg != nil {
		b, x, y := m.dialogBox()
		overlay(rows, b, x, y)
	}
	if m.pal != nil {
		body := []string{m.pal.in.View()}
		for i, c := range m.pal.matches(m.commands()) {
			l := fit("  "+c.name, 56)
			if i == m.pal.sel {
				l = m.th.selected(l)
			} else {
				l = m.th.text(l)
			}
			body = append(body, l)
		}
		b := box(m.th, "Command palette", body)
		overlay(rows, b, (m.w-lipgloss.Width(b[0]))/2, 2)
	}
	return strings.Join(rows, "\n")
}

func (m *model) footer() string {
	hint := map[page]string{
		pOverview: "alt+s Start jobs  alt+r Reset",
		pTasks:    "alt+i Filter  alt+t Table  alt+d Delete",
		pNotes:    "alt+e Editor",
		pLogs:     "alt+a Append  alt+l List",
		pSettings: "alt+n Name  alt+p Apply",
		pAdmin:    "alt+g General  alt+v Appearance  alt+z Network  alt+m Theme",
	}[m.page]
	return m.th.muted(" alt+1..6 Pages  " + hint + "  ctrl+p Palette  ctrl+q Quit")
}

func (m *model) navView(bh int) []string {
	var body []string
	for i, n := range pageNames {
		l := fit("  "+n, m.navW-4)
		if page(i) == m.page {
			l = m.th.selected(l)
		} else {
			l = m.th.text(l)
		}
		body = append(body, l)
	}
	body = append(body, "", m.th.text("  Quit"))
	return frame(m.th, "Menu", body, m.navW, bh, 1)
}

func (m *model) pageView(bh int) []string {
	th := m.th
	switch m.page {
	case pOverview:
		body := []string{th.text("Page 1: Overview"), ""}
		for i, l := range []string{"Build: ", "Test:  ", "Deploy:"} {
			body = append(body, th.text(l)+" "+m.bar.ViewAs(float64(m.job[i])/100))
		}
		body = append(body, "", th.text("Jobs: "+m.jobState), "",
			button(th, "[ Start jobs ]", m.ovFocus == 0), button(th, "[ Reset ]", m.ovFocus == 1))
		return frame(th, "Overview", body, m.mainW, bh, 1)

	case pTasks:
		lw := m.mainW * 65 / 100
		left := []string{th.text("Page 2: Tasks"), "",
			th.text("Filter:  ") + m.filter.View(),
			th.text("Status:  ") + m.status.view(th, m.tfocus == tfStatus),
			th.text(fmt.Sprintf("Rows: %d/%d", len(m.rows), len(m.tasks)))}
		left = append(left, lines(m.tbl.View())...)
		sel, title, owner, status := "-", "-", "-", "-"
		if t, ok := m.current(); ok {
			sel, title, owner, status = t.id, t.title, t.owner, t.status
		}
		right := []string{th.text("Selected: " + sel), "", th.text("Title: " + title), th.text("Owner: " + owner), th.text("Status: " + status), "",
			checkbox(th, "Flagged", m.flagged, false), "", button(th, "[ Delete ]", false)}
		return joinH(frame(th, "Tasks", left, lw, bh, 1), frame(th, "Detail", right, m.mainW-lw, bh, 1))

	case pNotes:
		ew := m.mainW / 2
		left := []string{th.text("Page 3: Notes"), th.text(fmt.Sprintf("Words: %d", m.words))}
		left = append(left, lines(m.notes.View())...)
		return joinH(frame(th, "Editor", left, ew, bh, 1), frame(th, "Preview", lines(m.prev.View()), m.mainW-ew, bh, 1))

	case pLogs:
		body := []string{th.text("Page 4: Logs"), "", th.text(fmt.Sprintf("Lines: %d", len(m.logs))), th.text(fmt.Sprintf("Line: %d", m.lst.Index()+1)),
			button(th, "[ Append 200 ]", false)}
		body = append(body, lines(m.lst.View())...)
		return frame(th, "Logs", body, m.mainW, bh, 1)

	case pSettings:
		body := []string{th.text("Page 5: Settings"), "",
			th.text("Name:    ") + m.name.View(),
			th.text("Level:   ") + m.level.view(th, m.sfocus == 1), "",
			checkbox(th, "Notifications", m.checks[0], m.sfocus == 2),
			checkbox(th, "Auto-save", m.checks[1], m.sfocus == 3),
			checkbox(th, "Telemetry", m.checks[2], m.sfocus == 4), "",
			button(th, "[ Apply ]", m.sfocus == 5), "",
			th.text("Saved: " + m.saved)}
		return frame(th, "Settings", body, m.mainW, bh, 1)

	default: // pAdmin
		tabs := []string{" General ", " Appearance "}
		for i, t := range tabs {
			if i == m.tab {
				tabs[i] = th.selected(t)
			} else {
				tabs[i] = th.text(t)
			}
		}
		theme := "dark"
		if !m.dark {
			theme = "light"
		}
		body := []string{th.text("Page 6: Admin"), tabs[0] + " " + tabs[1], th.text("Tab: " + []string{"General", "Appearance"}[m.tab]), th.text("Theme: " + theme)}
		out := frame(th, "Admin", body, m.mainW, 6, 1)
		for i, sec := range []struct{ name, text string }{{"Network", "Network: 3 interfaces up"}, {"Storage", "Storage: 62% used"}, {"Security", "Security: no findings"}} {
			if m.collapsed[i] {
				out = append(out, fit(" "+th.accented("▶ "+sec.name), m.mainW))
			} else {
				out = append(out, frame(th, "▼ "+sec.name, []string{th.text(sec.text)}, m.mainW, 3, 1)...)
			}
		}
		for len(out) < bh {
			out = append(out, strings.Repeat(" ", m.mainW))
		}
		return out[:bh]
	}
}

func main() {
	lipgloss.SetHasDarkBackground(true) // never ask the terminal for its background colour
	if _, err := tea.NewProgram(newModel(), tea.WithAltScreen(), tea.WithMouseCellMotion()).Run(); err != nil {
		fmt.Fprintln(os.Stderr, "workbench:", err)
		os.Exit(1)
	}
}
