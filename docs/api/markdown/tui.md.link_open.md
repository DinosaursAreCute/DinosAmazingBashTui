### `tui.md.link_open`

```bash
tui.md.link_open PANE
```

Follows the focused link of the document shown in `PANE`. Returns `1` when no link is focused.

**Notes**

- The function set with [`tui.md.on_link`](/api/markdown/tui.md.on_link.html) is called first, as `FN URL TEXT PANE`; return `0` when it handled the link.
- `#anchor` scrolls to that heading (GitHub-style slug).
- A relative `.md` or `.md#anchor` link loads that file in the pane and calls the function set with [`tui.md.on_navigate`](/api/markdown/tui.md.on_navigate.html).
- Anything else is copied to the clipboard with a notification.
- Before a jump, the position is pushed for [`tui.md.back`](/api/markdown/tui.md.back.html).

**Example**

```bash
tui.md.link_open docs
```
