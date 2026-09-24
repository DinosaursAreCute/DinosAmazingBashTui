### `tui.factory.button`

```bash
tui.factory.button NS PANE ROW TEXT [ACTION]
```

Creates a button with a generated id, tracked under namespace `NS`. `ACTION` is called as `ACTION ID`.

**Sets:** `_TUI_FACTORY_LAST_ID`.

**Example**

```bash
for f in *.log; do
    tui.factory.button files list_pane "$((row++))" "$f" open_file
done
```

**See also:** [`tui.button`](/api/widgets/tui.button.html)
