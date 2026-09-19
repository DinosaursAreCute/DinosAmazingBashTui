# Handing Over the Keys to the Castle: Rebindable Input, Command Palettes and Developer Ergonomics in Pure-Bash Terminal Interfaces

## Prelude: What the First Users Said

Before this release the framework had, for the first time, been put in front
of people other than its author: a first round of user tests, in which
people used the demo application, and a first round of developer tests, in
which people tried to build something with it. The feedback was positive.
It was also, read carefully, a warning, and this document exists largely
because of what it said.

Two patterns dominated.

**The questions were about things that were not there.** The most common
question, from users and developers alike, was some form of "how do I do
X", where X was something a person reasonably expects a terminal
application to do without being told: rebind a key, find a command without
knowing its name, keep typing in an input after pressing Enter, take the
mouse back to copy some text, quit from a page that had forgotten to
provide a way to. Each answer was, in effect, "that is not implemented
yet", and each carried a second, quieter cost that I had to weigh before
answering at all. Making any one of these a default behaviour is not a
local change. A default is a promise made on behalf of every page that will
ever exist, it changes what "an empty page" means, it decides who may
override whom, and it must be affordable on every keystroke in a language
where a careless subshell costs a millisecond. Nearly every question was
therefore a design question wearing the clothes of a feature request, and
the honest answer to several of them was a redesign of how the framework
treats input, focus and defaults, which is what most of this paper
describes.

**The impression was of a toy.** This is the part that matters more. The
recurring reaction, stated in different words by different people, was that
the framework was *impressive but nothing more*: a remarkable thing to have
achieved in pure bash, a good demonstration of what the language can be
made to do, and not something to build an application on. The compliment
and the dismissal were the same sentence. "In bash" was being received as
the whole of the achievement rather than as an implementation detail, and
an implementation detail that is admired for its difficulty is being asked
to justify itself on those terms and no others.

I think the reaction was fair. A framework earns being taken seriously by
the absence of surprises, and a toy is precisely a thing that surprises you
in the first ten minutes: the key that does nothing, the focus that
vanishes, the setting that does not survive a restart, the question with no
answer in the documentation. Impressive and unreliable is a description of
a demonstration.

## The Initiative

Version 0.0.6 is my first attempt to answer that, and this document is its
account. The intention behind it is a change of goal, not only a change of
feature list. The aim is for the framework to be not merely *usable*, in the
sense that a determined person can get a page on screen, but *desirable to
work with*: the sort of tool a developer reaches for because the experience
is good, and a user forgives nothing about because there is nothing to
forgive. And the aim is for that to hold **as a terminal UI framework**,
judged against Textual, Bubble Tea and their kind on its ergonomics,
documentation and defaults, and not graded on a curve for being written in
bash. That it needs nothing but bash and awk remains a real advantage:
nothing to install, nothing to break, nothing to update. It is a property
that should make the framework easier to adopt. It should never be the
reason the framework is excused.

The remainder of the paper is organised around that test. For each decision
the question asked is the one a sceptical newcomer would ask: does this
remove a surprise, does it answer "how do I do X" before it is asked, and
does it cost nothing when it is not used?

## Where This Paper Sits

The companion documents in this directory concern themselves with cost:
what it takes to move a viewport, to locate a pointer, to compose a
layout, to reconstruct a page. Each treats the framework as a machine to
be made fast. This one treats it as a place that two kinds of people have
to live in. The first is the user, who arrives at a terminal application
with habits formed elsewhere and who is, within a few seconds, either
comfortable or not. The second is the developer, who arrives with a
picture of an application in mind and a finite amount of patience for the
distance between that picture and a working page. Version 0.0.6 was
almost entirely spent on those two people. Very little of it made
anything faster, though a good deal of it had to be made cheap, because a
feature that costs a fork per keystroke is a feature nobody will be
allowed to keep.

What follows records the decisions, the alternatives that were refused,
and the reasoning, in the hope that the next decision can be made with
the previous ones in view.

## The Starting Position: Behaviour That Was Not Yours to Change

