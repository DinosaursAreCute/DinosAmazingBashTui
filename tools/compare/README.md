# DABT vs Textual comparison

Two small apps with the same four pages and a black-box harness that drives both through a hidden pseudo-terminal.
Dev tool only: Python is allowed here (like `tools/profiler`), the DABT runtime stays pure bash.

| page | widgets |
|---|---|
| 1 Buttons | label, three buttons (click counter) |
| 2 Form | input, two checkboxes, submit button, status label |
| 3 Data | scrolling list of 40 items (selection label), table |
| 4 Layout | three panes (one tall, two stacked), progress bar, advance button |

Both have the same menu on the left (18% wide), plain single borders, no colours beyond focus reverse video, and
write nothing while idle (no clock, no blinking cursor): the harness reads "no output for 150 ms" as "frame done".

```
tools/compare/dabt_app/run.sh            # look at the DABT side
tools/compare/textual_app/run.sh         # look at the Textual side (needs the venv below)

python3 -m venv ~/.cache/dabt-compare-venv && ~/.cache/dabt-compare-venv/bin/pip install -r tools/compare/textual_app/requirements.txt
tools/compare/compare.py                 # 5 rounds, both apps, 150x45, ~3 min
tools/compare/compare.py --rounds 2      # quick
tools/compare/compare.py --only dabt
```

Output: `reports/<timestamp>/{compare.txt,compare.json}` (git-ignored). `COMPARE_VENV` overrides the venv path.

## What is measured

Per step (page switch by menu click, button click, typing, list keys, resize, 2 s idle), medians over the rounds:
- **content**: input written to the expected text first appearing in the output (first output byte for steps with no expected text)
- **done**: last output byte before the screen went quiet
- **bytes / writes**: output volume per step
- **cpu**: CPU ms of the app's whole process tree during the step (`/proc`)
- **startup.cold**: fresh HOME (DABT builds its page cache, Textual has nothing to build); **startup.warm**: second start with the same HOME
- **rss**: resident memory of the tree after the session

## Caveats

- Both apps are written by the same author; the Textual app follows its documented patterns but is not tuned.
- Inputs are identical (same clicks and keys), but each framework decides how much it redraws per input.
- Per-function attribution exists for DABT only (`tools/profiler`); this harness cannot see inside either app.
- Page switches in Textual use `switch_screen` with a new screen per visit, matching DABT's page-per-file loading.
