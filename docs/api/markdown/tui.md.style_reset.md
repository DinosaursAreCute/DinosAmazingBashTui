### `tui.md.style_reset`

```bash
tui.md.style_reset [CLASS]
```

Restores the default style of `CLASS`, or of every style class when `CLASS` is omitted.

**Parameters**

- `CLASS`: optional, one style class as for [`tui.md.style_spec`](/api/markdown/tui.md.style_spec.html).

**Notes**

- Also forgets the specs set by [`tui.md.style_spec`](/api/markdown/tui.md.style_spec.html) for the affected classes.
- The profile style of each affected class shows again (see [`tui.md.profile`](/api/markdown/tui.md.profile.html)).

**Example**

```bash
tui.md.style_reset h1     # only h1
tui.md.style_reset        # every class
```
