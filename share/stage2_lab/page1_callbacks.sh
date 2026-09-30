#!/usr/bin/env bash
# page1_callbacks.sh - stage2_lab page 1 (Layout & Widgets). See page1.xml's header comment.
# Entry point: tools/stage2_lab.sh (this file is only ever sourced as a callback, never run
# standalone - it has no lib/tui.sh of its own to source, and no terminal to take over).

_S2_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

s2_page1_visit() {
	s2_notes_2a
}

s2_goto_page2() { tui.goto "$_S2_DIR/page2.xml"; }
s2_noop() { :; }

s2_notes_2a() {
	tui.output notes_output "2A Layout and sizing: units cells / % / fr / auto / fill / clamp(); min_*/max_* on fr children; widgets gain width, height, expand, padding, margin, gap. weight maps to fr. Owner: lib/layout/tui_layout.sh (measure/arrange primitives already exist, unit-tested; not yet wired to <pane>/widget attributes above expand/min_height/max_height, which already are)."
}
s2_notes_2b() {
	tui.output notes_output "2B Paint pipeline and line canvas: display list (row col sgr text), dirty flags, damage rects, per-row diff, one flush per loop iteration. No new markup - this is a rendering-internals rewrite, so nothing on this page exercises it directly; the payoff is fewer bytes flushed on hover/focus moves."
}
s2_notes_2c() {
	tui.output notes_output "2C Hit index and focus: per-row interval index; zone kinds widget/hitbox/scrollbar/divider/handle/chevron/title; focusable, tabbable, tab_order, focus_group, focus_nav, focus_wrap, autofocus, focus_next/prev, hitbox, hit_pad. See page 2 for inert attribute placeholders on real widgets."
}
s2_notes_2d() {
	tui.output notes_output "2D Node ops and composition: clone/insert/replace/remove/set/wrap/move; selectors #id .class tag >; built on top: <template>/<use>/<slot>/<fill>, <component>, parametrised <include>, <for>/<if>. These are NEW TAGS - the loader errors on an unknown tag today, so they can't appear live here; see page 2's reference text for the planned syntax."
}
