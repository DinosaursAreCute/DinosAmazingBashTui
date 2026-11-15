# Charts: strings from data

`lib/render/tui_chart.sh` - charts and text blocks as strings, for labels, panes and the `<spark>`, `<gauge>` and `<chart>` widgets. The renderers behind `tui.chart` are in `lib/terminal_renderer.sh`: [Renderers](renderers.md). Guide: [Charts](../guide/charts.md).

`tui.chart.spark` and `tui.chart.gauge` do not fork and do not read the renderer file, so they are cheap enough for a timer. `tui.chart` reads it on first use.

<!-- api: tui.chart tui.chart.spark tui.chart.gauge -->

| Function | Summary |
|---|---|
| [`tui.chart`](charts/tui.chart.md) | Renders a chart or text block into `VAR`, lines joined by newlines, ready for `tui.output PANE "$VAR"`. |
| [`tui.chart.spark`](charts/tui.chart.spark.md) | Stores one block glyph (`▁` to `█`) per value in `VAR`, scaled between the smallest and the largest value. It does not fork and does not read the renderer file. |
| [`tui.chart.gauge`](charts/tui.chart.gauge.md) | Stores a bar and a percent in `VAR`: `████████░░░░ 67%`. It does not fork and does not read the renderer file. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative charts/tui.chart.md %}

{% include_relative charts/tui.chart.spark.md %}

{% include_relative charts/tui.chart.gauge.md %}

</div>

<!-- /api -->
