# I Fired Sisyphus and Realized That Climbing a Mountain Is Exhausting, So I'm Blowing It Up: Fork Elimination, Wait Removal and Redundant-Work Deletion as a Latency Strategy in Pure-Bash Terminal Interfaces

**Abstract.** A companion document dismissed Sisyphus by writing down
the route of his climb and replaying it, so that a page already
constructed is never constructed again. That remedy removed the repeated
ascent but left the ascent itself untouched, and a page switch in the
reference application still cost between 356 and 409 milliseconds. This
paper reports a thirteen-change, profiler-guided campaign against what
remained. Three hypotheses were tested: that the residual cost
concentrated in a few slow functions and would yield to faster
implementations (H1); that it would yield to further retention, meaning
more caches and dirty flags (H2); and that it consisted largely of work
which should not exist at all, namely process spawns, idle waits and
duplicated computation (H3). H1 was rejected, H2 was demoted, and H3 was
supported: median page switches fell by 47 to 50 percent, wheel scrolling
by 73 percent, idle repaints by 90 percent, warm start by 66 percent and
cold start by 50 percent, principally by deletion rather than
acceleration. The campaign also produced one instructive casualty, a
silently destroyed feature, and one honest limit: deletion removes
scaffolding, not the load-bearing wall, and the remaining page-switch
latency is the irreducible cost of painting.

**Keywords:** terminal user interfaces, bash, latency profiling, fork
cost, redundant computation, measurement methodology

## 1. Introduction: The Mountain That Remained

Its companion, "Making Sisyphus Redundant," began from the observation
that `tui.goto` reconstructed every page from its markup source on every
visit, and resolved the problem by retaining a write-ahead log of how
each page had been built. The argument there was, in its own terms,
complete: the climb is repeated because nothing records the climb. Once
something does, the repetition ends.

It did not follow that the climb had become cheap. A first visit to a
page still had to be made, a revisit still had to be painted, and in the
reference application, the demonstration program shipped with the
framework, the measured median cost of moving between its ten pages
remained 356 milliseconds on a first visit and 370 on a revisit, against
perceived-instant budgets of 150 and 100. Startup required 5.8 seconds
cold and 0.86 seconds warm. An idle screen, with nobody touching it,
repainted itself twenty times every second. These are not the symptoms of a
system that repeats itself. They are the symptoms of a system that, on
each single traversal, carries far more than it needs.

The metaphor of the preceding paper admits a second reading. If dismissing
Sisyphus fails to make the mountain smaller, the remaining options are to
become a better climber, to install a funicular, or to ask whether the
summit was ever where the boulder needed to go. This paper investigates
the third, and its title should be taken as a methodological claim rather
than a mood: a surprising share of a slow interface's latency is not
work performed badly but work performed needlessly, and it is removed
more cheaply by demolition than by refinement.

## 2. Hypotheses

Three explanations for the residual latency were advanced before any
change was made, each with an operational consequence.

**H1, the climbing-technique hypothesis.** The cost concentrates in a
small number of functions that are individually slow. If true, the
profile's hottest entries are the correct targets, and their
optimization should produce proportionate gains.

**H2, the funicular hypothesis.** The cost is chiefly the repeated
recomputation of results that change rarely, and is addressed by
retaining more: memoizing conversions, baking styles, snapshotting
per-theme state, and introducing dirty flags so that frames carry only
what changed. This is the natural extension of the prior paper's
method, and so the hypothesis that an author with a hammer would most
expect to confirm.

**H3, the demolition hypothesis.** A large part of the cost is
structurally unnecessary: external processes spawned for work the shell
can do itself, intervals during which the program merely waits, and
computations performed twice because two correct pieces of code each
assumed the other would not. If true, the largest gains lie in
deleting these, and they will be invisible to a profile that ranks
functions by self time, because they are distributed across many small
costs or sit in the gaps between functions.

The three are not exclusive, but they are distinguishable, because they
predict different relations between a change's effort and its effect.

## 3. Method

### 3.1 Apparatus

Measurement was performed by a profiler that drives the real
application, unmodified, inside a hidden pseudo-terminal through a
scripted session: start, navigation by pointer and key, focus movement,
hovering, clicking, wheel scrolling, palette opening and closing, theme
changes, terminal resizing, idle observation and exit. A full run
performs five rounds of the session. The terminal is fixed at 150 by 45
cells throughout, and the dependencies are bash 5 and Python 3 alone.

### 3.2 Two instruments, calibrated against each other

Two measurements are taken, because neither answers both questions. The
first is an untraced run in which probes wrapped around roughly twenty
functions timestamp each interaction. This yields the latency a user
would experience, including time spent waiting, and is treated as the
ground truth for any claim of improvement. The second is a run under
bash's `xtrace`, which attributes time to functions, architectural
layers and subprocesses, but executes approximately three times slower.
Attribution is therefore rescaled, per scenario, to untraced speed, with
blocking time excluded from the scale factor so that waits are not
inflated into computation. The rescaling is verified rather than
assumed: over sixty functions, the calibrated attribution deviated from
the probe measurements by 6.5 percent on average with a bias of negative
1.0 percent, sufficient to trust layer-level conclusions.

