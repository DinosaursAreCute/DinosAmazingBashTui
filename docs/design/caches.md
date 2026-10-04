# Caches: keys, owners and invalidation

Every cache in `lib/`, in one table. The performance notes (`fork-elimination-and-redundant-work-deletion.md`) say why each exists;
this page says where its edges are.

## The rules

1. **One way to invalidate.** A module that changes something cached calls `_tui.epoch_bump KIND...`
   (`lib/state/tui_epoch.sh`). It never writes another module's generation counter or dirty flag. A module may reset
   its own cache's internals (the hit index clears its own flag after a rebuild).
2. **Kinds, not caches.** The caller says what changed; the table below says which caches depend on it.

   | Kind | Means | Effect |
   |---|---|---|
   | `layout` | a pane's rect, or the split / gap / pad / border / min / max math changed | `_TUI_LY_GEN` +1 |
   | `style` | a style table was written or replaced | `_TUI_RC_EPOCH` +1 |
   | `widgets` | the widget list or a widget's type changed | focus order and hit index marked dirty |
   | `hit` | only the zones moved (scroll, collapse, resize) | hit index marked dirty |
   | `focus` | only the focus order changed | focus order marked dirty |

3. **Content-addressed caches need no invalidation.** Their key holds every input, so a changed input is a different
   key. Anything that is not a plain value (a `${expr}` text) is never stored.
4. **`TUI_CACHES=off`** bypasses every cache marked "toggled" below. The two modes must behave the same; any
   difference is a bug in a cache boundary (see "Checking the boundaries").

## The table

| Cache | State | Owner | Key | Invalidated by | `TUI_CACHES=off` |
|---|---|---|---|---|---|
| Layout memo | `_TUI_LY_KEY`, `_TUI_LY_GEN_AT` | `layout/tui_layout.sh` | pane's own (row, col, h, w) and `_TUI_LY_GEN` | `epoch_bump layout` (any split, gap, pad, border, min/max, fuse, collapse, resize, page load or replay) | toggled: every layout recomputes |
| Widget position cache | `_TUI_WPC` | `tui.sh` (`_tui._widget_pos`) | pane rect, insets, widget row, pads, width / height / expand / rowspan / min / max, valign, scroll offset, stuck id | key holds its inputs; cleared when a widget type's handlers change (`_tui_widget.bind`); bounded at 4096 entries; never stored for types with a MEASURE handler (their height depends on content) | toggled |
| Row-fragment cache | `_TUI_RC` | `render/tui_rowcache.sh` | geometry, focus / hover state, resolved text, the style strings drawn with (content-addressed) | none needed; bounded at 4096; skipped for `${expr}` text | toggled (`_TUI_ROWCACHE=0`) |
| Paint diff | `_TUI_PAINT_PREV`, `_TP_LAST` | `render/tui_paint.sh` | screen row number to the bytes sent for it last time | `tui.paint.reset` (erase, resize, terminal takeover); any flush that bypassed the diff | toggled: every row is sent |
| Hit index | `_TUI_HZ_*` | `input/tui_hit.sh` | none: rebuilt wholesale from the current layout | `epoch_bump widgets` or `hit`; rebuilt by the next lookup or `tui.render` | toggled: stays dirty, rebuilt on every lookup |
| Focus order | `_TUI_FOCUSABLE`, `_TUI_FOCUS_TAB`, `_TUI_FOCUS_POS` | `input/tui_focus.sh` | none: rebuilt wholesale | `epoch_bump widgets` or `focus`; rebuilt by `_tui_focus.ensure` | toggled: stays dirty |
| Saved base frame | `_TUI_BASE_*` | `chrome/tui_modal.sh` | flush generation, `_TUI_RC_EPOCH`, rows, cols | `epoch_bump style`, a resize, any flush not folded into it | toggled: never valid, dismiss repaints |
| Page cache | `_TUI_CACHE_PAGE`, `_TUI_CACHE_SIG`, `_TUI_CACHE_MTIME` | `markup/tui_cache.sh` | page file path | the mtimes of the page and its includes change (unless `TUI_CACHE_TRUST`); scripts, `on_visit` and gotos always run live; on replay the theme is re-applied and styles re-baked when the overlay differs from the one baked in | toggled: `tui.cache.valid` is false, every visit builds |
| Theme memo | `_TUI_THEME_MEMO`, `_TUI_THEME_STAMP` | `markup/tui_cache.sh` | stylesheet path | its mtime changes (unless trusted) | toggled: parsed from disk |
| SGR memo | `_TUI_SGR_MEMO` | `tui.sh` (`_tui._sgr_from`) | fg, bg, mods (content-addressed) | none; bounded at 4096 | exempt |
| Visible width / slice memos | `_TUI_VW_MEMO`, `_TUI_VS_MEMO` | `tui.sh` | the string (and offsets) | none; bounded at 4096 | exempt |
| Content-need index | `_TUI_CN_ROW`, `_TUI_CN_LEN` | `tui.sh` | built at the start of `tui.render` while `_TUI_CN_ON=1`, dropped at its end | not a cache across frames | n/a |
| Effective min size | `_TUI_P_EFFECTIVE_MINW/H` | `tui.sh` (`_tui._refresh_content_fit`) | derived from widget content on every render for leaf panes | recomputed each render; part of the page snapshot | n/a |
| Refresh signatures | `_TUI_P_SIG_*` | `markup/tui_refresh.sh` | a signature of each pane's attributes and nodes | compared on `tui.page.refresh`; only changed panes are rebuilt | exempt: an incremental rebuild, not a stored result |
| Binding rows | `_TUI_BIND_GEN` | `input/tui_input.sh` | a counter bumped by every bind change | consumers (footer, text, shell) compare it | exempt |

"Exempt" caches are content-addressed or incremental: they cannot serve a stale result, so switching them off would
test nothing.

## Checking the boundaries

* `TUI_CACHES=off tools/t.sh` and `tools/t.sh` must both pass. Tests that assert how a cache behaves (a hit, a dirty
  flag, a suppressed row) start with `_t_needs_caches || return 0` and are skipped when caches are off.
* `tools/decoupling/cache_ab.sh [PAGE...]` replays one scripted session (resize and back, theme set / switch / clear,
  leave the page and return, a widget edit, a collapse) in both modes and compares the frame after each step. It found two
  stale-cache bugs: a cached replay kept the old theme's bold after `tui.theme.clear`, and it started `on_visit` with the
  recording's focus instead of none.
* A new cache adds a row here, calls `_tui.epoch_bump` from whoever changes its inputs, and gets a
  `((_TUI_CACHES))` guard at its lookup.
