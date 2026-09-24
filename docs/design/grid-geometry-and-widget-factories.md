# Asserting Dominance on a Small Village by Building a Scalable Production Line: Compositional Grid Geometry, Reusable Container Abstractions, and Runtime Widget Factories in Pure-Bash Terminal Interfaces

Its two companion documents addressed making a fixed viewport move
smoothly and making a pointer's location cheap to know. This one
addresses a quieter problem, the kind that doesn't show up as lag or a
stack trace: a framework that can only be *authored*, one identifier at a
time, doesn't compose. Every new layout need - a row of buttons, a
tabbed panel, a list whose length depends on data the page can't see
until it runs - either got hand-built from scratch or hand-built by
copying the last hand-built thing and hoping the copy stayed faithful.
`share/demo/components.xml`'s toolbar is six sub-panes, individually
declared, each holding exactly one button. `share/demo/case_study.xml` and
`share/demo/docu.xml` each independently reinvented "a row of buttons that
swap a content pane," diverging in the small ways two authors always
diverge when neither is working from a shared abstraction. Multiplying a
village of individually-tended plots was the entire method. This
document is about replacing that with a production line: a small set of
composable primitives that can stamp out as many uniform cells as a
layout needs, hand nothing to the author that isn't already load-bearing,
and stay honest about what they cost.

## The Village: What Hand-Authoring Every Element Actually Costs

### Boilerplate That Scales With Content, Not With Complexity

A row of N buttons is not a complex layout. It's the same layout N times.
But the markup format has no way to say "N times" - it can only say
"here is pane one, here is pane two," literally, once per pane, with a
`weight="1"` and a `border="none"` repeated verbatim each time. The
`components.xml` toolbar is not hard to read; it is merely long in a way
that carries no information. Every one of its lines is inferable from the
one before it. A format that requires an author to write down inferable
information is a format that will eventually be wrong in exactly the
place the author got bored transcribing it.

### Markup Cannot Describe What It Cannot See

A more fundamental limit sits underneath the boilerplate: XML-style
markup is parsed once, at load time, and every id it declares must exist
in the text of the file. This is fine when the shape of a layout is
known when the page is written. It is not fine for "one tab per document
this program happens to find on disk," which is not a fact about the
page, it's a fact about the filesystem at the moment the page loads.
Before this work, `docu.xml` handled that mismatch the only way static
markup can: by pretending the mismatch didn't exist. Four tabs were
hand-declared, matching whatever four documents existed on the day
someone last edited the file. The fifth document this session's own
scrolling-architecture writeup produced didn't get a tab. Not because
anyone decided it shouldn't - because nothing was watching for it. A doc
page that requires editing itself every time the docs change is not
documentation tooling, it's a second copy of the docs' table of contents,
manually kept in sync by whoever remembers to.

### Divergent Reinvention

`case_study.xml` and `docu.xml` both needed "clickable headers that swap
a content pane." Neither reused the other's implementation, because there
was no implementation to reuse - only a pattern, visible if you squinted
at both files side by side, that each page's author had re-derived from
first principles. This is the predictable outcome of a framework that
provides primitives (panes, buttons, `tui.output`) but no vocabulary for
the *compositions* of those primitives that keep recurring. Every
recurrence is a chance for the two implementations to drift: different
row numbers, different button ids, a content pane whose title gets set in
one version and forgotten in the other. None of that is a bug in either
file. It's a bug in not having a shared abstraction for the thing both
files were independently trying to build.

## The Production Line: Composing Existing Primitives Instead of Inventing New Ones

### Sugar, Not a New Engine

The temptation, faced with "authors keep hand-writing grids of panes,"
is to design a grid *rendering* system: a new layout algorithm, a new
class of node in the render tree, a new thing `_tui._draw_pane` has to
know about. That temptation was declined. A grid is a `vsplit` of rows,
each an `hsplit` of cells - the exact same recursive splitting primitive
every layout in this framework already goes through. Nothing about
hit-testing, rendering, or the hover/focus machinery this codebase spent
considerable effort making cheap needed to learn a new concept, because
as far as any of that machinery is concerned, a grid cell is a pane like
any other. The entire feature is a smarter way to *ask* for a tree of
panes, not a new kind of tree.

### Separating "What Was Asked For" From "How To Build It"

