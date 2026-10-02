### `tui.page.refresh`

```bash
tui.page.refresh
```

Re-applies the [addons](/guide/markup.html#addons) on disk (and re-runs templates and loops) on the page that is on screen, and rebuilds only the panes whose content changed. A page switch has 100 ms; so does this.

**Returns:** `0` when the screen is up to date, also when nothing changed.

**Notes**

- Every page remembers the tree it was built from, so a refresh starts from that instead of parsing the page's files again, which alone would take longer than the budget. It compares the result with what is on screen pane by pane and rebuilds a pane when its own attributes, its widgets or the weights of its child panes changed. Everything below a rebuilt pane is rebuilt with it. Typed text, ticked boxes and focus in the panes that did not change stay as they are.
- The cost follows what changed, not the size of the page: on the Addons demo page (150 x 45), enabling one addon takes about 45 ms plus the redraw, five at once about 70 ms, and a refresh with nothing changed about 30 ms. Rebuilding generated widgets costs roughly 1.5 to 3 ms each.
- When a change cannot be applied this way, the page is rebuilt in the background instead ([`tui.page.rebuild`](/api/core/tui.page.rebuild.html), with the spinner of [`tui.job.run`](/api/core/tui.job.run.html)). That happens when something outside the panes changed (a widget written directly under `<tui>`), when the root pane or a pane without an `id` would have to be rebuilt, or when the changed part contains `<tabs>` or another tag the incremental build does not handle. Give panes an `id` if addons are to change what is inside them.
- A widget written outside all panes with `pane="x"` ties pane `x` (and the panes above it) to a full rebuild. Nest widgets inside their pane to keep them refreshable.
- Afterwards the cached copy of the page is brought up to date by a quiet background job; a visit to the page before that finishes rebuilds it.

**Example**

```bash
cp new_banner.xml "$TUI_APP_CONF/addons/banner.xml"   # switch an addon on
: >"$TUI_APP_CONF/addons/old_addon.xml"               # switch one off (an empty file adds nothing)
tui.page.refresh                                      # the screen follows
```

**See also:** [`tui.page.rebuild`](/api/core/tui.page.rebuild.html), [`tui.addon.dir`](/api/core/tui.addon.dir.html)
