### `tui.exec`

```bash
tui.exec CMD OUT_PANE [CTL_PANE]
```

Runs a shell command in a pseudo-terminal and streams its output into a pane while the UI stays responsive.

**Parameters**

- `CMD`: command line, run by `script -q -e -c CMD`.
- `OUT_PANE`: pane that shows the output.
- `CTL_PANE`: optional pane that gets Cancel, Save Output, View Command, Retry and Back buttons plus an input box that sends a line to the process's stdin.

**Returns:** `1` when `CMD` or `OUT_PANE` is empty.

**Notes**

- Several instances may run at once, also into the same pane. Each gets an instance id (`e1`, `e2`, ...); later instances in a shared pane print a `── [eN] started ──` separator.
- Needs the util-linux `script`. BSD/macOS `script` takes different options.
- Running instances are killed on page change and on exit.
- Save Output writes `exec_output_<id>_<timestamp>.log` into the current directory.
- To restart cleanly in a pane (one process at a time), call [`tui.exec.cancel_pane`](/api/core/tui.exec.cancel_pane.html) first.

**Example**

```bash
tui.exec "ping -c 5 example.com" out ctl
```
