### `tui.chart`

```bash
tui.chart KIND VAR [--data NAME --col COL [--label COL] [--last N]] [--class CLASS] [RENDERER ARG...]
```

Renders a chart or text block into `VAR`, lines joined by newlines, ready for `tui.output PANE "$VAR"`.

**Parameters**

- `KIND`: one of `box divider alert table kv hbar vbar gauge sparkline linechart csv_hbar csv_vbar csv_linechart scatter boxplot forest heatmap histogram banner tree columns badges list quote`. They are the renderers of `lib/terminal_renderer.sh`, which is read on the first use; their arguments and flags (`-w 40`, `-h 8`, `-c GREEN`) are the ones listed in [Renderers](/api/renderers.html).
- `--class CLASS`: put the colours of a theme class back after every reset in the output, so the chart keeps the background of the pane it is shown in.
- `--data NAME`: build the arguments from a dataset. `--col` names the column (repeat it for several series), `--label` the column of the labels, `--last` limits to the newest rows.

| `KIND` with `--data` | Arguments built |
|---|---|
| `sparkline`, `histogram` | the values of `--col` |
| `hbar`, `vbar` | `LABEL:VALUE` per row (`--label`, default column 0) |
| `linechart`, `boxplot`, `forest` | one series `NAME:v,v,v` per `--col` |
| `table` | the `--cols` header and every row |
| `list` | the cells of `--col` |

**Notes**

- Colours and sizes are the renderer's. Pass `-w` to fit a pane.
- The renderer file defines functions with generic names (`box`, `list`, `table`, `tree`); they are defined in the app's shell once a `KIND` is rendered.

**Notes**

- A size or scale flag (`-w`, `-h`, `-n`, `-m`, ...) whose value is not a number is refused (rc 1, a message on stderr): the renderers loop forever on one.

**Returns:** `1` for an unknown `KIND`, a `KIND` that does not take `--data`, an unknown dataset, or a renderer that refuses its arguments.

**Example**

```bash
tui.chart hbar out --data hosts --col load --label host -w 40
tui.output pane_load "$out"
```
