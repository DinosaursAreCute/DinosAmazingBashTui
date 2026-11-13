# tools/benchmarks

Everything that measures DABT, side by side so they share one reporter.

| Tool | What it measures | Run |
|---|---|---|
| [`profiler/`](profiler/README.md) | the real demo app in a pty: latency per interaction, where the time goes | `profiler/profile.sh` |
| [`compare-v2/`](compare-v2/README.md) | DABT against Textual and Bubble Tea, from the screen the user sees | `compare-v2/compare.py run workbench` |
| [`renderers/`](renderers/README.md) | every renderer of `lib/terminal_renderer.sh` on several datasets and argument sets | `renderers/profile.sh` |
| [`reporting/`](reporting/README.md) | the shared reporter, live view and viewer window the tools above use | a library, no entry point |

The bash micro-benchmarks (`tools/bench/`) and the perflab pages (`tools/perflab/`) are separate tools.
