# Pages, templates, addons and refresh

How a page file becomes widgets on screen, how pieces of a page are reused and changed, and how a page that is already showing is updated inside the 100 ms budget of a page switch. This is the technical background for [Pages: the markup format](../guide/markup.md) and the API pages [`tui.page.refresh`](../api/core/tui.page.refresh.md), [`tui.page.rebuild`](../api/core/tui.page.rebuild.md) and [`tui.job.run`](../api/core/tui.job.run.md). The page cache this builds on is in [write-ahead-logging-and-replay.md](write-ahead-logging-and-replay.md).

## 1. The pipeline

```
 page file(s)
     │  tui_parse.sh      tokenize once, splice <include>s, record file:line      → node tree (raw)
     │  (raw tree is saved here: _TUI_P_RAW)
     │  tui_addon.sh      apply addon files from disk to the tree                  → node tree
     │  tui_compose.sh    expand <use>, <component>, <for>, <if>                   → node tree (plain tags only)
     │  tui_build.sh      walk the tree, one registered handler per tag            → engine arrays (_TUI_P_*, _TUI_W_*)
     │  tui_refresh.sh    sign what was built, pane by pane                        → _TUI_P_SIG_*
     ▼
 page snapshot (cache): the engine arrays + the raw tree + the signatures
```

Every stage takes and returns the **node store** (`tui_node.sh`), a struct-of-arrays tree: a node is an integer; `_N_TYPE`, `_N_PARENT`, `_N_KIDS`, `_N_ID` are plain arrays, attributes live in one associative array keyed `"node.attr"`, and `_N_ANAMES[node]` lists a node's attribute names. All mutation goes through `tui_ops.sh`.

Nothing here forks. The parser walks the file with parameter expansion and one regex per tag; `clone`, `remove`, `params` and the template substitution touch only the attributes of the nodes concerned, through `_N_ANAMES`, instead of scanning every attribute of the page (that scan was the main cost of the first version).

## 2. The node operations

`tui_ops.sh` is the only code that changes the tree, and every feature below is built from it.

| Operation | |
|---|---|
| `select ROOT SEL` | `#id`, `.class`, `tag`, combined as `tag#id.class`, `A B` (below) and `A > B` (directly below). A lone `#id` is one lookup. |
| `clone_all PREFIX N...` | deep copies, ids prefixed; one pass for any number of nodes |
| `insert append/prepend/before/after`, `replace`, `remove`, `move`, `wrap`, `set` | |
| `params`, `subst_all` | `{{@name}}` substitution; one pass; replacements are quoted so that a value containing `&` stays literal (bash 5.2 treats an unquoted `&` in `${v//a/b}` as "the matched text") |

## 3. Reuse: templates, loops, addons

**Compose** (`tui_compose.sh`) runs over the whole tree. It first collects every `<template>` and `<component>` and detaches them from the tree. It then walks the document by position and replaces each directive by what it expands to, re-reading the child list after each replacement so the new nodes are expanded in turn:

- `<use template="t" id="x" p="v">`: the template's children are cloned with the prefix `x_`, the parameters (template defaults, then the attributes of the `<use>`) are substituted, `<slot>`s are filled from the use's `<fill>`s or loose children, and the use is removed. A node that can expand again carries a `__via` path of the templates it came from; a template that reaches itself is cut off there and reported.
- `<for each|count>` clones its body once per item with `as` and `index` substituted. `<if test>` keeps one branch. Both are decided at load time.
- After an `<if>` drops a branch, the ids of the kept branch are re-registered, because both branches may use one id and the drop would otherwise remove it from the by-id index.

**Addons** (`tui_addon.sh`) are files of ops (`append`, `prepend`, `before`, `after`, `replace`, `remove`, `set`, `wrap`) with a `ref` selector. They are read from `$TUI_APP_CONF/addons` and every folder given to `tui.addon.dir`, sorted by `priority` (lower first, so the higher number has the last word) and applied **before** compose, which is why addon content may use templates and an addon can set the `count` of a `<for>`. Inserted content is cloned with the addon's id as an id prefix. An empty file is skipped without a parse: that is how an addon is switched off.

