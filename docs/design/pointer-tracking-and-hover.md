# Bending the Planet to Your Will: Architectural Strategies for Low-Latency Pointer Tracking and Hover Resolution in Pure-Bash Terminal Interfaces

Where its companion document addressed the mechanics of moving a fixed
viewport across static content, this one addresses a harder problem:
resolving, in real time, what a *continuously moving* pointer is currently
over, and doing so cheaply enough that a stream of such reports, arriving
far faster than any human interaction with a mouse click, never becomes
visible to the user as lag. Hover tracking looks, at first glance, like a
smaller problem than scrolling. In practice it exposed a wider variety of
failure modes, because pointer motion is not one event type but several,
arriving interleaved, at a rate the shell has no natural way to keep pace
with unless it is deliberately engineered to.

## The Bottleneck: Every Cell Is an Event

Terminal mouse reporting is not resolution-independent. In xterm's
any-motion tracking mode, the terminal does not send "the pointer is
moving" - it sends one full escape sequence *per screen cell the pointer
crosses*. A single fast sweep across a wide terminal does not produce one
event, or even a handful; it produces dozens, each a self-contained,
several-byte record that has to be read, parsed, and acted on before the
next one can be considered.

This is a fundamentally different load profile from scrolling. A mouse
wheel produces a bounded number of discrete notches; a pointer sweep
produces an event for every cell along its path, and the faster the
physical motion, the *more* events arrive in the *same* wall-clock window,
not fewer. Any per-event cost that would be imperceptible for a mouse
click becomes, multiplied across a fast sweep, the dominant cost in the
entire interaction loop.

### Correctness Problems Hide Inside Performance Problems

Enabling any-motion tracking to make hovering possible at all is not a
free change - it alters what the input stream can contain at points in
the code that were never written to expect it. Logic that had, until then,
only ever seen a mouse report when a button was actually pressed suddenly
started receiving movement reports with no button down at all. Code that
inferred "the user clicked here" from "there is a mouse report at this
position" silently became wrong: a scrollbar's jump-to-click track,
written under the assumption that any report landing on it represented a
deliberate click, began snapping the viewport every time the pointer
merely passed over the border; a correctness bug masquerading as a
UI-feel complaint, only found because it was tested directly rather than
inferred from symptoms.

The lesson generalizes: broadening what an input source reports does not
just add new cases to handle, it can silently invalidate assumptions baked
into code that has nothing to do with the new feature.

### The Debounce Trap

The scrolling architecture's central lesson: defer expensive redraws,
collapse a burst into one flush, was the obvious first tool to reach for
here, and applying it uncritically was itself a mistake worth recording.
Routing hover-driven redraws through the same debounce queue used for
scroll content did reduce draw volume during a sweep, but it also added a
fixed latency between "the pointer arrives somewhere new" and "the screen
reflects it," because a debounce queue's entire purpose is to *wait* before
acting, on the chance that more of the same is coming. For scrolling, that
wait is invisible. Nobody perceives a few-frame delay in a viewport
following a wheel spin. For a button lighting up under the pointer, the
same delay reads as sluggishness, because the user's mental model expects
hover feedback to be instantaneous, not "eventually consistent." Debouncing
is a tool for collapsing *redundant work*, not a general-purpose latency
tax to apply to anything that happens frequently - and the two are easy to
conflate until the wrong one is measured against user perception rather
than raw event count.

### The Byte-at-a-Time Tax

Beneath both of those issues sat a purely mechanical one: assembling a
single mouse report requires reading and classifying its bytes one at a
time, because the shell has no built-in concept of "read one complete
escape sequence." Each byte is its own call into the kernel. A report is
on the order of ten bytes; a burst of buffered reports during a fast sweep
is dozens of reports deep. The multiplication of "syscalls per byte" by
"bytes per report" by "reports per burst" turns an operation that looks
trivial in isolation into a measurable backlog the interpreter has to work
through before it can even determine where the pointer currently is - a
cost paid in full regardless of whether anything about the hover state
ultimately changes.

### The Asymmetry Hiding in a Convention

The most persistent source of lag turned out not to be a loop, a debounce
decision, or a parsing inefficiency at all, but an inconsistency in how two
outwardly identical-looking lookups returned their answer. One lookup
(which widget, if any, sits under the pointer) reported its result through
a pre-declared variable and a success/failure return code. The other
(which pane sits under the pointer) reported its result by printing it and
having the caller capture that output. A convention that looks equivalent
on the page but is not: capturing a function's output requires running it
in a subshell, and creating a subshell means asking the operating system
for a new process. That cost is invisible for a function called once. It
is not invisible for a function called on every single one of dozens of
events in a sweep, and it does not show up by reading the function's body,
only by noticing *how its result reaches the caller*. Two lookups that
do the same kind of work, side by side, can carry wildly different costs
for a reason that has nothing to do with their logic.

---

## Strategies Applied: Resolving State Without Paying to Draw It

The eventual architecture rests on distinguishing several things that are
easy to lump together under "handle the mouse": whether something changed,
whether that change is worth acting on immediately, whether acting on it
requires touching the screen at all, and whether the lookup used to
determine any of the above is itself cheap enough to run unconditionally.
Each of the failures above came from collapsing one of those distinctions
away.

### Separating "What the Pointer Is Over" From "What Reacts to It"