Before this release, the framework's response to input was a chain of
`case` statements inside the main loop. Tab moved focus because a branch
said so. `q` quit because a branch said so. The mouse wheel scrolled three
lines because the number three was written in a function. This is the
ordinary way for a small program to begin, and it has one property that
becomes a defect only when the program has users: **the behaviour is
exactly as changeable as the source file is**, which is to say, not at all
to anyone who is not editing the framework.

A user who wanted `j` and `k` to scroll had to accept that they already
did. A user who wanted them not to, because the page contained an input
field where they were typing prose, had to accept that the framework
already knew better. A developer who wanted `ctrl+s` to save had no
supported place to say so. And every developer who worked around this by
reading raw escape sequences inside a callback was quietly writing a
second, private input decoder that would disagree with the first one on
the first terminal that encoded shift-and-arrow differently.

The design question was therefore not "which keys should do what", which
is a matter of taste, but "where should the answer to that question
live", which is a matter of architecture. The answer chosen was that it
should live in data.

## Decision One: Everything the Framework Does Is a Binding

Raw bytes are decoded once, in one place, into names: `ctrl+c`,
`shift+up`, `mouse:right`, `wheel:down`, `paste`. The decoder absorbs the
differences between terminals (F-keys, CSI-u encodings, SGR mouse reports)
so that nothing downstream has to. Downstream, a name is looked up in
tables, and what the tables contain is a command: `tui.action.scroll up`,
`tui.action.focus_next`, `tui.action.quit`.

The consequential step was to route the framework's own behaviour through
exactly the same mechanism a developer uses. Tab is not special. It is a
row in `config/default/keybinds.xml` that reads `tab → tui.action.focus_next`.
A developer's `tui.bind ctrl+e on_export` and the framework's own
`tab` binding go through the same lookup, are listed by the same
`tui.bind.list`, and are overridden by the same mechanism. There is no
privileged path, and therefore no behaviour that can only be changed by
forking the project.

Three consequences followed that were not fully anticipated.

**The defaults became documentation.** A file that says what every key
does is a reference manual that cannot drift from the behaviour, because
it *is* the behaviour. The Keys page in the demo prints the live table, so
"what does this application respond to" stopped being a question with a
research component.

**Rebinding became a property of the whole surface.** Because mouse
clicks, wheel events and scrollbar drags are bindings too
(`mouse:left → tui.action.click`), a user can rebind them, a developer can
scope them to a pane (`--pane output`), and a page can switch a whole
group off (`tui.defaults.off wheel`) without touching a line of framework
code.

**Actions became an API.** `tui.action.*` is a set of named,
documented, argument-taking functions. It is the vocabulary in which
bindings, buttons, footer items and palette commands all speak. Learning
it once pays out in four places.

### Lookup order, and why it is what it is

A key is resolved through user bindings, then developer (code and page)
bindings, then framework defaults, and the first match wins. The order is
a statement about whose intent is most specific. A default is the
framework's guess at what everybody wants. A developer's binding is a
decision about one application. A user's binding is a decision about one
person, made after seeing the application. The person with the most
information gets the last word.

`--pass` exists for the case where two of these should both happen: run my
handler, then the default. `--always` exists for the case where a shortcut
must work even while the user is typing into an input. Both are flags
rather than separate mechanisms, because the alternative was two more
tables, and a binding system's difficulty grows with its tables, not its
rows.

## Decision Two: Defaults Are Opt-Out

The first version of the default bindings was opt-in: a page enabled scroll
keys if it wanted them. The reasoning was tidy, and the outcome was that
every new page shipped without scrolling, tab order, or the ability to
quit, until its author discovered each omission by encountering it.

Reversing the polarity was the single most valuable change to developer
experience in the release. A page now starts complete. It scrolls, focuses,
clicks, pastes and quits. What it lacks is decided by what it removes:

```xml
<tui defaults="-scroll -wheel">
```

The defaults are grouped (`focus`, `pane`, `scroll`, `click`, `wheel`,
`quit`, and so on) precisely so that the unit of opting out corresponds to
a concept a developer can name, not a key they would have to list. The
principle generalises beyond keybindings: **the cost of forgetting should
fall on the framework's side of the ledger.** A developer who forgets to
disable a default gets a working page that behaves like every other page.
A developer who forgets to enable one gets a broken page and a search.

