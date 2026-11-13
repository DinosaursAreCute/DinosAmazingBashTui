"""Scenario file of the renderer profiler: which cases a run can select. Same shape as the DABT profiler's scenario files.

  TITLE      shown in the report header
  CASES      the bash file that defines the cases (rc_case ...), relative to this file
  OPTIONS    defaults of --set NAME=VALUE: calls (calls per case, 0 = the harness default), width (the renderers' TR_WIDTH), wait (seconds a
             rendered result stays in the --watch window, 0 = no wait)
  SCENARIOS  [(name, description, spec)]; spec None = every case, else {"only": [renderers], "tags": [tags]}: the cases of those renderers
             that carry one of the tags (a missing key means no restriction on that side). Tags: plain, args, unicode, small, large.
"""
TITLE = "RENDERER PROFILE"
CASES = "cases.sh"
OPTIONS = {"calls": "0", "width": "100", "wait": "0"}

SCENARIOS = [
    ("full", "Every renderer, every dataset and argument set", None),
    ("text", "box, divider, alert, quote: framed text, wrapping, unicode", {"only": ["box", "divider", "alert", "quote"]}),
    ("tables", "table, kv, list, columns, badges, tree: rows and nesting", {"only": ["table", "kv", "list", "columns", "badges", "tree"]}),
    ("bars", "hbar, vbar, gauge, sparkline: counts and widths", {"only": ["hbar", "vbar", "gauge", "sparkline"]}),
    ("charts", "linechart, histogram, csv charts: points and series", {"only": ["linechart", "histogram", "csv_hbar", "csv_vbar", "csv_linechart"]}),
    ("stats", "scatter, boxplot, forest, heatmap: statistics charts", {"only": ["scatter", "boxplot", "forest", "heatmap"]}),
    ("banner", "banner: fonts, text length, scale", {"only": ["banner"]}),
    ("small", "The smallest dataset of every renderer", {"tags": ["small"]}),
    ("large", "The largest dataset of every renderer", {"tags": ["large"]}),
    ("args", "Every case that passes arguments (widths, colours, ranges, styles)", {"tags": ["args"]}),
    ("unicode", "Wide and accented content", {"tags": ["unicode"]}),
]
