# A live dashboard

**A step-by-step tutorial for datasets and the widgets that follow them. You should have written a page with panes and buttons before ([Writing your first app](writing-your-first-app.md)).**

## What you will build

A small monitor: a CPU gauge with a sparkline and a line chart that move every second, a table of services whose latencies change, and two buttons, Pause and Sort. The data is made up (`$RANDOM`), so it runs anywhere.

```
┌─ CPU ────────────────────────────────────────┐ 100 │
│  ██████░░░░░░░░░░░░░░░░░░                    │     │
│  ▃▃▇█▃▁▃▅▅▅▁                                 │     │●●●●●●
│  average: 33 %                               │     │
└──────────────────────────────────────────────┘ 0   └──────
┌─ Services ───────────────────────────────────────────────┐
│ name   state  ms                                         │
│ db     slow   42                                         │
│ web    up     12                                         │
└──────────────────────────────────────────────────────────┘
  [ Pause ]
  [ Sort by ms ]
```

The finished app is in [`examples/live-data/`](https://github.com/DinosaursAreCute/DinosAmazingBashTui/blob/main/examples/live-data/); run it with `bash examples/live-data/monitor.sh` from a checkout. The point of the tutorial: **the timer only changes data**. No function in the app draws a table, a gauge or a chart.

## Step 1: the idea

A **dataset** is a named list of rows. You declare it once, then append, change and remove rows. A widget that is *bound* to it shows it and updates when it changes.

```bash
tui.data.new load --cols "pct" --max 60      # a window of the newest 60 samples
tui.data.append load 42                      # add a sample
```

`--max 60` keeps the newest 60 rows; the oldest goes when you add a 61st. That is all a rolling history needs.

## Step 2: declare the data in the page

Open a new app folder with a `config/home.xml`. Declare two datasets before anything uses them:

```xml
<tui on_visit="monitor_visit">
  <script src="home_callbacks.sh"/>
  <footer items="@tui.action.quit,@tui.action.help"/>

  <data name="load"     cols="pct"                max="60"/>
  <data name="services" cols="name|state|ms" key="name"/>
```

- `load` is a plain window of numbers, one column called `pct`.
- `services` has three columns and `key="name"`. With a key, the `name` cell identifies a row: appending a row with a name that exists **replaces** it. One row per service, no search code.

## Step 3: widgets that follow the data

Inside the page's panes, add widgets with `from=`:

```xml
  <pane id="now" title="CPU" border="single" hpad="1">
    <gauge id="g_load" from="load" col="pct" width="24"/>
    <spark id="s_load" from="load" col="pct" last="40"/>
    <label id="l_avg" text="average: -"/>
  </pane>
  <chart id="plot" border="none" from="load" type="linechart" col="pct" args="-w 36 -h 6 -n 0 -m 100"/>

  <pane id="svc" title="Services" border="single">
    <table id="t_svc" from="services" rows="0"/>
  </pane>
```

- `<gauge>` shows the newest value as a bar and a percent (`max` defaults to 100).
- `<spark>` shows the newest `last` values as block glyphs.
- `<chart>` is a pane that holds a line chart. `args` are the chart's own flags: width, height and the scale 0 to 100.
- `<table from="services">` takes its header from the dataset's `cols` and shows every row.

Nothing is in them yet; there is no data. Add two buttons and close the page:

```xml
  <pane id="bar" height="3c" border="none" hpad="1">
    <button id="b_pause" text="[ Pause ]"     action="on_pause" align="left"/>
    <button id="b_sort"  text="[ Sort by ms ]" action="on_sort"  align="left"/>
  </pane>
</tui>
```

(The complete page, with the panes nested the way the picture shows, is `examples/live-data/config/home.xml`.)

## Step 4: a timer that appends

In `home_callbacks.sh`:

```bash
declare -gi PAUSED=0 LOAD=40

monitor_visit() {
	tui.data.append services "web|up|12" "db|up|31" "cache|up|3" "queue|up|7"
	tui.every 1 sample
}

sample() {
	((PAUSED)) && return 0
	((LOAD += RANDOM % 21 - 10))                 # a load that wanders
	((LOAD < 2)) && LOAD=2
	((LOAD > 98)) && LOAD=98
	tui.data.append load "$LOAD"                 # the gauge, the spark and the chart follow
	tui.data.stat load pct avg mean              # statistics without a loop
	tui.set_label l_avg "average: ${mean%%.*} %"
}
```

Run it. The gauge, the sparkline and the line chart move every second, and the code never mentions them. `tui.data.stat` computes `sum`, `min`, `max`, `avg` or `count` of a column.

> **Why nothing flickers.** After a callback returns, DABT updates the widgets bound to the datasets it changed, once, and only those whose text is different from what they show. A timer that appends the same value draws nothing.

## Step 5: change one cell

The services need to move too. Add this to `sample`:

```bash
	local name ms
	for name in web db cache queue; do
		tui.data.cell services "$name" ms ms          # read one cell by key
		((ms = ms + RANDOM % 7 - 3, ms < 1 ? ms = 1 : 0))
		tui.data.set services "$name" ms "$ms"        # change one cell by key
		((ms > 40)) && tui.data.set services "$name" state slow || tui.data.set services "$name" state up
	done
```

`tui.data.cell DATASET KEY COLUMN VAR` and `tui.data.set DATASET KEY COLUMN VALUE` use the key (`web`) and a column name. The table updates, and the row you selected stays selected, because the dataset is keyed.

## Step 6: buttons

```bash
on_pause() {
	if ((PAUSED)); then PAUSED=0; tui.set_label b_pause "[ Pause ]"
	else PAUSED=1; tui.set_label b_pause "[ Resume ]"; fi
}

on_sort() { tui.data.sort services ms --num --desc; }
```

Sorting is a change to the dataset like any other: `--num` compares numbers, `--desc` puts the largest first. The table follows without being told.

## Step 7: keep it

Give a dataset a scope to keep it longer:

```xml
<data name="load" cols="pct" max="60" scope="disk"/>
```

`session` (the default) lives until the app exits, `page` until the page is left, and `disk` is also written to `$TUI_HOME/state/data/` and read at the next start.

## What you learned

| You want | Write |
|---|---|
| a rolling window | `tui.data.new NAME --cols ... --max N`, then `tui.data.append` |
| one row per thing | `--key COLUMN`; appending a known key updates it |
| change a value | `tui.data.set NAME KEY COLUMN VALUE` |
| remove things | `tui.data.remove NAME KEY...` |
| show it | `from="NAME"` on `<table>`, `<list>`, `<label>`, `<spark>`, `<gauge>`, `<chart>` |
| numbers about it | `tui.data.stat NAME COLUMN sum\|min\|max\|avg\|count VAR` |
| order it | `tui.data.sort NAME COLUMN [--desc] [--num]` |

Next: the [Data guide](../guide/data.md) for scopes, patterns and limits, the [Charts guide](../guide/charts.md) for every kind of chart, and the [API](../api/data.md).