## Decision Three: Users Are Allowed to Change Their Minds, and to Keep Them

A binding system that forgets on exit teaches users not to bother. User
bindings therefore persist: `tui.bind --user` writes into a draft, the
Keys page shows an "unsaved changes" marker beside the entries that
differ from what is on disk, and *Save* and *Discard* do what their names
say. On the next start the saved file is loaded before the first frame.

The draft state is the decision worth explaining. Saving on every edit
would have been simpler, and would have made every experiment permanent.
People rebind keys by trying something, discovering it collides with
another habit, and wanting to go back. An interface that makes trying
irreversible makes trying rare. The draft is what turns rebinding from a
commitment into a conversation.

The framework's own settings (theme overlay, which default groups are off,
input behaviour) are kept in the same spirit in `tui.config`, a small
key-value store applied at startup. A developer's application inherits a
settings mechanism it did not have to design.

## Decision Four: The Command Bar as the Universal Entry Point

Keybindings solve the problem for people who know the key. A command
palette solves it for people who do not, and, less obviously, for
developers who do not want to design a menu.

`ctrl+p` (or `:`) opens a fuzzy-searchable list of every registered
command; Enter runs one. Its power lies in what it is built on. It is not a
feature of the demo. It is an API:

```bash
tui.cmd.add export "Export report" on_export --group App --key ctrl+e
tui.cmd.provider my_page_commands
```

The framework's own commands (go to a page, switch theme, focus a pane,
toggle a default group, open Settings) are registered through
`tui.cmd.add`, from a file, `commands.xml`, that any application can
replace or extend. The development order was deliberate: the API was
written first and the defaults were built *on* it. This is a cheap and
reliable check that an extension point is real. If the author of the
framework cannot build their own features with it, nobody else can either.

**Providers** handle the fact that some commands only make sense in
context. "Switch to Ocean" should exist because an Ocean theme exists.
A provider is a function called each time the palette opens; it registers
whatever is currently true, and its commands are discarded and regenerated
on the next open. Pages, themes, panes and default-key groups are all
providers. So the palette lists what is actually there, without a list
anyone has to keep up to date.

The palette's hints are read from the live binding tables. If a user
rebinds a command, the new key appears beside it. A palette that
advertises stale shortcuts is worse than none.

## Decision Five: Overlays Are a Layer, Not a Special Case

The palette needs to draw on top of a page it knows nothing about, and to
own the keyboard while it does. So does a confirmation dialog. So does the
kill-switch warning. Three features implemented three ways would have been
three ways to get the same bug.

`tui.overlay.add` registers a draw function that runs after every flushed
frame, so it is always on top. `tui.modal.open` is an overlay plus
ownership of input: while a modal exists, key and mouse events go to its
handlers and nothing else. `tui.overlay.box` draws a framed box in place.
The palette, the kill-switch box and the footer are all built from these
three primitives. A developer building a dialog uses the same three.

A consequence worth recording as a warning. The first implementation
redrew every overlay on every iteration of the main loop, which is the
obvious way to guarantee they stay on top, and it is wrong. On an idle
page it emitted the footer 238 times in four seconds, about 143 KB, and in
one terminal the repeated full-width writes scrolled the screen. It looked
like a rendering bug, and it was really a policy bug: nothing had said
*when* an overlay needs to be redrawn. The corrected rule is that overlays
redraw only after a frame has actually been flushed, which is the only
event that can have painted over them. Idle output fell to a handful of
redraws. The general lesson is that "always redraw" is not a safe default
for anything that writes to a terminal, because the terminal is a shared
resource that other things, including the user's scrollback, can observe.

## Decision Six: Focus Is Something the User Has, Not Something the Framework Grants

Three separate complaints, discovered independently, turned out to be one.

- Pressing Enter in a shell-style input dropped focus, so the user had to
  click back in to type the next command.
- Pressing Right in an uneven grid jumped, apparently at random.
- Reloading a page reset focus to nothing.

The common fault was that focus was treated as a transient of rendering
rather than as state that belongs to the user.

