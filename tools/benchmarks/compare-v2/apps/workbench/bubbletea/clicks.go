package main

import (
	"github.com/charmbracelet/lipgloss"

	tea "github.com/charmbracelet/bubbletea"
)

// Mouse hit-testing. Bubble Tea reports clicks as cell coordinates and has no widget hit-testing, so a click is matched against the
// position the page layout (pageView) gives each control. The positions are derived from the layout only when a click arrives: drawing
// a frame does no bookkeeping for them.

// span is the horizontal extent of a control on one body row.
func hit(x, y, row, x0, w int) bool { return y == 1+row && x >= x0 && x < x0+w }

func (m *model) clickPage(x, y int) tea.Cmd {
	x0 := m.navW + 2 // inside the border and the 1-cell padding of the main pane
	label := 9       // width of "Filter:  ", "Name:    " ...
	switch m.page {
	case pOverview:
		switch {
		case hit(x, y, 8, x0, len("[ Start jobs ]")):
			m.ovFocus = 0
			return m.startJobs()
		case hit(x, y, 9, x0, len("[ Reset ]")):
			m.ovFocus = 1
			m.resetJobs()
		}

	case pTasks:
		lw := m.mainW * 65 / 100
		xr := m.navW + lw + 2
		switch {
		case hit(x, y, 2, x0+label, lw-4-label):
			return m.setTasksFocus(tfFilter)
		case hit(x, y, 3, x0+label, len(m.status.value())+6):
			m.status.step(1)
			m.refill()
			return m.setTasksFocus(tfStatus)
		case y >= 1+5 && x < m.navW+lw:
			return m.setTasksFocus(tfTable)
		case hit(x, y, 6, xr, len("[ ] Flagged")):
			m.flagged = !m.flagged
		case hit(x, y, 8, xr, len("[ Delete ]")):
			return m.askDelete()
		}

	case pNotes:
		if x < m.navW+m.mainW/2 {
			return m.notes.Focus()
		}

	case pLogs:
		if hit(x, y, 4, x0, len("[ Append 200 ]")) {
			m.appendLogs()
		}

	case pSettings:
		switch {
		case hit(x, y, 2, x0+label, m.mainW-4-label):
			return m.setSettingsFocus(0)
		case hit(x, y, 3, x0+label, len(m.level.value())+6):
			m.level.step(1)
			return m.setSettingsFocus(1)
		case hit(x, y, 5, x0, len("[ ] Notifications")):
			m.checks[0] = !m.checks[0]
			return m.setSettingsFocus(2)
		case hit(x, y, 6, x0, len("[ ] Auto-save")):
			m.checks[1] = !m.checks[1]
			return m.setSettingsFocus(3)
		case hit(x, y, 7, x0, len("[ ] Telemetry")):
			m.checks[2] = !m.checks[2]
			return m.setSettingsFocus(4)
		case hit(x, y, 9, x0, len("[ Apply ]")):
			m.setSettingsFocus(5)
			return m.applySettings()
		}

	case pAdmin:
		if hit(x, y, 1, x0, len(" General ")) {
			m.tab = 0
		} else if hit(x, y, 1, x0+len(" General ")+1, len(" Appearance ")) {
			m.tab = 1
		}
		row := 6 // the Admin frame is 6 rows high; sections follow, 1 row collapsed or 3 rows open
		for i := range m.collapsed {
			if y == row {
				m.collapsed[i] = !m.collapsed[i]
				break
			}
			if m.collapsed[i] {
				row++
			} else {
				row += 3
			}
		}
	}
	return nil
}

// dialogBox returns the confirm dialog and where View puts it.
func (m *model) dialogBox() ([]string, int, int) {
	b := box(m.th, "Confirm", []string{m.th.text(m.dlg.msg), "", m.th.accented("[ Yes ]") + "  " + m.th.text("[ No ]") + m.th.muted("   y / n")})
	return b, (m.w - lipgloss.Width(b[0])) / 2, (m.h - len(b)) / 2
}

func (m *model) clickDialog(x, y int) tea.Cmd {
	_, bx, by := m.dialogBox()
	if y != by+3 { // top border, message, blank, buttons
		return nil
	}
	switch {
	case x >= bx+2 && x < bx+2+len("[ Yes ]"):
		d := m.dlg
		m.dlg = nil
		return d.yes()
	case x >= bx+2+len("[ Yes ]")+2 && x < bx+2+len("[ Yes ]")+2+len("[ No ]"):
		m.dlg = nil
	}
	return nil
}
