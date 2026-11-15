# Data: datasets and widgets that follow them

A **dataset** is a named list of rows kept by DABT. Code appends, changes and removes rows with one call each; widgets bound to the dataset update by themselves. The point is that a callback changes the data and nothing else: there is no function that rebuilds a table, a list or a chart from scratch.

```bash
tui.data.new latency --cols "ms" --max 60     # the newest 60 samples
tui.data.append latency 12                    # a callback adds one
```
```xml
<data name="latency" cols="ms" max="60"/>
<spark id="trend" from="latency" col="ms" last="30"/>
<gauge id="now"   from="latency" col="ms" max="200"/>
```

Everything below runs in the app's own shell: no process is started, and a change costs a few array operations.

## Rows, ids and columns

- A **row** is its cells separated by `|`, the same notation as `tui.table.set`: `"web1|up|12"`. A cell cannot contain `|`.
- **Columns** are numbered from 0. `--cols "host|state|ms"` also gives them names, so `state` and `1` mean the same column. The names become a table's header.
- A dataset with `--key COL` is **keyed**: the cell in that column identifies the row, there is one row per key, and a row you append with an existing key replaces that row. An **ID** in a call is the key. Without `--key` an ID is the 0-based index of the row.
- `--max N` keeps the newest `N` rows. The oldest goes when one is added past `N`; the others do not move, so a rolling window of any size costs the same per append.

```bash
tui.data.new hosts --cols "host|state|ms" --key host
tui.data.new log   --cols "time|text"     --max 200
tui.data.new ring  --max 8
```

`tui.data.new` on a name that exists does nothing, so a page can declare its datasets on every visit and keep what they hold.

## Changing data

| Call | Does | Cost |
|---|---|---|
| `tui.data.append NAME ROW...` | adds rows at the end (a keyed dataset replaces the row with that key) | constant per row |
| `tui.data.set NAME ID COL VALUE` | changes one cell | constant |
| `tui.data.replace NAME ID ROW` | changes a whole row | constant |
| `tui.data.remove NAME ID...` | deletes rows | one rebuild, however many ids |
| `tui.data.clear NAME` | deletes every row | one rebuild |
| `tui.data.sort NAME COL [--desc] [--num]` | sorts in place | n log n |

```bash
tui.data.append hosts "web1|up|12" "db1|up|31"      # two rows
tui.data.set hosts db1 state down                    # one cell, by key
tui.data.append hosts "web1|up|9"                    # replaces web1: same key
tui.data.remove hosts db1                            # gone
```

Every change marks the dataset. When the callback that made it returns, the widgets bound to the dataset are updated, once, however many calls changed it.

## Reading data

```bash
tui.data.count hosts n                 # number of rows
tui.data.has   hosts web1              # rc 0 when the row exists
tui.data.get   hosts web1 row          # "web1|up|9"
tui.data.cell  hosts web1 ms ms        # one cell
tui.data.rows  log recent --last 10    # an array, oldest first
tui.data.col   latency ms values       # one column into an array
tui.data.find  hosts state down who    # id of the first row whose cell matches
tui.data.stat  latency ms avg mean     # sum | min | max | avg | count
```

- The last argument of the reading calls is the **name** of your variable or array. Their own variables start with `_`, so `n`, `row`, `values` or any other name of yours is safe.
- `tui.data.stat` handles numbers with decimals (`12.5`) in thousandths, so it needs no fork and no floating point. Cells that are not numbers are skipped. `avg` keeps three decimals.
- `tui.data.sort --num` compares numbers; without it text is compared the way `[[ a < b ]]` does, which follows the locale.

## Showing a dataset

A widget follows a dataset through a **binding**. In markup it is the `from=` attribute:

| Widget | Shows | Attributes |
|---|---|---|
| `<table from="hosts" show="host,ms" heat="ms:50:100"/>` | the `--cols` names as header and every row. A keyed dataset keeps the selected row when rows change. `heat` colours the numbers of a column (`tui.table.heat`) | `show` (the columns to show, default all), `heat` |
| `<list from="hosts" col="host"/>` | one item per row | `col` |
| `<label from="nodes" key="web1" col="state" format="%s"/>` | the cell `col` of the newest row, or with `key` of that row of a keyed dataset | `col`, `format` (one `%s`), `key` |
| `<spark id="s" from="latency" col="ms" last="30" width="30"/>` | one block glyph per value: `▁▃▅█` | `col`, `last` (default 24), `width` |
| `<gauge id="g" from="cpu" col="pct" max="100" width="fit" levels="60,85"/>` | the newest value as a bar and a percent; `width="fit"` is as wide as its pane; `levels` colours it green, yellow or red by the percent (classes `gauge_ok`, `gauge_warn`, `gauge_crit`) | `col`, `max`, `width`, `levels` |
| `<chart id="c" from="latency" type="linechart" col="ms" args="-h 8"/>` | a pane holding a chart; see [Charts](charts.md) | `type`, `col`, `label`, `last`, `args` |

`col` is a 0-based index or a name. `<table>` keeps its own `data=` attribute for literal rows; `from=` is the dataset.

From code the same thing is `tui.data.bind NAME WIDGET KIND [OPTION=VALUE...]`:

```bash
tui.data.bind latency lbl_trend spark col=ms last=30
tui.data.bind hosts   tbl_hosts table
tui.data.unbind lbl_trend
```

**When a widget redraws.** After the callback that changed the dataset returns, and on every tick. It is drawn only if the text it would show is different from what it showed, so a timer that appends the same value every second does not repaint anything. `tui.data.flush` forces the update inside a long callback.

## Where a dataset lives: scope

| Scope | Lives | Use for |
|---|---|---|
| `session` (default) | until the app exits, across pages | counters, histories, shared state |
| `page` | until the page is left | a table of this page's rows |
| `disk` | also in `$TUI_HOME/state/data/NAME`; read when it is declared, written when the page is left and when the app exits | settings, a log that should survive a restart |

```bash
tui.data.new recent --cols "path" --max 20 --scope disk
```

A dataset also works as **page state**. Two columns and a key make a place to put values that belong together; give it a scope and it is kept as long as you chose:

```bash
tui.data.new state --cols "key|value" --key key --scope disk
tui.data.append state "theme|dracula"        # set
tui.data.cell state theme value theme        # get
```

## Patterns

**A rolling window.** `--max` plus a bound spark: the timer only appends.

```bash
tui.data.new cpu --cols pct --max 40
sample() { tui.sys.cpu; tui.data.append cpu "$TUI_SYS_CPU"; }
tui.every 1 sample
```
```xml
<spark id="cpu_trend" from="cpu" last="40"/>
<gauge id="cpu_now"   from="cpu" max="100"/>
```

**A live table of things that come and go.** Key it by what identifies a thing; append updates a known one and adds a new one.

```bash
tui.data.new procs --cols "pid|name|cpu" --key pid
on_ps_line() { tui.data.append procs "$1|$2|$3"; }       # add or update
on_exit_pid() { tui.data.remove procs "$1"; }
```
```xml
<table id="tbl_procs" from="procs"/>
```

**A sorted view.** Sort after changing; the table follows.

```bash
tui.data.sort procs cpu --num --desc
```

**Numbers over rows.** `tui.data.stat` instead of a loop of your own.

```bash
tui.data.stat latency ms max worst
tui.data.stat latency ms avg mean
```

## Things to know

- Names of datasets are global. Use a prefix for a dataset of a plugin or a component.
- In a page, `<data>` declares the dataset at build time and the `from=` bindings follow it. A dataset that a script creates must exist before the page that binds it is built: declare it in the shell's script or with `<data>`.
- A page replayed from the page cache re-declares its datasets and bindings; the rows of a `session` dataset are still there.
- Binding to a widget that is not on the page is skipped, and bindings are dropped when the page is left.
- `tui.data.remove`, `tui.data.sort` and `tui.data.clear` rebuild the row array. For a window that only grows at the end use `--max` instead of removing old rows by hand.
- `tui.hist.push` and `tui.hist.get` (rolling series of numbers) keep working. A dataset with `--max` does the same and adds columns, keys, statistics and widgets that follow it.

## See also

- [Charts](charts.md): `tui.chart`, `tui.chart.spark`, `tui.chart.gauge`.
- [A live dashboard](../tutorials/live-dashboard.md): a tutorial that builds a monitor from one dataset.
- [API: Data](../api/data.md).