*Retain Input On Submit* (`retain_input_on_submit`, `tui.input.retain`) is
the default: an input keeps focus after Enter and gives it up only on Esc,
Tab, or a click elsewhere. Opting out is a one-word attribute. `sticky`
extends the idea across repaints and same-page reloads, and a page reload
restores the previously focused widget when the page is the same page.

The spatial-navigation bug was more instructive. Arrow-key focus movement
originally picked the nearest widget by distance. In an even grid that
works; in an uneven one, nearest-by-distance is a different sentence from
"the thing I would expect", and the two disagree in ways users experience
as randomness. The corrected model is the one people carry in their head:
Left and Right stay on the same row, Up and Down follow the same column
beam. It is a smaller idea than "nearest", and it is the correct one,
because the specification was never geometric. It was a mental model.

Whole-pane focus (`f6`, `alt+arrows`, a highlighted border) was added for
the case the widget model cannot serve: a pane with nothing focusable in
it, such as a log, is still something a user wants to scroll with the
keyboard. The keyboard pane is the scroll target, and it follows widget
focus, so the two never disagree.

## Decision Seven: Give the Terminal Back on Request

A framework that captures the mouse takes something from the user: native
text selection and the terminal's own copy. Every terminal UI framework
eventually receives the same bug report.

Two features answer it, and they are deliberately different.

*Pass-through mode* (`ctrl+alt+p`) hands keyboard and mouse back to the
terminal entirely, so selection and copy work as they always did, and a
single key returns control. It is an admission that the framework is a
guest in the user's terminal.

The *kill-switch* (`ctrl+alt+k`) disables keyboard bindings only, with a
warning box that stays on top. It exists for the case where an application
binds a key the user needs, in the middle of a task, and cannot rebind
right now. The one key that turns bindings off is itself always live, and
it is configurable (`tui.keys.suspend_key`), because an escape hatch that
collides with something else is not one.

Bracketed paste and `tui.clipboard.copy` (OSC 52) complete the set. A
paste arrives as one bindable event rather than as a thousand keystrokes
that each trigger every binding, and the default inserts it into the
focused input with control characters removed.

## Decision Eight: The Developer Should Be Able to Ask

A developer builds against a mental model, and most defects are the model
disagreeing with reality. The fastest way to find the disagreement is to
ask the framework what it thinks. Until this release the honest answer to
"how wide is my pane right now" involved reading `_TUI_P_W`, which is
private, undocumented, and free to change.

`tui.get.*` closes that gap: dimensions (`tui.get.dimensions -r|-c
[--content] [PANE]`), position, rect, border, pad, split, children, parent,
scroll state, style, focused, hovered, event, page. Style getters are
fork-free (`tui.class.style`, `tui.class.sgr`, `tui.style.sgr`) because a
getter that costs a process cannot be called from a render path.
Callbacks that read framework state stopped needing to know how the
framework stores it.

The debug pages come from the same idea. The *Keyboard & mouse* view is a
full keyboard drawn from `tui.fixed`, with every key lit when pressed and
held for a few frames, plus mouse buttons and a last-input readout. The
*Feature lab* has a button for every palette, modal, overlay, focus and
clipboard feature, a live state readout and an event log. Neither is a
toy. They are how a bug report can begin with "here is what the framework
thought was happening".

## Decision Nine: Live Things Should Be One Line

The single most requested shape of page turned out to be a page with
something updating on it: a clock, a monitor, the output of a command.
Doing this correctly in pure bash is hard, and the obvious implementation
is wrong: a `while sleep 1` loop in a background process that prints into a
pane, a subshell per update, and a page that leaks the process when you
navigate away.

`tui_api.sh` reduces the correct implementation to one line each:

```bash
tui.clock hdr seg3               # live clock, big font
tui.every 2 refresh_stats        # timer
tui.watch out "df -h /" 5        # command off-thread, streamed via a fifo
tui.monitor mon 1                # CPU / MEM / SWAP / load dashboard
```

All of it rides one shared tick listener, times itself from
`EPOCHREALTIME`, reads `/proc` with `read < file`, writes into panes with
here-strings, and skips the redraw when the text did not change. Slow
external work runs in a single background producer per watch, feeding a
fifo that the tick drains without blocking, so the interface never waits on
a command. Jobs are cleared on page change and on exit, which removes the
leak. The developer's whole obligation is to say what should update and how
often.

