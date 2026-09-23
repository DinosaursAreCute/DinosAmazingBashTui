# Markup: pages & cache

`lib/markup/tui_markup.sh`, `lib/markup/tui_cache.sh` - the XML page loader and its record/replay cache. Guide: [../guide/markup.md](../guide/markup.md). ← [API index](README.md) for the full module list and a task-oriented tour with examples.

## Pages and cache

| Function | Parameters | Description |
|---|---|---|
| `tui.load` | `FILE` | Parse a markup file and build panes/widgets. |
| `tui.goto` | `FILE` | Switch page: reset UI, load (cached), keep history and focus. |
| `tui.reset_ui` | | Wipe panes, widgets, timers, modal, footer, page binds; rebuild an empty `root`. |
| `tui.load_cached` | `FILE` | Drop-in `tui.load` that replays a valid cached page. |
| `tui.cache.valid` | `FILE` | Status 0 if the page and all its includes are unchanged since recorded. |
| `tui.cache.record` | `FILE` | Load with recording on and store the call log. |
| `tui.cache.replay` | `FILE` | Rebuild a page from its call log. |
| `tui.cache.signature` | `FILE...` | `path=mtime;…` string for a file set. |
| `tui.cache.deps_of` | `FILE ARRAYNAME` | Append FILE and its (recursive) includes to an array. |
| `tui.cache.dump_dir` / `tui.cache.load_dir` | `DIR` | Write / read recorded pages (invalid entries dropped on load). |
| `tui.cache.disk_dir` | | Print the persistent cache dir (`.cache/tui_pages/`). |
| `tui.cache.warm_with_spinner` | `PAGE...` | Pre-warm pages with a banner and progress bar. |
| `tui.cache.init` | | Wrap the builder functions for recording (done once at load). |
| `tui.cache.cleanup` | | Remove the stamp directory. |
