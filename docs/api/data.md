# Data: datasets and bound widgets

`lib/state/tui_data.sh`, `lib/markup/tui_data_tags.sh` - named lists of rows that code appends to, changes and removes, and widgets that follow them. Guide: [Data](../guide/data.md). Tutorial: [A live dashboard](../tutorials/live-dashboard.md).

A row is its cells separated by `|`. An `ID` is the key of the row for a keyed dataset (`--key`), else the 0-based index. A `COL` is a 0-based index or a name from `--cols`. Functions that take a variable or array name (`VAR`, `ARRAY`) keep their own locals under a `_` prefix, so any caller name is safe.

## Declare

<!-- api: tui.data.new tui.data.drop -->

| Function | Summary |
|---|---|
| [`tui.data.new`](data/tui.data.new.md) | Declares a dataset: a named list of rows that code appends to, changes and removes, and that widgets can show. |
| [`tui.data.drop`](data/tui.data.drop.md) | Forgets a dataset, its rows and the bindings of the widgets that showed it. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative data/tui.data.new.md %}

{% include_relative data/tui.data.drop.md %}

</div>

<!-- /api -->

## Change

<!-- api: tui.data.append tui.data.set tui.data.replace tui.data.remove tui.data.clear -->

| Function | Summary |
|---|---|
| [`tui.data.append`](data/tui.data.append.md) | Adds rows at the end. A row is its cells separated by `\|`. |
| [`tui.data.set`](data/tui.data.set.md) | Changes one cell of a row. |
| [`tui.data.replace`](data/tui.data.replace.md) | Changes a whole row. In a keyed dataset the new row may carry another key; the row keeps its position. |
| [`tui.data.remove`](data/tui.data.remove.md) | Deletes rows. Ids that do not exist are skipped. |
| [`tui.data.clear`](data/tui.data.clear.md) | Deletes every row. The dataset stays declared and bound. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative data/tui.data.append.md %}

{% include_relative data/tui.data.set.md %}

{% include_relative data/tui.data.replace.md %}

{% include_relative data/tui.data.remove.md %}

{% include_relative data/tui.data.clear.md %}

</div>

<!-- /api -->

## Read

<!-- api: tui.data.count tui.data.has tui.data.get tui.data.cell tui.data.rows tui.data.col tui.data.find tui.data.stat tui.data.sort tui.data.gen -->

| Function | Summary |
|---|---|
| [`tui.data.count`](data/tui.data.count.md) | Prints the number of rows, or stores it in `VAR`. |
| [`tui.data.has`](data/tui.data.has.md) | Succeeds when a row with that id exists (the key for a keyed dataset, else the 0-based index). |
| [`tui.data.get`](data/tui.data.get.md) | Stores a row, its cells joined by `\|`, in `VAR`. |
| [`tui.data.cell`](data/tui.data.cell.md) | Stores one cell in `VAR`. |
| [`tui.data.rows`](data/tui.data.rows.md) | Fills the array `ARRAY` with the rows, oldest first. With `--last N` only the newest `N` rows. |
| [`tui.data.col`](data/tui.data.col.md) | Fills the array `ARRAY` with one column, oldest first. With `--last N` only the newest `N` values. |
| [`tui.data.find`](data/tui.data.find.md) | Stores the id of the first row whose cell `COL` equals `VALUE` in `VAR`: the key for a keyed dataset, else the 0-based index. |
| [`tui.data.stat`](data/tui.data.stat.md) | Computes `sum`, `min`, `max`, `avg` or `count` over the numeric cells of a column and prints it, or stores it in `VAR`. |
| [`tui.data.sort`](data/tui.data.sort.md) | Sorts the rows in place. The sort is stable. |
| [`tui.data.gen`](data/tui.data.gen.md) | Stores the change counter of a dataset in `VAR`. It grows with every change, so code can tell whether something changed since it last looked. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative data/tui.data.count.md %}

{% include_relative data/tui.data.has.md %}

{% include_relative data/tui.data.get.md %}

{% include_relative data/tui.data.cell.md %}

{% include_relative data/tui.data.rows.md %}

{% include_relative data/tui.data.col.md %}

{% include_relative data/tui.data.find.md %}

{% include_relative data/tui.data.stat.md %}

{% include_relative data/tui.data.sort.md %}

{% include_relative data/tui.data.gen.md %}

</div>

<!-- /api -->

## Show

Widgets follow a dataset through a binding. Markup writes the same bindings as attributes; see [Data](../guide/data.md#showing-a-dataset).

<!-- api: tui.data.bind tui.data.unbind tui.data.flush -->

| Function | Summary |
|---|---|
| [`tui.data.bind`](data/tui.data.bind.md) | Keeps a widget showing a dataset. Whenever the dataset changes the widget is updated, once, after the callback that changed it, and only when the text it would show is different. |
| [`tui.data.unbind`](data/tui.data.unbind.md) | Removes the binding of a widget. The widget keeps what it shows. |
| [`tui.data.flush`](data/tui.data.flush.md) | Updates the widgets bound to datasets that changed since the last flush. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative data/tui.data.bind.md %}

{% include_relative data/tui.data.unbind.md %}

{% include_relative data/tui.data.flush.md %}

</div>

<!-- /api -->

## Keep

<!-- api: tui.data.save tui.data.load -->

| Function | Summary |
|---|---|
| [`tui.data.save`](data/tui.data.save.md) | Writes the rows of a dataset to `$TUI_HOME/state/data/NAME`: one row per line, with `\` and newlines escaped, through a temporary file that is moved into place. |
| [`tui.data.load`](data/tui.data.load.md) | Reads the disk copy of a dataset, replacing its rows. `tui.data.new` with `--scope disk` does this itself. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative data/tui.data.save.md %}

{% include_relative data/tui.data.load.md %}

</div>

<!-- /api -->