Addon files and their folders are part of a page's cache signature (§6).

## 4. Updating a page that is showing: `tui.page.refresh`

The task: an addon is switched, or a setting that drives a `<for>` changes; the screen must follow within 100 ms. Parsing the page again costs more than that alone, and rebuilding every widget costs more still. The refresh therefore never parses and rebuilds as little as it can.

**What a page remembers.** `_TUI_P_RAW` is the dump of the raw tree (taken right after the parse, before addons). `_TUI_P_SIG_OWN`, `_TUI_P_SIG_FULL` and `_TUI_P_SIG_PLAIN` hold, per pane key (its id, or a path for a pane without one), a signature of the tree that was built:

- **own**: the pane's tag and attributes, its non-pane children (the widgets, serialised with all attributes), and for its child panes only their key and the attributes that matter to the parent's split (`weight`, `width`, `height`, `grid_row`, `grid_col`, `span`, `newline`);
- **full**: own plus the full signature of every pane below;
- **plain**: 1 when nothing below uses a tag the incremental build cannot handle (anything but panes and the ten widget tags);
- **top**: everything outside all panes (flat widgets, binds, scripts), as one string.

All of these live in variables named `_TUI_P_...`, so the page snapshot carries them and a page restored from the cache can be refreshed too.

**The algorithm.**

