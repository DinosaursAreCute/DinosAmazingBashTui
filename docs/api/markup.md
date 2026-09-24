# Markup: pages, cache & validation

`lib/markup/tui_markup.sh`, `lib/markup/tui_cache.sh`, `lib/markup/tui_validate.sh` - the XML page loader, its record/replay cache, and the validator that checks pages before an app starts. Guide: [../guide/markup.md](../guide/markup.md). ← [API index](README.md) for the full module list and a task-oriented tour with examples.

Functions return `0` unless their entry says otherwise.

## Pages

<!-- api: tui.load tui.goto tui.reset_ui tui.load_cached -->

| Function | Summary |
|---|---|
| [`tui.load`](markup/tui.load.md) | Parses a markup page and builds its panes and widgets through `tui.*` calls. Nothing is drawn. |
| [`tui.goto`](markup/tui.goto.md) | Switches to another page: clears the current UI, loads `FILE` (from the page cache when valid) and repaints in one frame. |
| [`tui.reset_ui`](markup/tui.reset_ui.md) | Clears the whole UI and leaves an empty full-screen `root` pane. [`tui.goto`](/api/markup/tui.goto.html) calls it. |
| [`tui.load_cached`](markup/tui.load_cached.md) | Like [`tui.load`](/api/markup/tui.load.html), but replays the page from its recorded call log when it is cached and unchanged, and records it otherwise. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative markup/tui.load.md %}

{% include_relative markup/tui.goto.md %}

{% include_relative markup/tui.reset_ui.md %}

{% include_relative markup/tui.load_cached.md %}

</div>

<!-- /api -->

## Page cache

A loaded page is recorded as the list of `tui.*` calls it made and replayed on later visits, as long as the page and its includes keep their mtimes. Why and how: [../design/write-ahead-logging-and-replay.md](../design/write-ahead-logging-and-replay.md). Cache keys are absolute, normalized paths.

<!-- api: tui.cache.valid tui.cache.record tui.cache.replay tui.cache.signature tui.cache.deps_of tui.cache.dump_dir tui.cache.load_dir tui.cache.disk_dir tui.cache.warm_with_spinner tui.cache.init tui.cache.cleanup -->

| Function | Summary |
|---|---|
| [`tui.cache.valid`](markup/tui.cache.valid.md) | Returns `0` when `FILE` has a recorded page and neither it nor any of its includes changed since, else `1`. |
| [`tui.cache.record`](markup/tui.cache.record.md) | Loads `FILE` with recording on and stores the call log and a signature of its files. |
| [`tui.cache.replay`](markup/tui.cache.replay.md) | Rebuilds a page by replaying its recorded call log. Returns `1` when nothing is recorded for `FILE`. |
| [`tui.cache.signature`](markup/tui.cache.signature.md) | Prints `path=mtime;` for every file, sorted by path, as one line without a newline. Used as the cache validity key. |
| [`tui.cache.deps_of`](markup/tui.cache.deps_of.md) | Appends `FILE` and every file it includes, recursively, to the array named `ARRAY_NAME`, as absolute paths. |
| [`tui.cache.dump_dir`](markup/tui.cache.dump_dir.md) | Writes every recorded page to `DIR`, three files per page (`.key`, `.cache`, `.sig`). |
| [`tui.cache.load_dir`](markup/tui.cache.load_dir.md) | Reads pages written by [`tui.cache.dump_dir`](/api/markup/tui.cache.dump_dir.html) and drops every entry that is no longer valid. |
| [`tui.cache.disk_dir`](markup/tui.cache.disk_dir.md) | Prints the folder of the persistent page cache, `$TUI_HOME/cache/pages`, without a newline. |
| [`tui.cache.warm_with_spinner`](markup/tui.cache.warm_with_spinner.md) | Records pages into the cache in a background worker while showing the D.A.B.T logo and a progress bar. |
| [`tui.cache.init`](markup/tui.cache.init.md) | Wraps the builder functions so page loads can be recorded. Called once when `tui.sh` is sourced; never call it again. |
| [`tui.cache.cleanup`](markup/tui.cache.cleanup.md) | Removes the temporary stylesheet stamp folder. Called on exit. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative markup/tui.cache.valid.md %}

{% include_relative markup/tui.cache.record.md %}

{% include_relative markup/tui.cache.replay.md %}

{% include_relative markup/tui.cache.signature.md %}

{% include_relative markup/tui.cache.deps_of.md %}

{% include_relative markup/tui.cache.dump_dir.md %}

{% include_relative markup/tui.cache.load_dir.md %}

{% include_relative markup/tui.cache.disk_dir.md %}

{% include_relative markup/tui.cache.warm_with_spinner.md %}

{% include_relative markup/tui.cache.init.md %}

{% include_relative markup/tui.cache.cleanup.md %}

</div>

<!-- /api -->

## Validation

`tui.start` and `tui.start_cached` validate every page before the terminal is taken over. Errors abort the start (`dabt --ignore-invalid-xml` or `TUI_IGNORE_INVALID_XML=1` starts anyway and shows a notification); warnings are only logged. `TUI_VALIDATE=0` skips validation. A clean result is remembered in `$TUI_HOME/cache/validated`, so only the first start after a change pays for the check.

The default rules live in `lib/markup/tui_validate_rules.sh` and use the same registration functions an app can call to add its own.

<!-- api: tui.validate.files tui.validate.page tui.validate.report tui.validate.log tui.validate.messages -->

