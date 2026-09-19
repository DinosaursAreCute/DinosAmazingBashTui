# CSV Chart Examples

A tour of the CSV-driven charting commands in [`terminal_renderer.sh`](../../bin/terminal_renderer.sh).

Run it:

```bash
bash examples/csv-charts/run_examples.sh
```

## What's in `data/`

| File                    | Shape                          | Used with        |
|-------------------------|---------------------------------|-------------------|
| `quarterly_revenue.csv` | `label,value` rows              | `csv_hbar`        |
| `language_popularity.csv` | `label,value` rows            | `csv_hbar`        |
| `server_cpu.csv`        | `label,value` rows              | `csv_vbar`        |
| `disk_usage.csv`        | `label,value` rows              | `csv_vbar`, `gauge` (read by hand) |
| `website_traffic.csv`   | header row + multiple series    | `csv_linechart`   |
| `stock_prices.csv`      | header row + multiple series    | `csv_linechart`   |

`csv_hbar`/`csv_vbar` expect plain `label,value` rows (no header needed unless
you pass `--header`). `csv_linechart` expects a header row where the first
column is the x-axis label and every other column is a series name.

Every chart accepts `-c "COLOR,COLOR,..."` (names from
[`bin/colors.sh`](../../bin/colors.sh)) to override the default color cycle,
as shown throughout `run_examples.sh`.
