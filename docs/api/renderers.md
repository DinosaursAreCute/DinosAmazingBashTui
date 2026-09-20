# Renderers

`lib/terminal_renderer.sh` - widget-string renderers that work standalone (no `tui.sh` state) or inside panes.

```bash
source lib/terminal_renderer.sh
box "Pure bash"                                   # print
tui.output pane "$(box_string 'Pure bash')"       # string form: lines joined by literal \n
bash lib/terminal_renderer.sh hbar "Bash:100" "Fun:99" -w 40 -c GREEN -s   # CLI; -s = string mode
```

Each renderer has a `_build` (fills `TR_RESULT`, private), a printing form and a `_string` form. `TR_WIDTH=N` sets the width to lay out to (defaults to the terminal width, probed at most every 2 s); inside panes set it from `tui.pane_size`/`tui.get.dimensions --content`.

| Command | Arguments | Notes |
|---|---|---|
| `box` | `"message"` | Bordered box. |
| `divider` | `["label"]` | Rule with optional label. |
| `alert` | `info\|warn\|error\|success "msg"` | Callout. |
| `table` | `"H1\|H2" "r1\|r2"...` | Header row first, cells split on `\|`. |
| `kv` | `"Key: Val"... [-t dots\|plain\|dashes]` | Leader style between key and value. |
| `hbar` | `"Label:Value"... [-m max] [-n min] [-w width] [-lw label_w] [-c COLORS]` | Uncolored by default (safe in tables). |
| `vbar` | `"Label:Value"... [-h rows] [-m] [-n] [-tw total_w] [-cw col_w] [-c COLORS]` | |
| `gauge` | `VALUE [-m max] [-n min] [-l label] [-lw] [-w width] [-c COLOR]` | |
| `sparkline` | `"v1 v2 ..." [-d delim] [-w] [-m] [-n] [-c COLOR]` | Resamples to `-w`. |
| `linechart` | `"Series:v1,v2,..."... [-h rows] [-w plot_w] [-m] [-n] [-c COLORS]` | Resamples to `-w`. |
| `csv_hbar`, `csv_vbar`, `csv_linechart` | `FILE.csv [--header] [-d delim]` + the plain chart's flags | See `examples/csv-charts/`. |
| `banner` | `"TEXT" [FONT] [SCALE]` | Fonts: `block5 seg3 box3 blk3 half2`; `banner --list` shows glyph sets. |
| `tree` | `"root" "  child"...` | Two-space indent per level. |
| `columns` | `[-h "Hdr"] "col1" "col2"...` | Side by side. |
| `badges` | `"pass:Build" "fail:Test"...` | Status tags. |
| `list` | `[-n] [-s "▸"] "item"...` | Bullet or numbered. |
| `quote` | `[-a "Author"] "text"` | Block quote. |

**Colors:** `-c` takes names from `lib/colors.sh` (`RED`, `BRIGHT_CYAN`, `DIM_YELLOW`, ...), comma separated for several bars/series. `vbar`, `linechart` and `gauge` have sensible defaults.

**Fixed-size charts:** every chart takes `-m/-n` (pin the scale instead of scaling to the current data) and a sizing flag so a live chart never resizes between refreshes; `linechart`/`sparkline` resample history to fit `-w` exactly. For a chart that fills a pane compute the size once from `tui.get.dimensions --content PANE`. `share/demo/monitor_callbacks.sh` drives all four live.

More: [CSV chart examples](../../examples/csv-charts/README.md) · everything in one table: [reference.md](reference.md#renderers) · the raw escape helpers underneath: [terminal-controls.md](terminal-controls.md).
