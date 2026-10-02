# Making Sisyphus Redundant: Write-Ahead Logging and Deterministic Replay in Pure-Bash Terminal Interfaces

Its companion documents address the cost of moving a fixed viewport, the
cost of locating a pointer, and the cost of composing layout without
hand-authoring every element. Each takes for granted that the page under
discussion already exists. In practice it did not, reliably, on any
visit after the first: `tui.goto` reached a page by the same procedure
every time, including the fourth, fifth, and fortieth visit to a page
already constructed once earlier in the same session. `tui.reset_ui`
discarded every pane and widget record; `tui.load` re-read the markup
file from disk and re-derived, one regular-expression match per
attribute, the identical pane tree it had derived a minute before;
`tui.render` repainted the result. Measured across eleven pages, this
cycle cost between six hundred milliseconds and 1.2 seconds per switch,
of which approximately ninety percent was attributable to re-parsing
rather than to rendering or layout arithmetic. A user returning to a
page already visited was not being shown that page. The page was being
reconstructed from source material in front of them, because nothing
about its first construction had been retained.

> **How this page relates to the code today.** The reasoning below is why the page cache exists, and it still holds. The mechanism changed twice since it was written. The first version logged every builder call and replayed the log with `eval`. Since markup-v2 stage 1 the loader tokenizes a page into a node tree and builds it through registered tag handlers, and the cache stores the *result*: a `declare -p` snapshot of exactly the variables a build touches, restored with one `eval`. The "Implementing the Log" section describes that, and what stayed a logged call. Page changes made while the app runs (addons, generated content) no longer go through the cache at all: they are applied to the page on screen, see [Pages, templates, addons and refresh](pages-templates-addons-refresh.md).

## The First Hypothesis: Cache the Rendered Image

The most immediate remedy presents itself because `tui.render` already
performs an operation that resembles half the work: it walks every pane
and widget and assembles a single string, assigned in `tui.sh` as
`buf="$(...)"`, which is then passed whole to `_tui._flush`, wrapped in a
synchronized-update block, and written once. A single flushable string,
constructed once per frame, invites the conclusion that it should simply
be retained. Keep the string produced by the first visit; on the second
visit, omit the walk and print the retained string directly.

This hypothesis does not survive two properties the framework already
depended on being true. First, every line of that string is positioned
by absolute cursor addressing, `cur.goto "$r" "$c"`, where `$r` and `$c`
are drawn from `_TUI_P_ROW` and `_TUI_P_COL`, themselves the product of
`_tui._layout` computed against whatever `term.size` reported at the
moment the page was built. A string cached at one terminal geometry is
not a representation of the page in general; it is a representation of
the page at that specific width and height, and printing it unmodified
into a terminal of different dimensions does not resize the interface,
it corrupts it. Second, and more consequentially, a rendered image is
not equivalent to a page. Locating the pane under a mouse click, cycling
keyboard focus, redrawing a single pane in response to a `tui.tick`,
routing a live `tui.exec` process's output into the pane responsible for
displaying it: none of these operations act upon pixels. Each acts upon
the pane and widget records, `_TUI_P_*` and `_TUI_W_*`, that produced the
image in the first place. If only the image is retained, the instant a
user does anything beyond observing the screen, there remains nothing
beneath the image to interact with. The rendered frame was never the
expensive artifact worth preserving. It was the least expensive product
of `tui.load`, and the last one that required preserving.

## The Second Hypothesis: Cache the Internal State

If the rendered image is downstream of the state that actually matters,
the state itself becomes the natural candidate for caching: serialize
the pane and widget arrays with `declare -p` after a genuine `tui.load`,
restore them verbatim on the following visit, and omit the parse
entirely. This hypothesis is closer to correct and further from safe.
Some of that state is not a clean object to serialize in the first
place: `_TUI_PANE_CONTENT_<paneid>` is a `declare -n` nameref addressing
a dynamically named global, so restoring the reference without also
correctly reconstructing the target array under its precise generated
name restores a pointer to nothing. Some of it is actively unsafe to
replay twice: the identifier counters behind `tui.factory.*`
(`_TUI_FACTORY_COUNTER`) are monotonic across the lifetime of the
process, not the page, so a snapshot captured after one execution of
`on_visit` and restored before a second execution produces identifiers
that either collide with, or diverge from, whatever the second execution
generates independently; two notionally identical copies of the same
dynamic grid cease to agree about their own contents. And some of it
cannot be restored under any circumstance, as a matter of principle
rather than implementation difficulty: a `tui.exec` instance owns a live
process identifier, an open file descriptor, and a directory created by
`mktemp -d`, all of which terminate with the process that created them.
A snapshot of a running terminal's process handles does not transfer to
a later moment; it is a record of a moment that has already concluded.
To cache the internal state is to cache artifacts that were never
intended to outlive the transaction that produced them, which is the
same error committed by the first hypothesis at a different layer:
retaining the result of a computation rather than the computation
itself, and discovering, one failure at a time, every place where a
result depended silently on the exact circumstances of its own creation.

