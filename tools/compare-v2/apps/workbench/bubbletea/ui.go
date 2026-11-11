package main

import (
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/x/ansi"
)

// theme is one colour palette; the whole UI is drawn from the active one.
type theme struct {
	fg, dim, accent, border, ok lipgloss.Color
	selFg, selBg                lipgloss.Color
}

var (
	darkTheme  = theme{fg: "252", dim: "244", accent: "81", border: "250", ok: "114", selFg: "0", selBg: "81"}
	lightTheme = theme{fg: "236", dim: "243", accent: "25", border: "238", ok: "28", selFg: "255", selBg: "25"}
)

func (t theme) text(s string) string  { return lipgloss.NewStyle().Foreground(t.fg).Render(s) }
func (t theme) muted(s string) string { return lipgloss.NewStyle().Foreground(t.dim).Render(s) }
func (t theme) accented(s string) string {
	return lipgloss.NewStyle().Foreground(t.accent).Bold(true).Render(s)
}
func (t theme) selected(s string) string {
	return lipgloss.NewStyle().Foreground(t.selFg).Background(t.selBg).Render(s)
}

// fit clips or pads one line to exactly w cells (ANSI aware).
func fit(s string, w int) string {
	if w <= 0 {
		return ""
	}
	if n := ansi.StringWidth(s); n > w {
		return ansi.Truncate(s, w, "")
	} else if n < w {
		return s + strings.Repeat(" ", w-n)
	}
	return s
}

// lines splits rendered content into rows, dropping one trailing newline.
func lines(s string) []string { return strings.Split(strings.TrimSuffix(s, "\n"), "\n") }

// frame draws a bordered pane of exactly w x h cells with a title in the top border and hpad cells of horizontal padding.
func frame(th theme, title string, body []string, w, h, hpad int) []string {
	iw, ih := w-2-2*hpad, h-2
	bd := func(s string) string { return lipgloss.NewStyle().Foreground(th.border).Render(s) }
	head := ""
	if title != "" {
		head = " " + title + " "
	}
	top := bd("┌" + head + strings.Repeat("─", max(0, w-2-ansi.StringWidth(head))) + "┐")
	out := make([]string, 0, h)
	out = append(out, fit(top, w))
	pad := strings.Repeat(" ", hpad)
	side := bd("│")
	for i := 0; i < ih; i++ {
		row := ""
		if i < len(body) {
			row = body[i]
		}
		out = append(out, side+pad+fit(row, iw)+pad+side)
	}
	out = append(out, bd("└"+strings.Repeat("─", w-2)+"┘"))
	return out
}

// joinH puts blocks of equal height side by side.
func joinH(blocks ...[]string) []string {
	out := make([]string, len(blocks[0]))
	for _, b := range blocks {
		for i := range out {
			out[i] += b[i]
		}
	}
	return out
}

// overlay paints box (rows of equal width) over base at cell (x, y), keeping the rest of each row.
func overlay(base, box []string, x, y int) {
	for i, bl := range box {
		r := y + i
		if r < 0 || r >= len(base) {
			continue
		}
		bw := ansi.StringWidth(bl)
		left := fit(ansi.Truncate(base[r], x, ""), x)
		base[r] = left + "\x1b[0m" + bl + "\x1b[0m" + ansi.TruncateLeft(base[r], x+bw, "")
	}
}

// box wraps lines in a border for overlays (dialog, toast, palette).
func box(th theme, title string, body []string) []string {
	w := 0
	for _, l := range body {
		w = max(w, ansi.StringWidth(l))
	}
	w = max(w, ansi.StringWidth(title)+2) + 4
	return frame(th, title, body, w, len(body)+2, 1)
}

// selectBox is a closed drop-down: left/right/space/enter cycle through the items.
type selectBox struct {
	items []string
	idx   int
}

func (s selectBox) value() string { return s.items[s.idx] }

func (s *selectBox) step(d int) { s.idx = (s.idx + d + len(s.items)) % len(s.items) }

func (s selectBox) view(th theme, focused bool) string {
	t := "[ " + s.value() + " ▾ ]"
	if focused {
		return th.selected(t)
	}
	return th.text(t)
}

func checkbox(th theme, label string, on, focused bool) string {
	mark := "[ ]"
	if on {
		mark = "[x]"
	}
	t := mark + " " + label
	if focused {
		return th.selected(t)
	}
	return th.text(t)
}

func button(th theme, label string, focused bool) string {
	if focused {
		return th.selected(label)
	}
	return th.text(label)
}