### 3.3 Protocol for each change

Every change was made singly. Before it, an expected effect was written
down with its reasoning. After it, the relevant scenario was measured
again, and the expectation and the observation were recorded side by
side, including when they disagreed. This discipline is the source of
most of the findings below, because the disagreements were more
informative than the agreements.

### 3.4 Noise floor

Page-revisit medians proved stable, with a median coefficient of variation
across eight rounds of 0.8 percent. First-visit medians were not: a
per-page coefficient of variation of 7.5 percent and round-to-round
swings of roughly 7 percent. Terminal resizing was bimodal by target
size and is reported without a reliable figure. A difference below
about three percent was accordingly never reported as a change, and a
mid-campaign bump in first-visit latency is attributed to this variance
rather than to regression.

## 4. Results

### 4.1 Aggregate effect

Medians of probe-measured latency, first deep run against the latest.

| Interaction | Before | After | Change | Budget |
|---|---|---|---|---|
| Page switch, mean over all pages | 409 ms | 203 ms | −50% | none |
| Page switch, first visit | 356 ms | 190 ms | −47% | 150 ms |
| Page switch, revisit | 370 ms | 196 ms | −47% | 100 ms |
| Command palette close | 143 ms | 52 ms | −64% | 100 ms |
| Wheel scroll | 64 ms | 17 ms | −73% | 60 ms |
| Idle repaints | 20.7 per s | 2.0 per s | −90% | 2 per s |
| Warm start | 857 ms | 287 ms | −66% | 1 s |
| Cold start | 5.84 s | 2.90 s | −50% | 5 s |

*Table 1. Latency before and after thirteen changes. The page switch
remains above budget; every other interaction is within it.*

Attributed by layer for a page revisit, subprocess time fell from 79 to
39 milliseconds and style computation from 72 to 11, while flush fell
from 48 to 25. In the lightest representation of the final state, a
157-millisecond page switch comprised 20 milliseconds of subprocesses,
10 of style, 23 of flush, 21 of layout, 21 of rendering and 17 of
widgets, the residue being the actual drawing work.

### 4.2 H1 is rejected: the hot function was not the mountain

The first change was the most orthodox: the function converting colour
triples to escape sequences was hot by count, and memoizing it was
certain to be correct. It was. It also saved approximately 19 of the 378
milliseconds of a theme switch, too little to appear in wall-clock
measurement at all. The expected gain had been derived from the
function's share of the profile, and the share was real. What the
reasoning omitted was that a function may be hot and still be cheap in
aggregate, because it is being called in a context whose cost is dominated by
something else.

The same pattern recurred at smaller scale. Sharing a pane's inset
calculation across consecutive widgets, a correct and careful change to
the two most frequently called geometry functions, reduced layout from
26.7 to 24.0 milliseconds. No change aimed at a hot function
outperformed a change aimed at the structure around it.

### 4.3 H3 is supported: what deletion bought

The largest single-interaction gain of the campaign was a change of one
variable. The main input loop, after receiving an event and queuing a
render, waited out a full fifty-millisecond poll before flushing it. The
wait was not computation, appeared in no function's self time, and
therefore never ranked in the profile. Shortening the settle interval
while a render is queued reduced wheel scrolling from 58 to 18
milliseconds and added a saving of about 35 milliseconds to every page
switch. A second wait of the same family, an unconditional fifty-millisecond sleep
per process while terminating a process tree on leaving the Terminal
page, cost 302 milliseconds for a four-level tree and 6 after the
change.

Redundant computation was the second reliable source. An overlay redraw
that re-triggered itself on every tick accounted for the idle repaint
rate of twenty per second, and moving a single statement reduced it to
two without altering any visible behaviour. A layout step scanned every
widget once per pane and was executed twice per render; replacing it
with a single-pass index reduced layout from 42 to 26 milliseconds per
page switch. Page code invoked `tui.render` a second time from within the
page's own visit handler, and deferring the render while a page loads
removed 90 milliseconds from the heaviest page. Bordered panes rebuilt an
identical interior row for every row they contained, and building it once
removed about 20 milliseconds from every full repaint.

The third family was the process spawn. Pane rendering passed every
coloured line through `awk`; replacing the pipe with bash string
slicing removed every fork from hover, click and scroll. Cache
validation spawned one `stat` for every file; one batched invocation
reduced the warm start from 823 to 308 milliseconds, a threefold gain
from deleting a category of operation rather than tuning one. Removing
about nine thousand forks from the page-cache build, and a further 872
later, took the cold start from 5.54 to 2.87 seconds.

### 4.4 A correction to a prior: the price of a fork

The forks supplied the campaign's only quantitative surprise. Anticipating
roughly one millisecond per process, the expected gain from the last 872
forks was close to a second. The observed gain was about 230
milliseconds, a cost of about a quarter of a millisecond each. The
conclusion is not that forks are unimportant, since removing thousands of
them halved startup, but that their cost accumulates through count rather
than through any single expensive instance, and that forecasts built on
an intuitive per-fork price overstate the return by a factor of four.