## What a Database Administrator Would Have Recognized Immediately

Neither hypothesis represents a novel error. Both repeat a problem that
every durable database system resolved long before the question of
caching a pure-bash terminal interface arose. A database does not
achieve durability by retaining a permanent in-memory copy of every row
it has ever held; that approach is the rendered image, unaffordable at
scale and incorrect the instant the underlying data changes. Nor does it
achieve durability by discarding the day's data whenever no client is
connected and having a clerk retype it from memory before service
resumes; that approach is precisely what `tui.load` had been doing,
substituting a regular-expression parser for the clerk. What a database
does instead is maintain a log of the operations that produced its
current state, an append-only record of instructions such as "insert
this row," and recover not by re-deriving the data from first
principles, nor by hoarding a frozen copy of it, but by replaying that
log, deterministically, against the most recent checkpoint it trusts.
The log remains inexpensive precisely because it is small: an `INSERT`
statement occupies fewer bytes than the row it produces, once multiplied
across every row a substantial table has ever contained, in the same way
that `tui.hsplit "root" "nav:20" "main:80"` is a few dozen bytes
describing a pane tree that, once expanded and rendered against a live
terminal, constitutes considerably more state than the instruction
itself.

`tui.load` was never computing anything new. Every visit to `home.xml`
produces the same sequence of `tui.hsplit`, `tui.label`, and `tui.button`
calls, in the same order, because the markup driving it has not changed
between visits. The parser was not deriving structure so much as
transcribing an unchanged structure from an unchanged source, by hand,
on every single visit, in the manner of a clerk with no memory of
yesterday retyping today's figures from a receipt that has not moved.
The artifact worth retaining was never the image and never the internal
state. It was the transaction log, the sequence of operations, present
the entire time inside the one function that already traversed the
markup tag by tag in order to call `tui.hsplit`, `tui.label`, and
`tui.button` and thereby construct it.

## Implementing the Log

The first implementation did what the analogy suggests: `lib/markup/tui_cache.sh` renamed about twenty builder functions (`tui.hsplit`, `tui.label`, `tui.button`, ...), wrapped each so that it appended a `printf %q` record of its own call to a buffer, and replayed a page by `eval`-ing the recorded lines. It worked, and it taught three lessons that shaped what replaced it. Nested calls (`tui.grid` calls `tui.vsplit`) had to be recorded once, at the outermost level, or replay divided a pane twice. Anything with a side effect that did not go through a wrapped function (a `<button page=...>` handler defined by a bare `eval`) was missing after a replay, and the button existed but failed with `command not found`. And every new builder had to be added to the wrapper list by hand, or its calls were silently absent from the log.

All three come from recording calls. Since markup-v2 stage 1.3 the cache records **state** instead, and the second hypothesis above, rejected as a naive idea, is the one that works, once its objections are answered one by one:

- The loader builds the page from a node tree, so what a build changes is a known, finite set of variables: everything whose name starts with `_TUI_P_`, `_TUI_W_`, `_TUI_STYLE_`, `_TUI_TABS_`, `_WX`, `_TX` and a few exact names (`_TUI_FOCUS_ID`, `_TUI_FOCUSABLE`, ...). They are found by prefix, so a new widget's arrays are covered without a list to maintain.
- Their `declare -p` form is rewritten **once, at record time**, to `declare -g`, so a replay is a single `eval` of a prepared string.
- The objections to snapshotting state do not apply. Pane output (`tui.output`) is produced at run time by callbacks, after the replay, so the per-pane content arrays that were namerefs are not part of a snapshot. The factory counter is reset with the page and consistent with the snapshot. A running `tui.exec` instance belongs to the page it was started on, is dismissed when the page is left and is never part of a snapshot.
- What cannot be state stays a recorded **call**, individually replayed and fresh on every hit: sourcing the page's `<script>` files, running `on_visit`, defining the handlers of `<button page=...>`, and applying classes (`tui.class ID CLASS`, so that a theme switch reaches the baked colours of a cached page). That is the write-ahead log that remains: a handful of entries per page, each a call that must run again because its effect is not a pure function of the markup.

