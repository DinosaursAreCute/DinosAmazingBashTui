### `tui.capture`

```bash
tui.capture VAR CMD [ARGS...]
```

Runs `CMD` and stores its standard output in `VAR`, like `VAR="$(CMD ARGS...)"` but without a subshell.

**Parameters**

- `VAR` - name of the variable that receives the output; trailing newlines are stripped, as `$( )` does.
- `CMD` - a function or command; it runs in the current shell.

**Returns:** the exit status of `CMD`.

**Notes**

- A fork costs 1 ms or more on a busy machine. Use this in callbacks that run on page visits, ticks and input.
- `CMD` shares the shell: variables it sets stay set, and it must not rely on `$( )` isolation.
- Calls can be nested.

**Example**

```bash
tui.capture banner banner_string "DABT"
tui.output out "$banner"
```
