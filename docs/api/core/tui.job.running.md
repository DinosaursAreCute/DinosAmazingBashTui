### `tui.job.running`

```bash
tui.job.running ID
```

Tells whether the background job `ID` is still pending, that is started with [`tui.job.run`](/api/core/tui.job.run.html) and its `DONEFN` not yet called.

**Returns:** `0` while the job is pending, `1` otherwise.

**Example**

```bash
tui.job.running report && return   # a refresh is already on its way
```

**See also:** [`tui.job.cancel`](/api/core/tui.job.cancel.html)
