# perflab

The fixture app of the profiler's `perflab` scenario file (`tools/profiler/scenarios/perflab.py`). It measures the
framework, not the demo: the pages are frozen, each one exercises one feature, and nothing here changes when the demo does.

- `bin/perflab.sh` starts on `pages/start.xml`, one button that opens the page named by `PERFLAB_PAGE`.
- `pages/*.xml` are the feature pages (`ticks`, `every`, `hooks`, `table`, `textarea`, `input`, `palette`); their size comes from `PERFLAB_N` and
  `PERFLAB_COLS`, set per profiler unit. Pages that need N elements in the markup itself (buttons) are generated per rung
  by the scenario file's `prepare` hook into a run-private directory: `buttons`, `nav` (a page of N labels with a Back button) and
  `markdown` (a document of N paragraphs or N tables rendered by `<markdown>`).
- `pages/perflab_callbacks.sh` holds the callbacks. Everything is deterministic: no clock, no random data.

Run it through the profiler, see `tools/profiler/README.md`, *Sweeps and perflab*. Add a feature: a page here (or a generator
in `prepare`), a callback, and one row in `AXES` of the scenario file.