### 4.5 H2 is demoted, not refuted

Dirty flags, the most obvious instance of H2, were investigated and
demoted. Tracing the frame sources showed that the extra frames per user
action were small: one 40-kilobyte render and approximately 15 further
kilobytes across the remainder, so that the expected saving from
suppressing redundant frames did not justify the complexity it would
introduce. The per-theme snapshot and style baking were deferred for a
similar reason, since they would address about 40 milliseconds inside a rare
event. H2 was not shown to be false. It was shown to be aimed at a cost
that, after deletion had done its work, was no longer large.

## 5. Discussion

### 5.1 Why the profile did not point at the largest wins

The profile ranks functions by self time, a measure that cannot see
idle waiting, which belongs to no function, and cannot see duplicated
work, which belongs to two functions each of which is individually
reasonable. It is also blind to fork counts, which it renders as many
tiny entries of the same name. The 50-millisecond wait and the duplicate
render were discovered by reading the timeline of a slow interaction as a
sequence of events, and asking of each interval what it was for. The
practical rule derived is that an optimization campaign should examine
what a slow operation contains before examining how fast its parts run.

### 5.2 The explosives are not selective

Deletion carries a hazard that refinement does not: it can remove
something that nothing obviously depended on. The campaign's single
regression of this kind was a pre-existing one discovered incidentally.
Key bindings declared in page markup were silently omitted from cached
pages, so that the `alt+1` through `alt+0` navigation keys did nothing on
any warm start. The profiler reported it as an interaction with a latency
of 10.9 milliseconds, which is to say that a key press had completed
suspiciously quickly because it had done nothing. Correcting it made the
measured key-navigation scenario a real page switch of 368 milliseconds,
an apparent regression of the metric that represented the repair of the
feature. A measurement campaign must therefore distinguish a faster
operation from an operation that no longer occurs, and the reference
application's profiler is deliberately configured to report the second as a finding.

### 5.3 What remains of the mountain

After the thirteenth change a page switch still exceeds its budget by a
factor of 1.4 on a first visit and 2.1 on a revisit. The remainder is
not scaffolding. It is the substance of painting a frame: drawing widgets,
computing their positions, emitting cursor movements and flushing the
result, with the heaviest pages adding their own work, such as a
103-kilobyte frame on the components page. Deletion has, for practical
purposes, exhausted itself here. What is left is reducible only by
retaining rows between frames, which is the approach of the preceding
paper applied one level lower. The two strategies are therefore not rivals
but successive stages: retention eliminates repeated ascents, deletion
eliminates the dead weight carried on each one, and the next gain, if
any, lies in building a smaller summit.

## 6. Threats to Validity

Four limitations bear on the conclusions. First, all measurements come
from one machine, one terminal geometry and one application; the ratios
may not transfer to hardware where process creation is more expensive,
and the near-uniform quarter-millisecond fork cost in particular should
be treated as local. Second, the baseline and subsequent runs differ in
round count, five against between three and four for several later
scenarios, so medians rather than means are compared. Third, the first
visit of a page includes one-time work and its medians carry a
noise of up to ten percent, which is why only the revisit column supports
fine comparisons. Fourth, several effects are not attributed with
certainty: a rise in shutdown time from 31 to 54 milliseconds has not
been investigated, and a change in a focus-movement scenario reflects a
change in scenario state, not code, and cannot be compared across runs.
Finally, the unit test suite was run by the maintainer after some changes,
but its results are not recorded alongside the measurements, so claims of
behavioural equivalence rest on matching output byte counts and isolated
equivalence tests.

## 7. Conclusion

Sisyphus was not, in the end, the problem, and neither was the boulder.
The prior paper dismissed him by recording the route, so that the climb
need not be repeated. This one observed that the route, on each
occasion it was walked, passed through a checkpoint that demanded a
fifty-millisecond wait before proceeding, stopped to hire a
subcontractor for every step that the climber could take alone, and
carried, at intervals, a second copy of the boulder. None of these
appeared on the map, because the map recorded where the climber spent
effort and not where the climber merely stood. Removing them did not make
the climb more skilful. It made it shorter, and it did so more cheaply
than any refinement of the climbing had, at the modest cost of one
feature, silently lost and promptly rediscovered, which demonstrates that
the charge must be placed where the measurements say and that the
measurements themselves must be watched for signs of nothing having
happened. Of the three hypotheses, H3 survives as the one that explains
the campaign, H1 does not survive contact with its own first change, and
H2 remains the correct hypothesis for a problem that has, by now, been
reduced in size until it is the right one. The mountain is smaller. The
climb that remains is the honest kind, in which everything being carried
is being carried for a reason.

## References

- *Making Sisyphus Redundant: Write-Ahead Logging and Deterministic
  Replay in Pure-Bash Terminal Interfaces*. `write-ahead-logging-and-replay.md`.
- *Performance progress*, the per-change log with expected and measured
  effects. `docs/concepts/performance-progress.md`.
- *Making a pure-bash TUI feel instant*, the short version of this
  campaign. `performance-journey.md`.
- Performance explorer, an interactive comparison of any two profiler
  runs. `performance-explorer.html`.
