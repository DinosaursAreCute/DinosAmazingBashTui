# TODO

Measured on the demo, headless 45x150, cache trusted, unless noted. Numbers are per `tui.goto` unless noted.

## Done (kept for the numbers)

- `tui.cache.load_dir`: one file per page instead of twelve. 87.6 ms to 50.0 ms for 26 pages (read and split 24, `stat` 10, validity loop 11, dependency parse 5 of what is left).
- `tui.bind.defaults`: parse cached as a snapshot. `tui_input.sh` 21 ms to 3 ms, whole lib source 91 ms to 71 ms.

## Todo (investigate)

- **Do not repaint the shell on a page switch.** A switch inside a shell sends the whole frame (25-32 KB) although header,
  nav and footer rows are identical. If the shell parts are exactly the same, those rows need no update. Open points: the
  code comment in `tui.render` says a row diff of a full render cost +41% when measured (that was before the shell existed
  as a unit); compare diffing rows against `_TUI_PAINT_PREV` with painting only the outlet rectangle; the shell's own
  widgets (focus, hover, an input's text) can change between pages, so the check must be on the bytes of the rows, not on
  "same shell". Benchmark first.
- **`lib/chrome/tui_cmd.sh` takes ~9-11 ms to source** with no load-time forks and only four `tui.cmd.provider` calls at the top.
  Not explained. Build a call-site trace (xtrace inside a sourced file printed nothing here: find out why, e.g. a `set +x`
  or `BASH_XTRACEFD` reset during the load, then time each top-level statement) and find what runs.

## Click path (measured headless 50x170, per click)

Hover 2.5 ms, press 7-11 ms, release = `tui.goto` + 1 ms (was press 20-27 ms, release = goto + 19-28 ms). What is left:

- The press draws the old and new widget and up to three pane borders (7-11 ms, 8-10 KB). A focus change that does not change a
  border's colour (the pane keeps its focus ring) could skip the border; check what `_tui._draw_pane_border_buf` redraws for a
  pane whose state did not change.
- A pane with a scrollbar or output (the 101x30 `output` pane) still takes 3-5 ms per border redraw: the scrollbar and the
  output bars are recomposed with it.

## Smaller leads (from the page-switch survey)

- `_tui_input.reverse_keys` costs ~0.9 ms per footer build: it rebuilds the user and code tiers and compares a long signature
  on every call. A short-circuit on `_TUI_BIND_GEN` needs the writers that do not bump it (`tui.config.apply` sets
  `_TUI_DEF_OFF` directly, `tui.bind.clear_page` resets `_TUI_DEF_OFF_PAGE`) fixed first.
- `_tui_shell.leave_page` still ends with `_tui._collect_leaves root`, and the replay or build right after collects again
  (~1.3 ms). Skipping the first needs a decision about a goto to a page that fails to load (it would leave `_TUI_P_ALL` empty).
- The `debug_input` page takes ~190 ms per goto (94 leaves): not looked at.
- `tui.cache.dump_dir` rewrites every page's file at the end of a cold or lazy build; only the built pages changed (now 26 writes, ~14 ms).
- `tui.cache.load_dir` still parses each page's dependency signature twice (once for the stat list, once in `tui.cache.valid`): ~5-8 ms.