1. Load the raw tree back (`tui_node.load`), apply the addons on disk, run compose.
2. Sign the result the same way.
3. Compare. Starting at the top panes: if a pane's **own** signature differs (or the pane is new), it is a *target*. If its own signature is equal but its full signature differs, the change is below it: look at its child panes. Equal full signature: nothing to do.
4. For each target: tear down the engine state of everything below it (`_tui_engine.forget_below`: widgets, child panes, their baked styles, the target's own properties, set back to what a split gives a fresh pane), then build the target again from its new nodes with the ordinary tag handlers. Because the build is the ordinary one, the result is what a full load would give; the unit tests compare the two.
5. Put the new widgets back at the position of the old ones in `_TUI_W_ORDER` (document order is Tab order), clear focus or hover that pointed at removed things, mark the focus order and hit index stale (`_tui_w.changed`), lay out and draw.
6. Adopt the new signatures as the page's.

**When it gives up.** Any of these makes the refresh hand the work to `tui.page.rebuild` (§5), which builds the whole page in the background:

- something outside the panes changed (top signature);
- a target is the root pane, a pane without an id, or does not exist on screen;
- the target or its old or new subtree contains a tag outside the plain set (`<tabs>`, ...);
- a widget written outside all panes names the target pane, or one below it, with `pane="..."`: tearing the pane down would remove widgets that the target's own nodes do not recreate.

**The cache.** After a refresh the cached copy of the page is stale. It is dropped at once (a visit before the next step rebuilds it) and refreshed by a *quiet* background job (`tui.page.rebuild --quiet`: no spinner, nothing drawn). The user never waits for that.

**Cost.** The floor, with nothing changed, is about 27 ms: load the tree (3), apply addons (6), compose (17, mostly the shared header and menu templates), sign (7). Above it a rebuild costs 1.5 to 3 ms per widget created. One addon: about 45 ms. Five at once: 70 to 105 ms. A generated page of 3 x 2: 59 ms, 8 x 6: 209 ms, 20 x 9: 556 ms. Plus the redraw, about 15 ms at 150 x 45. See [Designing Fast Apps, section 12](../guide/performance.md#12-what-an-addon-or-a-refresh-costs).

**Why signatures and not a diff of the engine arrays.** The engine arrays contain things that are not in the markup (computed geometry, focus, typed text, scroll offsets) and things that change on their own. A signature of the *input* answers the only question that matters: "is what the markup says now different from what it said when this pane was built?". It also keeps untouched panes untouched: typed text and focus in them are not reset.

**Why synchronous.** The widgets have to be created in the running program; a background process cannot hand arrays to the main shell except by serialising them, and the serialising and loading would cost about what the build costs. The part that is slow in itself and independent of the screen (building a whole page to refresh the cache) does go to a process.

## 5. Background work: `tui.job.run` and `tui.page.rebuild`

`tui.job.run ID WORKFN DONEFN` starts WORKFN in a background subshell with stdin from `/dev/null` and stdout and stderr in files (`${TUI_JOB_PREFIX}out`, `err`, and `rc` written by the process when it ends). The main loop polls: while any job is pending, `_tui_job.tick` is registered as a tick listener, checks for the `rc` file with one `[[ -s ]]`, and when it exists reads the status, calls `DONEFN ID RC OUTFILE`, and truncates the files. No timers, no signals, no polling processes.

- **The spinner** is an overlay (`tui.overlay.add`), drawn in the top-right of the first row once a job has been pending longer than its delay (default 100 ms, `--delay`). The frame advances every 80 ms. It is switched off *before* DONEFN runs, because a render inside DONEFN draws the registered overlays and would paint the spinner back onto the new page; if DONEFN does not render anything itself, the page is redrawn so no spinner cell is left behind.
- **Nothing is drawn half-finished.** The work function cannot touch the screen (it is another process); the result reaches the screen only through DONEFN, in one go.
- **Same ID replaces.** Starting a job whose ID is pending kills the first (its files are not reused, so a late write cannot leak into the new run).
- **No processes of its own.** Files are created by redirects and removed once, with the temp root, at exit (the `exit` hook). The only process the module starts for itself is `mktemp` once per app run.
- `tui.page.rebuild FILE` is the job that runs `tui.cache.record` in the worker, sends the cache entry back as one blob, installs it in DONEFN and, if the page is still on screen, goes to it (`tui.goto` of the same page keeps the focused widget).

## 6. The cache signature

A page's signature is the modification time of every file it depends on: the page, each `<include>` (found by `tui.cache.deps_of`), and every addon file and addon folder. A folder's time changes when a file is added or removed, so a new addon is noticed without listing the folder on every load. The signature is checked at start-up; afterwards the cache is trusted (`TUI_CACHE_TRUST=0` keeps checking), which is why a page changed on purpose while the app runs uses `tui.page.refresh` or `tui.cache.forget`, not a file touch.

## 7. How it is tested

- `tests/unit/ops.t.sh`, `compose.t.sh`, `addon.t.sh`: the operations, every directive and every addon op on small fixtures.
- `tests/unit/refresh.t.sh`: the central property. A page refreshed from "none" to "all five addons" and back equals a full load in both directions (a sorted dump of all pane and widget arrays plus the widget order); the Generated page refreshed equals a full load and keeps what was typed outside the regenerated pane; focus on a removed widget is cleared; a change outside the panes falls back to a rebuild; a no-change refresh rebuilds nothing; the compute part stays under 100 ms.
- `tests/unit/job.t.sh`: results, exit status, cancel, replacement, the spinner's lifecycle and that it is gone before DONEFN.
- `tests/unit/docs_examples.t.sh`: the page examples in the guides validate.
- `tools/profiler/profile.sh --scenario addons` and `--scenario generated` rate the real app against the 100 ms budget.

## 8. Limits and the next steps

- The redraw after a refresh is a full frame. Painting only the rebuilt panes' rectangles would save most of the 15 ms; it needs a check that nothing outside moved.
- `<tabs>` and anything not in the plain set force the background rebuild. Supporting them in place means giving them signatures and teardown of their own state.
- Anonymous panes cannot be targets; the answer is an id.
- Factories (`tui.factory.*`) still use their own bookkeeping to create and drop widgets; they are the natural next client of the node operations.
- A generated page (see the Board tab of the Compose demo page, `share/demo/compose.xml`) is bound by what bash can create per widget. A list or table widget holds any number of rows in one widget; use it for long lists.
