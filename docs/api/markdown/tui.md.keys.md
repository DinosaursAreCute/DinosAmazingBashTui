### `tui.md.keys`

```bash
tui.md.keys PANE reader|chords|none
```

Chooses which default Markdown keys act on `PANE` (`<markdown keys="..."/>` does the same in markup).

**Parameters**

- `reader`: the alt chords and the plain reading keys: `n` `N` next / previous link, `Enter` follow, `b` / `Backspace` back, `/` search, `]` `[` next / previous match, `o` outline, `z` fold, `y` / `Y` copy section / document, `g` `G` top / bottom. Plain keys act only while the pane has the keyboard (click it or press `f6`), so they never take keys from a text box.
- `chords` (the default): only the alt chords (`alt+j`, `alt+k`, `alt+l`, `alt+b`, `alt+left` / `alt+right` (back / forward) and the thumb buttons, `alt+s`, `alt+g`, `alt+h`, `alt+o`, `alt+z`, `alt+y`, `alt+u`).
- `none`: no default Markdown key acts on the pane.

**Notes**

- A key acts on the keyboard pane, else the pane under the pointer, else the pane of the focused widget, else the only (or last shown) Markdown pane. `f2` lists the keys.
- The keys are the `markdown` and `markdown_reader` default groups: `tui.defaults.off markdown_reader` removes the plain ones everywhere. Your own `tui.bind` always wins.
- Returns 1 for another mode.

**Example**

```bash
tui.md.keys docs reader
```
