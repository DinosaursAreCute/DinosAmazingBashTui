### `tui.data.bind`

```bash
tui.data.bind NAME WIDGET KIND [OPTION=VALUE...]
```

Keeps a widget showing a dataset. Whenever the dataset changes the widget is updated, once, after the callback that changed it, and only when the text it would show is different.

**Parameters**

- `KIND`: what the widget shows.

| `KIND` | Widget | Shows |
|---|---|---|
| `table` | `<table>` | the `--cols` names as header and every row (`show=name,cpu` picks columns); a keyed dataset keeps the selected row |
| `list` | `<list>` | one item per row, the cells of `col` |
| `label` | `<label>` | the cell `col` of the newest row, through `format` (a `printf` format with one `%s`) |
| `spark` | `<label>` | one block glyph per value of `col`, the newest `last` (default 24), `width` cells wide |
| `gauge` | `<label>` | the newest value of `col` as a bar `width` cells wide (default 20) out of `max` (default 100) |
| `chart` | `<pane>` | `tui.chart` of `type` (default `linechart`) over `col` (several, comma separated, for one series each), `label` and `last`, with the renderer flags in `args` |

- `OPTION=VALUE`: `col` is a 0-based column index or a name (default 0). Binding a widget again replaces its binding.
- `width=fit` (spark, gauge) and `-w fit` / `-h fit` in a chart's `args` take the size of the pane the widget is in, less what the widget draws around itself. The size is read when the widget is drawn, so a resized terminal gets it at the next change of the data.
- `key=ID` (label, gauge): show the cell `col` of that row of a keyed dataset instead of the newest row, so a block per node can show its own numbers.
- `levels=WARN,CRIT` (gauge): the widget is restyled with the theme class `gauge_ok`, `gauge_warn` or `gauge_crit` by the percent of `max`.
- `heat=col:WARN:HOT,...` (table): `tui.table.heat` on those columns of the shown header; `show=a,b` picks the columns.
- `class=NAME` (chart): the colours of that class are put back after every reset in the chart, so it keeps the background of its pane.

**Notes**

- In markup the same bindings are written as attributes: `<spark id="s" from="latency" col="ms" last="30"/>`.

**Returns:** `1` for an unknown dataset or kind.

**Example**

```bash
tui.data.bind latency lbl_now label col=ms 'format=now %s ms'
tui.data.bind latency lbl_spark spark col=ms last=30
```
