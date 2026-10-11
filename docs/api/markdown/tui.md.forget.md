### `tui.md.forget`

```bash
tui.md.forget PANE
```

Stops re-rendering a pane that was filled by [`tui.md.show`](/api/markdown/tui.md.show.html) or `<markdown>`.

**Parameters**

- `PANE`: the pane id.

**Notes**

- Call it before putting other content into the pane (a tab that shows something else): otherwise the next resize or page switch renders the remembered Markdown over it.
- The pane's current content stays until it is replaced. Unknown panes are ignored.

**Example**

```bash
tui.md.forget content
tui.output content "$other_view"
```