The snapshot also carries what [`tui.page.refresh`](../api/core/tui.page.refresh.md) needs to change the page later without parsing it: the raw node tree and the per-pane signatures of what was built.

## Checkpoints, and the Conditions Under Which They May Be Distrusted

A log replayed indefinitely without verification against the artifact it
describes eventually diverges from that artifact: a page edited on disk
after being logged is a page whose log now describes a version of the
file that no longer exists, and replaying that log faithfully reproduces
an incorrect page, faithfully. Every recorded page's log carries a
signature: the modification time of the page file itself, together with
the modification time of every `<include>` it drew upon, discovered
through a dedicated traversal (`tui.cache.deps_of`), plus every addon
file and the addon folders (a directory's modification time changes when
a file is added or removed, which is how a new addon is noticed). Before a replay proceeds, this
signature is compared against the filesystem (since DevEx Update 1.87,5 this happens
at start-up only: once every page is validated and warmed the cache is trusted for
the rest of the run, and files are assumed not to change while the app is running,
unless `TUI_CACHE_TRUST=0`); any discrepancy, whether
in the page itself or in a shared fragment edited since the page was
last recorded, is treated as absence rather than as stale but usable
data, and control passes through precisely the path taken by a page that
was never cached at all: a genuine `tui.load`, which repopulates the log
for subsequent use. A cache miss, including one caused by staleness, is
never a distinct code path from "no cache yet exists." It is the same
path, entered for a different reason, and this identity is what renders
the entire mechanism safe under error: a stale log is never trusted into
producing an incorrect page. It is simply an occasion to write a correct
one.

This same signature is what justifies persisting the log to disk rather
than reconstructing it once per process. `tui.start_cached` loads
whatever has already been checkpointed in `$TUI_HOME/cache/pages/`, validates
each entry against current modification times, and warms, in a pool of
background workers (one per stale page, as many at once as there are
cores), behind a banner and a progress indicator (the only
component of this design intended to be observed rather than forgotten),
only those pages found to be missing or invalid. A session in which
nothing has changed loads its entire log from disk in well under a
second and warms nothing further. A session in which a single page was
edited re-derives that one page and leaves the remaining ten checkpoints
untouched. This is, again, not a novel technique. It is the same
practice by which a database takes a complete backup once, and
thereafter transmits only the write-ahead log entries describing what
has actually changed since the backup was last trusted.

## The Analogy, Concluded

Sisyphus was condemned to push a boulder to the summit of a hill, watch
it roll back to the bottom, and begin again, the labor renewed in full
on every cycle regardless of how faithfully the previous cycle had been
completed. The punishment was never located in the difficulty of any
single ascent. It was located in the fact that the ascent counted for
nothing once finished, so that the thousandth repetition demanded
exactly the effort the first had, with no advantage carried forward from
one climb to the next. This was the prior behavior of `tui.load`:
correct on every visit, and incapable of distinguishing a page already
constructed from a page never previously encountered, because nothing
was ever retained for comparison, so every visit paid the full price of
the first. The competing proposal, to leave the boulder permanently
wedged at the summit, or to keep a perfect memory of the climb so that
the climb itself need never be repeated, fails for a related reason: a
boulder fixed at one summit is correct only for that summit, and becomes
wrong the instant the mountain changes shape beneath it, while a memory
of the climb, never checked against the mountain it describes, eventually
diverges from a mountain it no longer accurately remembers. What
functions correctly, on a mountainside and equally in a terminal
interface that ought not repeat a computation it has already performed
once, is the less dramatic alternative: record the ascent, not the
boulder's final position and not a frozen memory of the climb itself,
verify the record against the mountain before trusting it, and replay
the ascent only when the mountain has not moved. Sisyphus is not
relieved of his task because the boulder has become lighter. He is
relieved of it because pushing was never the part of the labor worth
repeating. Writing down the route was, and once the route is written
down, walking it again costs a few milliseconds and arrives, by
construction, exactly where the summit was.