| Function | Summary |
|---|---|
| [`tui.validate.files`](markup/tui.validate.files.md) | Validates pages and their includes, replacing any earlier findings. |
| [`tui.validate.page`](markup/tui.validate.page.md) | Validates one page, adding to the current findings. Ids are checked per page. |
| [`tui.validate.report`](markup/tui.validate.report.md) | Prints every finding, then a `N error(s), M warning(s)` summary. Prints nothing when there are no findings. |
| [`tui.validate.log`](markup/tui.validate.log.md) | Writes every finding to the app log ([`tui.log`](/api/core/tui.log.html)) with level `error` or `warn`. |
| [`tui.validate.messages`](markup/tui.validate.messages.md) | Formats every finding into the array `_TV_LINES`, one sentence each, in the order found. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative markup/tui.validate.files.md %}

{% include_relative markup/tui.validate.page.md %}

{% include_relative markup/tui.validate.report.md %}

{% include_relative markup/tui.validate.log.md %}

{% include_relative markup/tui.validate.messages.md %}

</div>

<!-- /api -->

### Writing rules

<!-- api: tui.validate.tag tui.validate.container tui.validate.widget tui.validate.self_closing tui.validate.require tui.validate.enum tui.validate.int tui.validate.conflict tui.validate.needs tui.validate.parent tui.validate.parent_split tui.validate.rule tui.validate.attr tui.validate.here tui.validate.error tui.validate.warn tui.validate.error_at tui.validate.warn_at -->

| Function | Summary |
|---|---|
| [`tui.validate.tag`](markup/tui.validate.tag.md) | Declares tags the loader understands. Any other tag is reported as unknown. |
| [`tui.validate.container`](markup/tui.validate.container.md) | Declares tags that may have children (`<tag>…</tag>`). Implies `tui.validate.tag`. |
| [`tui.validate.widget`](markup/tui.validate.widget.md) | Declares widget tags. Their `id` and `pane` are recorded for the cross-reference checks (duplicate ids, missing panes). |
| [`tui.validate.self_closing`](markup/tui.validate.self_closing.md) | Declares tags that must be written self-closing: `<tag … />`. |
| [`tui.validate.require`](markup/tui.validate.require.md) | Declares attributes that must be present and non-empty on `TAG`. Repeated calls add to the list. |
| [`tui.validate.enum`](markup/tui.validate.enum.md) | Restricts an attribute to a list of values. `*` applies it to every tag. |
| [`tui.validate.int`](markup/tui.validate.int.md) | Requires an attribute to be a whole number of at least `MIN` (which may be negative). `*` applies it to every tag. |
| [`tui.validate.conflict`](markup/tui.validate.conflict.md) | Reports an error when both attributes are given on `TAG`. `WHY` is added to the message. |
| [`tui.validate.needs`](markup/tui.validate.needs.md) | Declares that `ATTR` only has an effect when `OTHER="VALUE"`; using it otherwise is reported. |
| [`tui.validate.parent`](markup/tui.validate.parent.md) | Restricts which tags may enclose `TAG`. `-` stands for the top level of the page. |
| [`tui.validate.parent_split`](markup/tui.validate.parent_split.md) | Declares that `ATTR` only has an effect inside a `<pane split="SPLIT">`. |
| [`tui.validate.rule`](markup/tui.validate.rule.md) | Registers a custom check. |
| [`tui.validate.attr`](markup/tui.validate.attr.md) | Inside an element rule: stores the value of attribute `NAME` in `REPLY`. Returns `1` when the attribute is absent. |
| [`tui.validate.here`](markup/tui.validate.here.md) | Inside an element rule: stores the location of the current element (or of `ATTR` on it) in `REPLY` as `file\|line\|col`. |
| [`tui.validate.error`](markup/tui.validate.error.md) | Inside an element rule: reports an error at the current element, or at attribute `ATTR`. |
| [`tui.validate.warn`](markup/tui.validate.warn.md) | Inside an element rule: reports a warning at the current element, or at attribute `ATTR`. Warnings are logged but never stop a start. |
| [`tui.validate.error_at`](markup/tui.validate.error_at.md) | Reports an error at `LOC` (`file\|line\|col`; `col` may be empty). For end rules, which have no current element. |
| [`tui.validate.warn_at`](markup/tui.validate.warn_at.md) | Reports a warning at `LOC` (`file\|line\|col`). |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative markup/tui.validate.tag.md %}

{% include_relative markup/tui.validate.container.md %}

{% include_relative markup/tui.validate.widget.md %}

{% include_relative markup/tui.validate.self_closing.md %}

{% include_relative markup/tui.validate.require.md %}

{% include_relative markup/tui.validate.enum.md %}

{% include_relative markup/tui.validate.int.md %}

{% include_relative markup/tui.validate.conflict.md %}

{% include_relative markup/tui.validate.needs.md %}

{% include_relative markup/tui.validate.parent.md %}

{% include_relative markup/tui.validate.parent_split.md %}

{% include_relative markup/tui.validate.rule.md %}

{% include_relative markup/tui.validate.attr.md %}

{% include_relative markup/tui.validate.here.md %}

{% include_relative markup/tui.validate.error.md %}

{% include_relative markup/tui.validate.warn.md %}

{% include_relative markup/tui.validate.error_at.md %}

{% include_relative markup/tui.validate.warn_at.md %}

</div>

<!-- /api -->
