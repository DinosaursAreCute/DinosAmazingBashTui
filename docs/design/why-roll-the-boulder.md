# Why Even Roll the Boulder? The Gods Won't Notice, and What Will They Do, Curse Me *Again*?
*An essay on optimizing a terminal UI in Bash and cleaning up the mess I made.*

## Table of Contents

<details>

   <summary>Contents</summary>

1. [It was slow, it felt slow and that was almost fine with me](#it-was-slow-it-felt-slow-and-that-was-almost-fine-with-me)
1. [The caches had holes](#the-caches-had-holes)
1. [The boulder was not my code](#the-boulder-was-not-my-code)
1. [Where I kept failing](#where-i-kept-failing)
1. [So, why roll it?](#so-why-roll-it)
1. [After Word](#after-word)

</details>

## It was slow, it felt slow and that was almost fine with me

DABT was slow, Pages took a moment too long to appear, keys had a slight lag and sometimes it would freeze for a short time. It's bash, I have written it, of course it's slow. Bash was not built for this, everyone knows that I knew that and It was ok.  gods
Nobody gave me this boulder I chose it, I took it from Sisyphus. The gods did not do this to me. I do it to myself, I do, and that's what really hurts. (subtle Radiohead reference ;3)

Then I built the `compare` harness to put DABT next to Textual and Bubbletea on the same workbench app. The numbers were bad. They weren't "Bash tax" bad. They were "you
did something wrong" bad.

Any reasonable person would have gone: "ah, it's Python, of course it's fast and Go is simply not feasible to even aim for."
I expected this result. I was almost ok with that result- *almost*. I accepted it for about a day. Then I thought: why can bash not be faster actually?

## The caches had holes

I had a lovely caching system: page cache, layout memo, widget placement, paint diff, markdown snapshots. I was sufficiently satisfied with it.

Then I noticed the pipes are leaking. 

And let me tell you it leaked everywhere. Some leaks were places that should have hit the cache and didn't. Others were places that hit it and then repainted anyway.

To let you be part of my misery: 
- A button click repainted the released button 20 to 28 ms after the new page was already on screen. Fixing it saved about 60 ms per click.
- A page switch painted the screen twice. Now it paints once.
- The page cache was 12 files per page, so a start read 286 files. Now it reads 26.
- A held Down arrow cost 478 ms of work per second of hold and painted 49.5 KB. Now it costs 47 ms and 4.3 KB.
- A table Down keypress went from 40 ms to 20 ms. Typing in a filter went from 42 ms to 5 ms.

Input was a mess too. Every mouse event cut the poll short and re-ran every tick function. Alt plus a key waited 10 ms for an escape sequence that was never
going to arrive. A timer job that was due right now politely waited out a 50 ms poll.

Essentially I managed to set my own precious home on fire while also getting my basement flooded. 

And the stupid part? 
Nothing was slow in a way my profiler flags. It was a lot of small leaks that I had half-fixed in other places.
In a way one could say it is an achievement, my framework outgrew the profiler. It was too optimized for the profiler to catch these things. I say: maybe I should have updated my profiler. Easy to say when sitting in the rubble of a fight now over. (at least for this very moment of writing this)

## The boulder was not my code

I also did what I wanted to do, which was speed up my own Bash functions. That's the fun part, because I can read the code, shave a loop, and feel clever.
It barely mattered. There was always more to shave in my own functions, but that wasn't where the time went.

The time went to things that shouldn't exist at all:

- A 200-row `table` forked about 201 times per call. It now forks 2 to 4 times.
- `mapfile` on a pipe reads one byte at a time. For a 13 KB chart that cost 10 to 15 ms, and word splitting does it in about 1 ms.
- Page validation ran 27 pages in 1550 ms. Run in parallel, it takes 248 ms.

Cold start went from 2.8 s to 600-700 ms in 0.0.31. The renderers now take 33% less time per call over 114 profiler cases. `csv_vbar` went from 207 ms to 10 ms.
Most of that wasn't cleverness. It was deleting work. It was repeating what I had already figured out. Boilerplate. But Boilerplate that showed results. It was never bash. It was always me. 

## Where I kept failing

My dead ends were all the same: find one inefficiency, such as a redundant paint, then apply the fix everywhere. That doesn't work. A redundant paint in
a click handler is not the same bug as one in a resize or a layer drag. Each place needed its own look.

The real fixes were mostly cleanup, plus solutions to problems I had already solved several times in this codebase. I kept solving the same problem and
forgetting I had done it.

## So, why roll it?

The gods didn't notice. Textual still wins some rows of the comparison, and I can live with that. Though now that I wrote it out, it does bother me a bit. 

But I stopped trying to use "it's Bash" as an excuse to stop this project. At this point I am awfully aware that I have gone past the point where I can claim that excuse for myself. I am way too deep into it now, just now 31 versions in. The boulder stays at the top for a while, and I know
by now where it rolls down.

And if they do notice, what are they gonna do? Curse me again? They already did- **for eternity!**

## After Word
This essay might make it sound like I am suffering. So why do it then? Simple. Because the wall I thought bash would put in front of me never appeared. So I must keep pushing. Either I become god myself (beating Go, although rust exists and I am afraid to profile that) or I die (metaphorically) trying. 

With that said, 
I will sign off

Kthxbye \
Dino <3