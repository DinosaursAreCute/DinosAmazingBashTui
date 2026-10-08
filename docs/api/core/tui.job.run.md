### `tui.job.run`

```bash
tui.job.run [--delay MS] [--label TEXT] ID WORKFN DONEFN [ARG...]
```

Runs `WORKFN ARG...` in the background and keeps the interface running. When it has finished, `DONEFN ID RC OUTFILE` is called in the main shell. If the work is still going after `MS` milliseconds, a spinner with `TEXT` shows in the top-right corner of the frame, so the user can see that something is happening.

**Parameters**

- `--delay MS`: how long to wait before the spinner appears. Default `$TUI_JOB_SPINNER_MS` (100). Work that finishes sooner shows no spinner. `0` shows it at once.
- `--label TEXT`: the words next to the spinner. Default `Working...`.
- `ID`: names the job. Starting a job with an ID that is still pending cancels the earlier one first.
- `WORKFN`: a function; it runs in a separate process.
- `DONEFN`: a function; called with the job `ID`, the exit status of `WORKFN`, and the path of a file holding what `WORKFN` printed.

**Returns:** `1` for a missing or undefined function or a `--delay` that is not a whole number.

**Notes**

- Because `WORKFN` is a separate process, it cannot change the main shell's variables. Hand a result back as output: whatever it prints becomes `OUTFILE`, and it may write more files named `"${TUI_JOB_PREFIX}name"`. Its error output goes to `"${TUI_JOB_PREFIX}err"`. Nothing it prints reaches the terminal.
- `DONEFN` is where the result goes on screen. Nothing is drawn before it runs, so a page or a list built by `WORKFN` appears all at once, never half-finished. The spinner is already gone when `DONEFN` runs, and the screen is repainted afterwards if `DONEFN` did not redraw it.
- `$TUI_JOB_PREFIX` is also set while `DONEFN` runs, so it can read those files. They are removed when the app exits.
- `WORKFN` starts with an empty job table, so a job it starts itself is its own: it cannot cancel the main shell's job of the same `ID`, and its temp files carry the process id so they never collide with the main shell's.
- Several jobs can run at once. One spinner is shown for all of them, with `(+N)` for the others.

**Example**

```bash
build_report() { sleep 2; printf 'sales: 42\nreturns: 3\n'; }   # slow work, runs in the background
show_report() {                                                # $1 id, $2 exit status, $3 output file
    (($2 == 0)) && tui.set_text report "$(<"$3")" || tui.notify "Report failed" error
}
on_refresh() { tui.job.run --label "Building report..." report build_report show_report; }
```

**See also:** [`tui.job.cancel`](/api/core/tui.job.cancel.html), [`tui.job.running`](/api/core/tui.job.running.html), [`tui.page.rebuild`](/api/core/tui.page.rebuild.html)
