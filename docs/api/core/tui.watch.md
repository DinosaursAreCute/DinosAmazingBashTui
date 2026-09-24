### `tui.watch`

```bash
tui.watch PANE CMD [SEC] [ID]
```

Runs a shell command every `SEC` seconds in the background and shows its latest output in a pane, like `watch`.

**Parameters**

- `CMD`: shell code, evaluated with `eval` in a background subshell.
- `SEC`: interval. Default: `2`. Minimum `0.05`.
- `ID`: watch id. Default: `watch_PANE`.

**Returns:** `1` when `PANE` or `CMD` is empty.

**Notes**

- The UI never waits for `CMD`. Only the newest complete output is shown; stderr is discarded.
- Starting a watch with an existing `ID` restarts it.
- Stopped on page change, on exit, and when `PANE` no longer exists.

**Example**

```bash
tui.watch disk "df -h /" 5
```

**See also:** [`tui.watch.stop`](/api/core/tui.watch.stop.html), [`tui.watch.now`](/api/core/tui.watch.now.html)
