### `tui.registered`

```bash
tui.registered KIND NAME
```

Looks up `NAME`'s handlers under `KIND` into `$_TUI_REGISTERED` (space-joined, registration order).

**Output:** returns non-zero and empties `$_TUI_REGISTERED` when nothing is registered.

**Example**

```bash
tui.registered widget list && echo "$_TUI_REGISTERED"
```