Grid placement has to answer two different questions that are easy to
conflate: which cell does each child belong in (a question about the
*author's intent* - explicit coordinates, or document order, or a mix),
and how large should each row and column actually be (a question of pure
arithmetic once the assignment is settled). Keeping these as two
separate steps - the markup parser resolves intent into a flat,
already-decided list of names; `tui.grid` turns that flat list into
geometry, and does not know or care whether a name arrived there by an
author's explicit `grid_row`/`grid_col` or by falling into the next open
slot - means the geometry primitive stays reusable by something that
isn't the markup parser at all. `tui.factory.grid` needed exactly that:
a caller that only knows a count, not a set of authored intentions,
building the same geometry through the same function.

### A Composite Widget That Isn't One

`<tabs>` looks, from a markup author's perspective, like a new kind of
UI element. From the renderer's perspective, it doesn't exist: a tab
header is a button, sitting in a grid cell, and "the active tab" is
nothing more than *that button currently has keyboard focus.* This
reuses, rather than duplicates, a whole subsystem: whatever a theme
already does for `.class:focus` is what shows a tab as active, with no
second notion of "selectedness" to keep synchronized with focus and no
new code path in `_tui._draw_widget`'s dispatch. The lesson generalizes
past tabs specifically - the cheapest new feature is the one that turns
out, on inspection, to already be expressible as a configuration of
features that exist. A feature that needs its own rendering branch is a
feature that inherits every future obligation the rendering path already
has (the hover/focus discipline, the content-fit checker, the
synchronized-write batching) a second time, by hand, instead of for
free.

### The Production Line's Actual Product: Ids and Teardown

Once placement is decoupled from geometry, and geometry is decoupled from
"is this a grid the author wrote or one a callback is building," the only
piece left to generalize is *identity* - every widget still needs a
unique id, and a rebuildable layout needs a way to discard its old
widgets without discarding anyone else's. `tui.exec`'s own controls had
already solved a narrow version of this (a hardcoded `_x` prefix, matched
and stripped on teardown) - narrow because a hardcoded prefix cannot
support two independently-rebuildable dynamic regions coexisting on one
page without their teardown routines colliding. Generalizing "prefix" to
"caller-chosen namespace" is a small change in isolation, but it's the
change that turns one bespoke pattern into a primitive: id generation and
bulk teardown, parameterized by who's asking, wrapped around
constructors that were already there. Nothing about `tui.factory.button`
is a new way to make a button. It is the old way, plus bookkeeping.

## What Building the Line Actually Exposed

### A Composability Test That Two Bugs Failed

Composing existing primitives is supposed to inherit their existing
correctness along with their existing behavior. Twice during this work,
that assumption was checked by building something new on top of an old
primitive and watching the old primitive's own conventions get violated
by the new code, not by the primitive itself:

The factory constructors were written to *optionally* return their
generated id via a trailing `printf`, on the theory that a caller could
capture it with `$(...)` if wanted. That theory quietly assumes every
caller remembers to capture it. One didn't - `debug_callbacks.sh`'s own
first version called `tui.factory.button` in a loop with no `$(...)`
around it, and every generated id wrote itself directly onto the running
terminal, because in a TUI stdout is not a log stream, it's the screen.
The fix wasn't to document the footgun more clearly. It was to remove the
possibility: a factory constructor now only ever writes to a variable.
Optional-and-easy-to-forget is not a safe default for anything that
writes to a display.

The content-fit checker's cache was computed inside `tui.render`'s
output-buffering subshell - the same `buf="$( … )"` pattern used
throughout this codebase specifically to batch many small writes into
one. That pattern is correct for what it was designed for: capturing
*output*. It is silently wrong for anything that also needs to leave
*state* behind, because a subshell's variable assignments evaporate the
moment it exits, taking only its stdout with it. The cache populated
during a full render never survived past that render, so every later
hover, focus, or click - none of which re-enter `tui.render`'s subshell
- read an empty cache and treated it as "nothing to worry about." Grid
cells and tab headers, built by code that was itself new, were the first
thing to actually exercise a full render followed immediately by
targeted redraws often enough for the gap to be visible: a label present
on the first frame, gone until hovered, a border appearing on click,
gone again the moment a different cell was clicked. The fix was to move
the state-producing half of the work outside the subshell and leave only
the output-producing half inside it - but finding it required actually
running the sequence a user would run, not reasoning about the code in
the abstract.

### Sizing Meets Its Own Consequences

A grid or a set of tabs, once it can be built from a runtime item count
rather than an author's careful hand-tuning, will eventually be asked to
fit five tab labels into a header that was sized, by weight, for
whatever a human guessed "a row of buttons" would need. The content-fit
checker (built earlier in this same line of work) did exactly its job
here: it noticed, correctly and consistently once the caching bug above
was fixed, that several generated tab labels didn't fit their allotted
cell width. The right response wasn't to suppress the checker - it was
to recognize that a tab header clipping its label is the same kind of
"acceptable, expected overflow" a nav sidebar button already exhibits
without complaint, and exempt tab cells from strict fit-checking the same
way scrollable panes already are. A general correctness feature and a
generated layout's specific tolerances are different concerns; making the
first configurable per-use-case, rather than either always-on or
all-or-nothing, is what let both stay right.

### The Metaphor, Collected

A village scales by adding villagers, one relationship, one hand-dug
well, one hand-built house at a time - and it stays a village exactly
because that's how it grows. A production line scales by having already
solved "one unit" in a way that doesn't need re-solving for unit
one-thousand. The six-sub-pane toolbar, the twice-reinvented tab pattern,
and the doc page that needed manual edits every time a doc was added were
villages: correct, readable, and bounded by how much hand-authoring
someone was willing to do. Grid geometry that both a markup author and a
runtime callback can drive through the same function, a tabs
abstraction with no rendering code of its own, and a factory that turns
"unique id" and "clean teardown" into parameters instead of hand-managed
bookkeeping - that's the production line. It doesn't do anything a
village couldn't eventually do by hand. It does it without needing a
human present for each additional unit, and - once the two bugs above
were actually found rather than assumed away - without needing that
human to have been careful every single time.
