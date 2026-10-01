# Developer Guide: Designing Fast Apps

How to write pages and callbacks that stay under the perceived-instant budgets. Every recommendation here comes from a measured change to the demo app; the numbers are in [section 9](#9-what-the-demo-gained).

## 1. Budgets

A page switch under 100 ms and input feedback under 50 ms feel instant. These are the lines the profiler (`tools/profiler`) rates against:

| interaction | budget |
|---|---|
| hover, focus, click | 30 to 100 ms |
| page switch | 100 to 150 ms |
| palette, dialog open or close | 100 ms |
| resize | 250 ms |
| idle | 2 repaints per second at most |

The framework already makes the common work cheap (page snapshots, a style cache, row and geometry caches, one synchronized flush per frame). What is left is **your code**: a callback that forks five times costs more than the whole render of a simple page.

## 2. The cost model

Rough prices on a desktop machine, in bash 5:

| operation | cost |
|---|---|
| builtin command (`[[ ]]`, `(( ))`, `printf -v`) | 1 to 3 µs |
| associative array lookup `${A[$k]}` | 2 to 3 µs |
| function call | 2 to 5 µs |
| `$( )` of a function (a fork, no exec) | 0.3 to 1 ms |
| `$( )` of an external program (fork and exec) | 1 to 3 ms, more under load |
| pipeline of `n` programs | `n` forks and `n` execs |
| waiting on a child that ignores SIGTERM | 50 ms |

Two consequences:

- **One fork is worth a few hundred array lookups.** Removing forks beats shaving arithmetic.
- **Lookups add up.** A widget redraw is about 100 lookups, so about 300 µs. Do not redraw widgets you did not change.

## 3. Measure first

Never tune by feel.

```bash
tools/bench/page_switch.sh 40          # headless: render, layout, flush spans, bytes per switch
tools/profiler/profile.sh --scenario nav --rounds 5     # the real app in a pty: latency per interaction
tools/profiler/profile.sh --deep       # also a per-function trace, forks per call site
```

In your own app: `_tui_perf.begin NAME` / `_tui_perf.end NAME` around a phase, `tui.perf.report`, or `TUI_PERF_LOG=FILE`. The profiler report lists **forks per call site** (`attr.forks`) and **time per function and per page**; read those two first. Compare against the run before your change, not against a feeling.

A trivial page still costs about 120 ms to revisit in the profiler: about 23 ms cache replay, 28 ms render and about 33 ms of probe and settle overhead. Anything above that is page code or layout.

## 4. Callbacks: no forks on hot paths

"Hot" means: `on_visit`, tick callbacks (`tui.every`, `_TUI_TICK_FN`), input handlers, anything that runs per keystroke or per refresh.

### 4.1 Use `tui.capture` instead of `$( )`

```bash
# slow: a subshell per call
id="$(tui.get.focused)"
pos="$(tui.text.cursor wx_text)"

# fast: runs in the current shell, no fork
tui.capture id tui.get.focused
tui.capture pos tui.text.cursor wx_text
```

`tui.capture VAR CMD ARGS...` stores the stdout of `CMD` in `VAR` with trailing newlines stripped, exactly as `$( )` does. The status of `CMD` is returned. A widget status line that ran five captures every 0.3 s forked 17 times per second just to stay idle; with `tui.capture` it forks never.

Because `CMD` runs in the current shell, variables it sets stay set. That is almost always fine, but do not rely on `$( )` isolating a callee's globals.

### 4.2 Replace external programs with builtins

| instead of | use |
|---|---|
| `$(date +%H:%M:%S)` | `printf -v now '%(%H:%M:%S)T' -1` |
| `$(date +%s)` | `printf -v now '%(%s)T' -1` |
| `$(cat file)` | `$(<file)` (bash reads it, no fork) |
| `$(basename "$p")`, `$(dirname "$p")` | `${p##*/}`, `${p%/*}` |
| `$(echo "$x" \| sed 's/a/b/g')` | `${x//a/b}` |
| `$(printf '%s\n' "${arr[@]}")` | `printf -v out '%s\n' "${arr[@]}"` (then strip the trailing newline, see 4.4) |
| `$([[ cond ]] && echo on \|\| echo off)` | `if [[ cond ]]; then v=on; else v=off; fi` |
| `$(IFS=,; echo "${a[*]}")` | `local IFS=,; v="${a[*]}"` inside a function |
| `df \| tail -n +2 \| awk '{...}'` | one `df`, parsed with `read -r a b c d e f` |
| `$(nproc)` on every visit | compute once, see 5.2 |
| `awk` for integer arithmetic | `(( ))`; use awk only for floating point |

Pages that read `/proc` do it with `while read -r ...` loops, never `cat`, `grep` or `awk`.

### 4.3 What a fork-free callback looks like

```bash
_mon_refresh_disk() {
    local now_ts device pct target _hdr
    printf -v now_ts '%(%s)T' -1                    # was: now_ts="$(date +%s)"
    {
        read -r _hdr                                # one df instead of df | tail | awk
        while read -r device _ _ _ pct target _; do
            entries+=("${target##*/}:${pct%\%}")
        done
    } < <(df -P -x tmpfs -x devtmpfs 2>/dev/null)
    tui.capture bars hbar_string -w "$w" "${entries[@]}"   # was: bars="$(hbar_string ...)"
}
```

### 4.4 Behaviour to preserve

`$( )` strips **all** trailing newlines. `printf -v` does not. When you convert, strip them yourself so the text stays identical:

```bash
printf -v out '%s\n' "${lines[@]}"
out="${out%"${out##*[!$'\n']}"}"      # trailing newlines off, as $( ) did
```

`tui.capture` already does this. Compare old and new output byte for byte after a conversion; the demo conversions were all checked that way.

## 5. Do not repeat work that cannot have changed

### 5.1 Memoise static output, keyed on its inputs

Renderer output (`banner`, `table`, `hbar`, ...) depends only on its arguments and the renderer width. Build it once per width:

```bash
declare -gA _SC_ALL_MEMO            # NO "=()": see below

show_all() {
    local key="${TR_WIDTH:--}|$_SC_W"
    if [[ -z "${_SC_ALL_MEMO[$key]+x}" ]]; then
        # ... build "$out" with tui.capture ...
        _SC_ALL_MEMO[$key]="$out"
    fi
    tui.output output "${_SC_ALL_MEMO[$key]}"
}
```

The key must contain **everything** that changes the output (here the width). A result that depends on data (a live value, a file that may change) is not memoisable; leave it uncached.

### 5.2 Scripts are re-sourced on every visit

A page's `<script>` runs again each time the page is entered. Two consequences:

- `declare -gA memo=()` **resets** the memo on every visit. Write `declare -gA memo` without a value: it creates the array once and keeps it.
- Anything expensive at the top level of the script runs per visit. `_MON_NPROC="$(nproc)"` forked on every visit; guard it:

```bash
declare -g _MON_NPROC
[[ -n "$_MON_NPROC" ]] || _MON_NPROC="$(nproc 2>/dev/null || echo 1)"
```

### 5.3 Cache on content, not on counters

When you cache a result, key it on the inputs that produce it. Do **not** rely on "I bumped a version counter whenever X changed": one mutation path that forgets to bump leaves a stale screen that is hard to find. The framework follows this rule (row, geometry and line-slice caches are keyed on their inputs), and a stale entry is then impossible by construction. A wrong key can only cost a miss, never a wrong result.

### 5.4 Compute interval text once

Text derived from a setting that changes rarely (a refresh interval, a label) does not need an `awk` on every refresh. Memoise it on the setting (`_MON_INTERVAL_S[$ticks|$poll]`).

## 6. Layout and widgets

- **Panes cost.** Each pane is drawn, laid out and key-hashed on every full render. Prefer fewer, larger panes; nest only where the structure is real. Do not add wrapper panes for spacing; use `hpad`/`vpad`.
- **Consistent geometry is cheaper.** The shared menu is 18% wide on every page, so its rectangles and the cached geometry for its 15 buttons are identical across pages and are reused.
- **Pick plain widgets for static content.** Labels, buttons and checkboxes with plain text are cached by the framework. A text containing `${expr}` is re-evaluated (and forks) on every draw and bypasses the cache; keep dynamic text in a variable you update with `tui.update`, not in an expression.
- **Do not restyle every frame.** A pane or widget fragment is cached under its geometry, text, state and the style strings it draws with, so a restyled widget only misses for itself, and an identical widget on another page (the menu, the header) hits. Restyling in a tick callback still recomposes what it touches on every frame, and the frame must be flushed. Style once, then change text.
- **Update, do not rebuild.** `tui.update ID TEXT` changes one widget. Rebuilding a tab strip or grid (`tui.tabs.build`, `tui.grid`) on every visit costs tens of milliseconds; build once and keep it when the content is unchanged.
- **Output panes.** Lines with colour are measured and sliced in bash and memoised per line, so scrolling back is cheap. Very large outputs (thousands of lines) still cost to split into lines; page or truncate long documents when the user does not need all of it at once.

## 7. Timers, ticks and background work

- A tick callback runs every iteration of the main loop. Keep it to a few builtins, and do the real work every N ticks (`_mon_tick` refreshes every 20 ticks). Make the work fork-free (section 4).
- `tui.every SEC FN ID` and `tui.after` are cheaper than a polling loop in a tick callback. Always cancel with `tui.every.cancel` when the page is left; a leaked timer is permanent idle cost.
- Nothing should repaint while the app is idle. A clock that updates once per second is fine; a blinking cursor or an animation timer is not. Idle must stay under 2 repaints per second.
- Processes started with `tui.exec` are killed when the page is left. An interactive shell ignores SIGTERM; the framework now follows up with SIGHUP, which turns a 55 ms wait into 11 ms. If you launch your own long-lived child, make it exit on SIGHUP or SIGTERM promptly.

## 8. What the framework does for you, and what defeats it

| mechanism | what it saves | what defeats it |
|---|---|---|
| page snapshot cache | parse and build on revisit, and the per-switch `stat` | an edited page or dependency is detected at start-up only; while the app runs the cache is trusted (`TUI_CACHE_TRUST=0` re-enables the live check); `<script>` and `on_visit` always run fresh |
| row cache (`_tui_rowcache`) | recomposing unchanged panes and plain widgets, about -45% render on a content-heavy page | `${expr}` texts, a changed style, geometry or text (only for the fragment concerned) |
| widget geometry memo | recomputing positions | a changed placement or size attribute, a resized pane |
| line-slice and width memos | re-measuring and re-slicing coloured output lines | new line text (it is a miss, not an error) |
| `tui.modal.dismiss` | re-rendering the page under a closing overlay (palette close 38 ms to 14 ms) | anything painting, restyling or resizing while the overlay is open (it falls back to the full repaint) |
| `TUI_ROWCACHE=0`, `TUI_DISMISS_REPLAY=0` | switch the caches off to check whether one causes a problem | |

Use `tui.modal.dismiss` for esc and click-outside. Use `tui.modal.close` when a command runs after the close, because the saved page cannot know what the command changes.

## 9. What the demo gained

Two deep profiler runs, 5 rounds, settle medians (same machine and size): `195825` before and `201315` after the demo page changes (fork-free callbacks, memoised static output, one navbar width).

| | before | after |
|---|---|---|
| page switch by key (`alt+2`, components) | 201 ms | 106 ms |
| page switch, first visit | 204 ms | 184 ms |
| page switch, revisit | 168 ms | 156 ms |
| settings, first visit | 278 ms | 176 ms |
| components, revisit | 215 ms | 157 ms |
| monitor, revisit | 228 ms | 186 ms |
| theme switch, first use | 242 ms | 215 ms |

Interactions the changes did not touch (hover, focus, click, scroll, palette, resize, startup) did not move (within 3%).

In the demo, each of these paid off most:

1. The `show_all` renderer view built 13 renderers through `$( )` on every visit. Fork-free and memoised per width it went from the largest item on the page to one lookup.
2. The monitor refresh forked about 20 times per refresh, once a second (`date`, `awk`, a capture per chart and per colour list, `df | tail | awk`, one per pane in the output trimmer). It forks once now (`df`); `nproc` runs once per process.
3. `wx_status_tick` and `_lab_state` run several times per second on their pages and forked 5 and 3 times per run. They fork none.
4. Leaving the Terminal page waited 50 ms for a shell that ignores SIGTERM.

## 10. Checklist

Before you ship a page, run the profiler on it and check:

- [ ] No `$( )`, `date`, `cat`, `awk`, `sed`, `basename` or `nproc` in `on_visit`, tick callbacks or input handlers. Use `tui.capture` and builtins.
- [ ] Static output is memoised on every input that affects it; `declare -gA memo` without `=()`.
- [ ] Nothing expensive at the top level of a `<script>` (it runs on every visit).
- [ ] No `${expr}` text in widgets that redraw often; no `tui.style` in tick callbacks.
- [ ] Timers started on visit are cancelled on leave; the page repaints nothing while idle.
- [ ] Pane count and nesting are no more than the layout needs; the menu width matches the other pages.
- [ ] Old and new output compared byte for byte after any refactor of rendering code.
- [ ] Before and after profiler numbers recorded for anything you call an optimisation.

See also: [Callbacks and interactive viewports](callbacks-and-viewports.md), [Grids and tabs](grid-layouts-and-tabs.md), the measurements in [performance-progress](../concepts/performance-progress.md) and the design background in [cheap-redraws-concept](../concepts/cheap-redraws-concept.md).

## 11. Lessons from the page-switch floor

Measured on the trivial pages (home, layout, case study), where no page code runs: a switch fell from 136 ms to 86 ms by removing framework work, not page work. What carried over to app code:

- **Key a cache on what the result depends on, then count the hits.** A fragment cache keyed on a counter that every page switch bumped never hit across pages (57 stores per switch) while a repeat-render benchmark looked fine. A key made of the real inputs (geometry, text, the style strings) lets identical elements on different pages share one entry.
- **Do the rewrite once, where the data is produced.** The page snapshot was reformatted line by line on every replay; moving that step to record time cut the restore from 9.5 to 2.6 ms. Look for transformations of data that never changes.
- **Do not repeat work whose inputs did not change.** The footer row, its key-hint map, the terminal size and the layout of a replayed page are all functions of inputs that rarely change; each is now skipped (or rebuilt) when its inputs differ, compared by content.
- **Price a suspect untraced before you fix it.** `xtrace` inflates in-shell time unevenly: it blamed 6 ms on re-sourcing page scripts that costs 0.5 ms. Use the trace to find candidates, a timed loop to price them, and `tools/profiler/profile.sh --scenario floor` to see the breakdown of one switch.
