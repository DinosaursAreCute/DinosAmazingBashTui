# Charts and number series

The renderers (`gauge`, `sparkline`, `linechart`, `hbar`, `vbar`, ...) turn numbers into text for a pane. The full list is in the [renderers reference](../api/renderers.md); this page is how to use them in an app.

```bash
tui.require terminal_renderer                 # not `source`: callback files re-run on every page visit
tui.hist.push rate "$value" 30                # rolling series, keeps the newest 30
tui.hist.get rate series                      # space separated, into a variable
tui.capture chart linechart_string "words/s:${series// /,}" -h 6 -w 38 -m 600 -n 0
printf -v chart '%b' "$chart"                 # the _string forms join lines with a literal \n
tui.set_text chart_pane "$chart"
```

> `tui.hist` is a **number series for charts**. It is not input history. For recalling earlier messages with up and down, see [Input bindings](input-bindings.md#recalling-earlier-messages).

## Which chart

| Show | Use |
|---|---|
| one value against a maximum | `gauge` |
| a trend in one row | `sparkline` |
| a series over time | `linechart` |
| a few values compared | `hbar` (rows) or `vbar` (columns) |

## Keep a live chart steady

Pin the scale and the size, or the chart rescales and jumps with every new value:

```bash
linechart_string "rate:$series" -m 600 -n 0 -w 38 -h 6      # max, min, width, rows
```

## Charts from data

`tui.chart KIND VAR ...` renders any renderer into a variable, and can take its numbers from a [dataset](data.md) so there is nothing to collect by hand:

```bash
tui.data.new latency --cols "ms" --max 60
tui.chart linechart plot --data latency --col ms -w 40 -h 8      # lines in $plot
tui.output pane_plot "$plot"
tui.chart hbar bars --data hosts --col load --label host -w 40   # LABEL:VALUE per row
```

| `KIND` with `--data` | Takes |
|---|---|
| `sparkline`, `histogram` | the values of `--col` |
| `hbar`, `vbar` | `LABEL:VALUE` per row (`--label`, default column 0) |
| `linechart`, `boxplot`, `forest` | one series per `--col` (repeat the flag) |
| `table`, `list` | the dataset's rows, or one column |

`--last N` limits to the newest rows. The other kinds (`box`, `alert`, `banner`, `tree`, `scatter`, ...) take the renderer's own arguments: `tui.chart banner big "OK" block5`.

Two chart helpers need no renderer file and do not fork, so a timer may call them:

```bash
tui.chart.spark line -w 24 "${samples[@]}"     # ▁▃▅▇█▅▂ , the newest 24 values
tui.chart.gauge bar 67 100 -w 12               # ████████░░░░ 67%
```

In markup, a chart that follows a dataset is a tag, and nothing else has to be written:

```xml
<data name="latency" cols="ms" max="60"/>
<spark id="trend" from="latency" col="ms" last="30"/>        <!-- one line, a label -->
<gauge id="now"   from="latency" col="ms" max="200"/>        <!-- a bar and a percent -->
<chart id="plot"  from="latency" type="linechart" col="ms" args="-w 40 -h 8"/>   <!-- a pane -->
```

The chart is redrawn when the dataset changed and the text would differ. `args` holds the renderer's flags (`-w`, `-h`, `-c GREEN`, `-m`, `-n`). `tui.hist.push` and `tui.hist.get` keep working; a dataset with `--max` does the same with columns, keys and widgets that follow it.

## Quirks

- `gauge`, `sparkline`, `linechart`, `hbar` and `vbar` use **integer** math. Scale decimals up (words per second times ten) and say so in the legend. `scatter`, `boxplot`, `forest`, `heatmap` and `histogram` accept decimals.
- `tui.hist` values are single words.
- The renderers use variables that are **not local**. A loop around a renderer call that uses `i`, `s` or `e` as its counter can be disturbed by it: pick distinctive names.
- In a **detachable** pane only widgets draw. Fill one label per chart row, and strip the colour escapes first (see [Tabs and menus](tabs-detach-menus.md#quirks)); the chart is then monochrome.
- `tui.output` wants real newlines; `printf '%b'` turns the `\n` of a `_string` result into them.
- Chart text carries colour escapes. Show it with `tui.set_text`, which measures and cuts it. For a chart redrawn many times a second, build full-width rows and use `tui.set_canvas` (see [Animation](animation.md)).

## Performance

Measured on the development machine, per call:

| Call | Cost |
|---|---|
| `gauge`, width 30 | 0.2 ms |
| `sparkline`, 30 points | 1.2 ms |
| `linechart`, 30 points, 3 / 6 / 12 rows | 4.2 / 5.9 / 9.0 ms |
| an empty `$( )` for comparison | 1.3 ms |

Draw a chart when its data changes, once per answer or per second, never once per frame. Use `tui.capture` instead of `$( )` so the call does not fork. In Chatty the speed chart is drawn once per answer and when its tab opens.
