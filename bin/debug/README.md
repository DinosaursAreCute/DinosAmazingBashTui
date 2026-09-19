# bin/debug - performance and diagnosis tools

Headless (no terminal needed), use a throw-away `XDG_CONFIG_HOME`, run from anywhere.

| script | answers |
|---|---|
| `profile_page_switch.sh PAGE...` | reset / load_cached / render time of a warm `tui.goto`, per page |
| `profile_replay.sh PAGE...` | which recorded call (or `on_visit`, or a re-sourced script) dominates a page's load |
| `profile_calls.sh 'CMD' ...` | microseconds per call of any framework call, to spot hidden forks |
| `profile_callbacks_source.sh` | cost of re-sourcing each page's callback file (they are sourced on every visit) |

Typical workflow: `profile_page_switch.sh home settings keys ...` to find the slow page, `profile_replay.sh THAT_PAGE` to
see whether it is builder calls or `on_visit`, then `profile_calls.sh` on the suspect calls. Rules of thumb: a bash
builder call is ~100-250 us, a fork (`$(...)`, `< <(...)`, a pipe) costs ~1 ms, an awk process ~4 ms.

Related: `bin/bench_page_switch.sh` (older, end-to-end with the cache warm-up worker and a progress bar).

| `count_forks.sh 'CMD' ...` | how many processes a call creates (via the last-PID field of /proc/loadavg); 0 = fork-free. Use `-p PAGE` to pick the fixture page |
| `profile_all.sh [-s SECTIONS] [PAGE...]` | everything: startup, per-page cold/warm load, render/layout/bytes, hot calls, cache ops, state size, overlay idle bytes, resize |
| `screenshots.py [-t THEME,..] [-p PAGE,..]` | PNG of every demo page x theme into bin/debug/screenshots/ (headless; needs Pillow) |
| `screenshot_all.sh [OUTDIR] [ROWSxCOLS]` | one-shot: every page x theme + case study table + every docu tab, 0.5 s settle each |
