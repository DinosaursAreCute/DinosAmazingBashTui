# Live output: processes, jobs and streams

Four tools, one question each:

| You want | Use |
|---|---|
| to watch a program run in a pane, with Cancel, Retry and a stdin line | `tui.exec CMD OUT_PANE [CTL_PANE]` |
| a slow job that gives you its result once | `tui.job.run` |
| text to appear **while** a job produces it, in your own widget | job + file + timer (below) |
| a command's output refreshed every N seconds | `tui.watch PANE CMD [SEC]` |

## `tui.exec`: a console in a pane

```xml
<pane id="out" scroll="both" title="Server log" border="single"/>
<pane id="ctl" title="Controls" border="single"/>
```

```bash
tui.exec.cancel_pane out          # one process per pane
tui.exec "bash ./server.sh" out ctl
```

The control pane gets **Cancel, Save Output, View Command, Retry, Back** and an input line that sends text to the process. The output is for looking at: `tui.exec` does not hand text back to your code.

Needs the util-linux `script`. Running processes are killed on a page change and on exit. Save Output writes `exec_output_<id>_<time>.log` into the current directory.

## Streaming text into your own widget

`tui.job.run` gives you the result only when the job ends. To show text while it arrives, let the job append to a file and let a timer read it:

```bash
STREAM_FILE="${TMPDIR:-/tmp}/myapp-$$.stream"

work() { produce_text "$@" >>"$STREAM_FILE"; }          # background job: append as you go

follow() {                                              # timer: show what the file holds so far
  local text
  text=$(<"$STREAM_FILE")                               # bash reads the file itself
  [[ $text == "$SHOWN" ]] && return 0                   # nothing new: no redraw
  SHOWN=$text
  show "$text"
}

finished() { tui.every.cancel follow_timer; show "$(<"$STREAM_FILE")"; }

ask() {
  : >"$STREAM_FILE"; SHOWN=""
  tui.job.run --label "Thinking..." answer work finished "$1"
  tui.every 0.1 follow follow_timer
}
cancel() { tui.job.cancel answer; tui.every.cancel follow_timer; }
tui.hook.on exit cleanup                                # rm -f "$STREAM_FILE"
```

## Quirks

- The job runs in **its own process**. Variables it sets are lost; only what it prints or writes reaches you.
- **`tui.job.cancel` does not call the finish function.** Stop your timer yourself and keep the partial text.
- Starting a job with an id that is still running cancels the earlier one.
- Timers are dropped when the page changes. Start them from `on_visit` pages, not once at startup.
- `tui.exec` instances multiply: call `tui.exec.cancel_pane` before starting another into the same pane.
- **The job spinner can leave the footer clipped.** In the Chatty layout, a job that ran longer than 100 ms (so the spinner showed) left the footer cut off at the sidebar's width for good. A job that finished sooner was fine, and a small test app was fine, so it depends on the layout. A full repaint in the finish and cancel functions (`tui.action.redraw`) repaired it; it cost 38 to 43 ms, once per job. Found with a real-window screenshot, not a text capture.

## Performance

- **Redrawing a Markdown view renders all of its text every time.** In the Chatty app a redraw cost about 5 ms for one message, 41 ms for 104, 106 ms for 406 and 400 ms for 1008. At the 20 redraws a second of a typed-out answer, that is a frozen interface in a long chat. Fixes that worked: redraw at most 10 times a second, skip the redraw when nothing changed (as `follow` does), and draw only the newest part of a long transcript (40 messages kept it near 27 ms however long the chat). See [Fast apps](performance.md#10-a-long-transcript-or-log).
- Reading the stream file with `$(<file)` costs no fork.
- A full repaint (`tui.action.redraw`) measured 38 to 43 ms: fine once per job, not per tick.
- Updating a progress bar on every tick is cheap, but it is still a redraw: update it when the value changed.