## Decision Ten: Layout Should Say What You Mean

Several additions were small, and their combined effect was that the
layout vocabulary stopped having gaps.

`hpad` and `vpad` on panes and widgets, with parent padding acting as a
gap between a frame and its children, mean that breathing room is a
declaration rather than a run of spaces in a label. Parent panes can draw
their own borders, giving *layered* borders; when space runs out, the
borders drop automatically instead of consuming the pane's entire interior.
`tui.fixed` (`split="fixed"`) exists because some interfaces, a keyboard
above all, are defined by every element being the same size, which no
proportional layout expresses without contortions. Content in panes now
survives a resize, because a resize that discards what a callback loaded
turns every terminal window drag into data loss.

App-wide theme overlays (`tui.theme.set`) layer a palette over every page,
each of which may have its own stylesheet, so a user can pick Ocean or
Light once and have the whole application obey. Because a stylesheet can be
memoized by modification time, the cost of applying it is paid once.

## The Constraint Beneath All of It: Nothing Here May Be Slow

Every decision above adds a lookup, a redraw or a page. None of them was
acceptable at the price of a fork. The release therefore included a
systematic audit: count the processes each operation creates (the last-PID
field of `/proc/loadavg` is enough, and needs no tools), fix the worst, and
write the counting tool into `bin/debug/` so the audit is repeatable.

| Operation | Forks before | After |
|---|---|---|
| Hover a widget | 38 | 0 |
| Full frame render | 136 | 4 |
| Alert renderer | 30 | 0 |
| Line chart | 54 | 1 |
| Monitor refresh | 652 | 38 |

Switching to the Keyboard view fell from about 1050 ms to about 270 ms, and
warm page switches now sit between roughly 60 and 260 ms depending on the
page. The methods were the ones the earlier documents describe: `printf -v`
in place of `$(...)`, namerefs, here-strings in place of process
substitutions, `_v` variants of renderer helpers that leave their result in
a variable, and stylesheet memoization. The framework's renderers were
verified to produce byte-identical output after the rewrite, which is the
only acceptable standard for a change whose entire purpose is to alter
nothing observable.

A lesson recorded here for whoever does the next one: a feature's
performance cost is not only its own. A footer that costs nothing to build
cost a great deal when it was redrawn every tick. Overhead of that sort
does not appear in a profile of the function, only in one of the loop.

## Documentation and Tooling as Product

A framework is only as usable as its worst-documented corner, so the
documentation was treated as part of the deliverable rather than its
afterthought. It was reorganised into a single entry document with
`guide/`, `api/` and `design/` beneath it; the API reference lists every
public function and its parameters in one table; a generated page covers
the ~310 escape-sequence helpers, so that it cannot go stale.

Two tools were added because they change how development feels. A
headless screenshot generator (`bin/debug/screenshots.py`) renders every
demo page in every theme at more than one terminal size, using nothing but
a small terminal emulator and an image library; it turns "does this still
look right everywhere" into a command. A full profiler
(`bin/debug/profile_all.sh`) covers startup, cold and warm page loads,
render, cache operations, hot calls, overlays and resize. The rule adopted
alongside them, that profiling scripts live in `bin/debug/`, matters more
than either script: it keeps the measurements available to the next person.

## What This Enables

The claim of the release is that the distance between intent and result
has been shortened for both audiences.

For a **user**: the application responds to the keys they already know;
rebinding is a draft they can keep or discard; anything can be found with
`ctrl+p` without knowing it exists; the terminal can be taken back with one
key; focus stays where they put it; paste, wheel and resize behave.

For a **developer**: a page starts complete and is edited by subtraction;
every framework behaviour has a name that a binding, a button, a footer item
and a palette command can share; the framework can be asked what it knows;
live data is a single line; dialogs are three primitives; layout has words
for what it means; and the documentation and tooling are in the repository
rather than in the author's head.

Both lists come from one policy: **behaviour is data, and data belongs to
whoever needs to change it.** A framework that takes this seriously stops
being something that people use and becomes something that people build
on. The keys were never the framework's to keep.
