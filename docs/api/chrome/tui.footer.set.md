### `tui.footer.set`

```bash
tui.footer.set [ITEMS]
```

Declares the footer bar, as `<footer/>` does. Records the items only; the page layout then leaves the last row free.

**Parameters**

- `ITEMS`: `KEY|LABEL[|WHEN_FN]` items separated by `;`. Empty: the default (quit, command bar, and Back when there is a page to go back to).
  - `KEY` is shown as written (`ctrl+s`), or `@COMMAND` shows whichever key is bound to that command right now, so the footer follows rebinding. An `@COMMAND` with no key is skipped.
  - `WHEN_FN`: the item is shown only while it returns `0`.

**Notes**

- The footer belongs to its page and is removed on page change. At runtime use [`tui.footer.show`](/api/chrome/tui.footer.show.html), which also relayouts.
- Styled with `.footer`, `.footer_key`, `.footer_label`.

**Example**

```bash
tui.footer.set "@tui.action.quit|Quit;@tui.palette.open|Commands;ctrl+s|Save|is_dirty"
```