The most consequential decision was to stop treating "hover" as a single
concept applied uniformly to panes and widgets. A pane being hovered and a
widget being hovered answer different questions and were made to serve
different purposes. Pane-level hover exists purely as *routing state*, it
answers "which viewport should a scroll-wheel notch or a keyboard scroll
key affect right now," and nothing about resolving that question requires
touching the terminal. Pane borders instead react to *focus*: a
keyboard-driven, discrete, infrequent state change, reusing the same
visual channel (a border restyling) that hover previously - and
unnecessarily drove. Widgets, meanwhile, kept reacting to hover directly,
because a single widget redraw is cheap and there is no fan-out risk the
way there is when an entire pane's border ring redraws on every cell the
pointer happens to cross.

### Change-Gated State, Not Change-Gated Drawing

Every piece of hover/focus state is now written so that setting it to its
current value is a guaranteed no-op, checked first and cheaply, before any
work that depends on the change happens. This sounds obvious in the
abstract but is easy to get backwards in practice: it is tempting to let
the expensive operation (a redraw) be the thing that decides whether it
was necessary, by comparing old and new state *inside* the drawing path.
Structuring it the other way; decide first, using nothing but a string
comparison, whether there is anything to do at all means the overwhelming
common case (the pointer is still over the same thing it was a moment ago)
costs a single comparison and stops there, before touching any layout
math, any style resolution, or any terminal output.

### Batching Without Waiting

Where a redraw genuinely does need to happen, a focus change touching two
widgets and potentially two pane borders. The fix was not to draw each
affected element as its own write, and not to defer the writes behind a
timer either, but to compose every affected element into a single buffer
and flush it as one atomic, synchronized write. This is the debounce
architecture's "single-pass injection" principle applied without its
"wait to see if more is coming" half: batching collapses N writes into one
at the moment the work is known to be complete, with no artificial delay
introduced to see whether N might grow. Debouncing and batching are often
reached for as a pair, but they solve different problems - one collapses
redundant *future* work by waiting, the other collapses already-known,
simultaneous work by grouping it - and the framework's redraw helpers were
deliberately split into an immediate batching primitive and a separate,
genuinely-deferred queue, applying the queue only where waiting has no
perceptible cost (pane *content* re-rendering) and never where it does
(anything a user expects to feel instantaneous).

### Coalescing at the Input Layer, Not the Render Layer

The deepest fix for sweep-induced lag operates before hover state is ever
resolved at all. Rather than accepting every motion report as its own
unit of work, the event loop was taught to look ahead, once it has decoded
a report that represents pure movement, for more such reports that may
already be waiting to be read. If the very next thing available is *also*
pure movement, the earlier report is discarded outright. Its information
is entirely superseded by the newer one, and nothing was ever done with it
that needs to be undone. This continues until either the buffer is
genuinely caught up to real time, or something is encountered that is
*not* safely discardable: a click, a release, a wheel notch, a keystroke -
one-shot transitions that must be preserved and must stay in their
original order. Those get set aside intact and replayed through the exact
same input path immediately afterward, so that nothing downstream of the
event loop can tell a look-ahead ever took place. The distinguishing test
between "safe to discard" and "must be preserved" turns out to be a single
bit already present in the protocol's own encoding of button state. the
framework did not need to invent a classification scheme, only recognize
that the terminal was already supplying one.

The effect of this is that the *number of times hover state is resolved
at all* during a fast sweep drops from "one per cell crossed" to "one per
burst" - every intermediate position the pointer passed through and
already left is never looked at, never hit-tested, and never drawn,
because it was discarded before any of those operations had a reason to
run.

### Spatial Locality as a Short-Circuit

A separate, complementary technique addresses the cost of the lookup that
*does* still run once per resolved position: rather than always searching
every region of the layout to determine which one contains the pointer,
the last-known containing region is checked first, on the reasoning that
consecutive pointer positions are overwhelmingly likely to still be inside
whatever region the previous position was inside. This turns the common
case - the pointer moving within a region it was already in - into a
small, fixed number of boundary comparisons, with the full search reserved
for the comparatively rare moment a boundary is actually crossed. It is
the same idea underlying cache locality in general: recently-relevant
state is disproportionately likely to still be relevant, and checking it
first is cheap insurance against repeating a search whose answer usually
hasn't changed.

### Uniform Calling Conventions as a Performance Property, Not Just a Style Preference

The fix for the hidden subshell cost was, mechanically, almost trivial,
change how one function hands back its answer. What made it worth calling
out as a strategy in its own right is that the bug survived multiple
rounds of otherwise-careful optimization specifically *because* the two
lookups looked interchangeable from their call sites. Establishing a
single convention. A function that resolves a lookup writes its answer
into a known variable and signals success or failure through its return
code, full stop, no exceptions for "this one's simple enough to just print
it" removes an entire category of cost that is otherwise invisible at
every individual call site and only visible in aggregate, under load.

### Measuring Instead of Assuming

Several of the strategies above were arrived at only after a prior fix
that looked complete in review turned out not to be, once actually
exercised: a debounce queue that theoretically collapsed redundant
redraws, but empirically added latency where none was wanted; a peek
timeout chosen for being the most "obviously non-blocking" value available,
which turned out - verified directly against the shell's own documented
behavior, not assumed from its name - to silently discard every byte it
was meant to check for. Every load-bearing claim in this document about
what was slow, and by how much, was checked by isolating the operation in
question and timing it directly, before and after, rather than inferred
from the shape of the code. An optimization that has not been measured
against the specific failure it claims to fix is a hypothesis, not a
result - and more than one of the fixes here only became fixes once that
distinction was taken seriously.
