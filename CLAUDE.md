# CLAUDE.md

Pure bash TUI framework (D.A.B.T). No deps beyond POSIX utils + awk. No Python/Node/ncurses.

## Behavioral rules (token discipline)

Terse mode. Apply to all reasoning and replies in this repo:

- No filler ("Let me...", "I'll now...", "Great, so..."). State result, not narration.
- No restating the task back before doing it.
- No summary after edits unless asked. Diff speaks.
- One-line status updates. Skip updates for trivial/expected steps.
- Abbrevs OK when standard in this codebase: fn, def, impl, config, arg, param, var, dir, env.
- Answer first, justify only if non-obvious or asked.
- No hedging ("might", "could potentially") when you've read the code and know.
- Skip preamble in commit messages / PR descriptions too - lead with the change.
- Don't re-explain framework concepts already covered below; assume this file was read.

## Architecture

Load order (`bin/tui.sh` sources these): `terminal_controls.sh` → `colors.sh` → `tui_markup.sh` → `tui_style.sh` → `tui.sh` itself.

- `terminal_controls.sh` - raw ANSI/cursor primitives (`printat`, `sprint`, `sgr`, `putblock`, `link`, sync blocks). Low-level, no state.
- `colors.sh` - plain color const exports (`RED`, `BRIGHT_CYAN`, `BG_DIM_RED`, ...). No logic.
- `terminal_renderer.sh` - standalone widget-string renderers: `box`, `divider`, `alert`, `table`, `kv`, `hbar`, `gauge`, `banner`, `tree`, `columns`, etc. Each has a `_build` (returns lines) + public fn (prints) + `_string` (returns string) variant. CSV-driven charting lives here too (`_tr_csv_parse`, `_tr_resample`). Usable standalone (see `examples/csv-charts/`), independent of `tui.sh`'s pane system.
- `tui_markup.sh` - XML config parser (`tui.load`, `tui.start`). Turns `<pane>`, `<button>`, `<grid>`, `<tabs>`, `<include>`, `<script>`, `<theme>` tags into `tui.*` calls. `tui.start FILE` = init + load + run lifecycle in one call.
- `tui_style.sh` - CSS-like `.class` theme resolution (`fg`/`bg`/`mods`, `:focus`/`:border`/`:title` pseudo-states) from `theme.css` files referenced via `<theme src="..."/>`.
- `tui.sh` (2800+ lines, the core) - layout engine, focus/mouse routing, main event loop, `tui.exec` (multi-instance PTY-backed live process streaming into panes). Public API is dot-namespaced: `tui.init`, `tui.hsplit`/`tui.vsplit`/`tui.grid`, `tui.label`/`tui.button`/`tui.input`/`tui.checkbox`, `tui.exec`, `tui.output*`, `tui.run`, `tui.stop`. Private helpers prefixed `_tui.` or `_exec_`.

### Config-driven app model (primary usage)

Apps are XML files in `config/*.xml` (think HTML pages) + a paired `*_callbacks.sh` (bash functions = event handlers, referenced via `action="fn_name"` or `on_visit="fn_name"`). `<script src="foo_callbacks.sh"/>` sources the callback file; `<theme src="theme.css"/>` sets styling. Pages link via `page="other.xml"` on buttons. `<include src="_frag.xml"/>` for shared fragments.

Entry point pattern: a thin `bin/*_demo.sh` does `source tui.sh; tui.start "config/home.xml"`.

### Callback files (`config/*_callbacks.sh`, `bin/callbacks.sh`)

Plain bash functions, one per `action=`. No special return protocol beyond normal bash exit codes; they call `tui.*` API fns to mutate panes/output. Keep them free of framework internals - call public `tui.*`, not `_tui.*`/`_exec_*`.

## Key invariants - do not break

- No external deps. Before adding one, it's the wrong solution.
- `_tui.*`/`_exec_*`/`_tr_*`/leading-underscore fns are private - never call from config/callback code, never expose new ones without the underscore.
- `tui.exec` is multi-instance: never assume one instance per pane; panes are keyed by instance id (`e1`, `e2`, ...) in `_EXEC_PANE_INSTANCES`.
- Tick fns: page-level work goes through `tui.tick.add`, not overwriting `_TUI_TICK_FN` (that's legacy single-slot, reserved for a page's own per-frame hook) - clobbering breaks concurrent `tui.exec` polling.
- Render debouncing exists for a reason (scroll/content redraw coalescing) - don't add direct `tui.render` calls in hot paths without checking `_tui._draw_widgets_now` vs debounced queue distinction already in place.
- `TUI_MOUSE_DRAIN_PEEK_TIMEOUT` must never be set to 0 (`read -t 0` is a pure availability probe in bash, consumes nothing - see comment at top of `tui.sh`).
- Widget renderers (`terminal_renderer.sh`) must stay usable standalone (no `tui.sh` state dependency) - that's what `examples/csv-charts/` exercises.

## Testing

No formal test framework. `bin/test.sh` is a stub. Verify changes by running the actual demo:

```bash
bash bin/DABT_demo.sh        # or whichever bin/*_demo.sh targets the page you touched
bash examples/csv-charts/run_examples.sh   # standalone renderer sanity check
```

TUI changes must be visually verified in a real terminal - can't be checked from output text alone. Use the `run` skill if available.

## Docs

`docs/README.md` is the entry point; `docs/guide/` (markup, grid/tabs, callbacks/viewports, input bindings), `docs/api/` (API reference), `docs/design/` (deep-dive writeups: scrolling perf, mouse/hover, WAL replay, grid geometry). Check these before reimplementing scrolling/mouse/grid logic; they document non-obvious perf tradeoffs already made.

## Gotchas

- `.tui_exec.log` is a runtime artifact (debug log for `tui.exec`), gets modified by running the app - not something to hand-edit or worry about in diffs unless asked.
- Bash-only: no bashisms assumed unavailable - this targets bash specifically (not POSIX sh), but stays dependency-free otherwise (awk is used for the scrolling "shader" viewports, POSIX-only).
