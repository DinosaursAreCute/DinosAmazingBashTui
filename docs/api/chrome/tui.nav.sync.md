### `tui.nav.sync`

```bash
tui.nav.sync
```

Re-applies the highlight of every `<nav>`: the item whose page is the current one gets the nav's `active_class`, the others their `item_class`, and the nav buttons are redrawn.

**Notes**

- It runs by itself after every page load (also a cached one), so a click, a shortcut, Back and `tui.goto` need no call. Use it only after code changed what the current page is without loading one.
- The current page is compared by name: the file name without directory and extension (see [`tui.get.page_name`](/api/core/tui.get.page_name.html)).
- Does nothing when the page has no `<nav>`, or for a nav with `active="none"`.
