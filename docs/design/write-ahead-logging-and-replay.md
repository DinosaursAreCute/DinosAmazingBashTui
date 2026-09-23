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

`lib/markup/tui_cache.sh` renames every builder function `tui.load` invokes,
`tui.hsplit`, `tui.label`, `tui.button`, and roughly twenty others, to
`_tui_cache_orig.$fn`, and redefines the original name as a thin wrapper
that appends a `printf %q`-quoted record of its own invocation to a
buffer before delegating to the renamed original. This is not
equivalent to `declare -p` of the arrays those calls eventually
populate; it is a transcript of the calls themselves, each already a
proven, already idempotent element of the public interface, comparable
to logging `INSERT INTO panes VALUES (...)` rather than reproducing the
table's underlying storage pages and hoping they reattach correctly
elsewhere. Replay consists of `eval` applied to the saved lines, in
order, with no markup parsing and no disk access beyond reading the log
itself.

A write-ahead log must define what constitutes a single operation, and
must define that boundary correctly, or replaying the log corrupts the
state it exists to recover. `tui.grid` calls `tui.vsplit` and
`tui.hsplit` internally in the course of constructing itself; absent a
nesting guard, recording the outer `tui.grid` invocation together with
its inner `tui.vsplit` and `tui.hsplit` invocations as three independent
log entries causes replay to execute the split three times over, the
same pane divided again against its own already-divided children. This
is equivalent to a log that recorded both a transaction's net effect and
every statement composing it as separate, independently replayable
entries. `_TUI_CACHE_DEPTH` addresses this by recording only the
outermost call in any nested chain, precisely the granularity at which
`tui.load`'s own dispatch loop already operates, no finer, which is also
where a correctly bounded log's transaction boundary belongs. The same
depth guard preserves dynamic content as dynamic without additional
mechanism: `on_visit` and `<script src>` sourcing are themselves logged
as single operations, instructing replay to "execute this," so their own
internal widget-construction calls, occurring one level deeper, are
never individually logged and therefore never individually replayed.
Replay executes the operation live on every occasion, in the manner of a
trigger that fires afresh on every transaction satisfying its condition,
rather than one whose historical output has been recorded permanently
into the log.

Two defects arose from the inverse error: an operation with a genuine,
observable side effect that never entered the log at all, the
write-ahead-log equivalent of a schema alteration applied manually,
outside the migration history, of which recovery retains no record. A
`<button page="...">` element's click handler had been defined by a raw
`eval` situated directly within `tui_markup.sh`'s dispatch loop, entirely
outside any logged call, invisible to the recording mechanism in the
same manner that an unlogged `ALTER TABLE` is invisible to a replica
replaying a log that never mentioned it. Replaying a cached page
correctly reconstructed the button itself. It retained no record of the
handler the button was meant to invoke, since that handler had never
been written to the log; the button existed, and invoking it failed with
`command not found`, the recovered schema referencing a migration that
had never been logged. The correction follows the same pattern as
before: the `eval` is wrapped in `_tui_cache_define_goto`, which is added
to the set of recorded functions, so that the operation creating a
page's navigation becomes a logged operation like any other. The second
defect concerned not what was logged but whether the log's own
bookkeeping could subsequently be read. `_markup_expand` tracks which
files it has already visited during a given load, specifically to detect
`<include>` cycles, a mechanism entirely correct for that purpose and
entirely unusable by anything attempting to read that tracking data from
outside, because `_markup_expand` executes inside `<(_markup_expand
"$file")`, a process substitution, which is a subshell. A subshell's
variable assignments are genuine and internally consistent, and vanish
completely the instant it exits; the data existed correctly for exactly
as long as nothing outside that one execution context could observe it,
which resembles a replication stream captured from a session that
disconnects before its writes are flushed to disk: technically produced,
practically unrecoverable. The correction was not to make the existing
tracking mechanism visible from outside, since its purpose was correctly
scoped to a single load and altering that scope would have compromised
cycle detection in order to repair an unrelated read. The correction was
to traverse the same information by a separate method, executed within
the caller's own shell, where the result remains observable.

## Checkpoints, and the Conditions Under Which They May Be Distrusted

A log replayed indefinitely without verification against the artifact it
describes eventually diverges from that artifact: a page edited on disk
after being logged is a page whose log now describes a version of the
file that no longer exists, and replaying that log faithfully reproduces
an incorrect page, faithfully. Every recorded page's log carries a
signature: the modification time of the page file itself, together with
the modification time of every `<include>` it drew upon, discovered
through a dedicated traversal (`tui.cache.deps_of`) rather than by
reusing the tracking mechanism described above, which remains
unobservable outside its own subshell. Before a replay proceeds, this
signature is compared against the filesystem; any discrepancy, whether
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
whatever has already been checkpointed in `.cache/tui_pages/`, validates
each entry against current modification times, and warms, in a
background worker, behind a banner and a progress indicator (the only
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
