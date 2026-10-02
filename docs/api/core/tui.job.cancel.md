### `tui.job.cancel`

```bash
tui.job.cancel ID
```

Stops the background job `ID` started with [`tui.job.run`](/api/core/tui.job.run.html). Its `DONEFN` is not called, its files are removed, and the spinner goes away if it was the last job.

**Returns:** `1` when no job has that ID.

**Notes**

- The job's own process is stopped. A program that `WORKFN` started (for example `sleep`) can keep running until it ends.

**See also:** [`tui.job.running`](/api/core/tui.job.running.html)
