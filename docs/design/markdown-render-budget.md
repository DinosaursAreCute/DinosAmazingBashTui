# Markdown render budget

What the Markdown renderer owes the user, and how it is measured.

## The budget

| What | Budget | Accepted for now |
|---|---|---|
| The **viewport** of a pane painted after a change (open, resize, theme, style): the rows in view, at any scroll position, in any document | 100 ms | under 500 ms |
| The rest of the document (above and below the view) | background, in 25 ms time slices | no budget; nothing else waits for it |
| A link step, a search step, a fold (no re-render) | one frame | 10 ms |

The budget is about what is in the view, not about the document: a 5,000 line document and a 50 line one cost the same to show.

## How it is met

1. **Viewport first.** A scrolled pane begins its render at the top-level block that holds the top line (`_tui_md.paint_pane`), using the block records of an earlier render of the text. The part above is rendered afterwards (`_tui_md.prefix_slice`) and joined in front; the view stays on its source line.
2. **Prepared text.** Control bytes, tabs, HTML, reference definitions and the numbered lines are width independent: done once per text (`_tui_md.pd_put`, 4 kept).
3. **Memo.** Inline results of paragraphs, headings and cells are width independent (`_tui_md.inline_memo`).
4. **Caches.** The finished render per width, style and flags: memory (6) and, for files, `$TUI_HOME/cache/markdown`.
5. **Focus is an overlay.** The cached rows never hold the focused link; `_tui_md.compose` draws it, so a link step re-renders nothing.

## How it is measured

`tools/bench/run.sh` (fixed 400 line document, fixed 100 cell pane):

| Bench | Meaning | Now |
|---|---|---|
| `md_view_top` | width change, view at the top: time until the viewport is painted | 31 ms |
| `md_view_scrolled` | width change, scrolled to row 300 of 487 | 34 ms |
| `md_render_cold` | the whole document, nothing cached | 323 ms (background) |
| `md_link_step` | focus the next link | 5 ms |
| `md_disk_hit` | a new session, the file was seen before | 5 ms |

`tools/bench/run.sh --compare tools/bench/baseline.txt` fails when a `md_view_*` bench goes over 500 ms (G4), notes it over 100 ms, and applies the usual 5 % regression gate (G3) to every bench.

The README (393 lines, banner headings, badges) measured by hand: viewport painted in 53 to 80 ms at every position and width tried; its first cold show 160 ms.

Spans for a live run: `md_render`, `md_disk_load`, `md_slice`, `md_compose`. Counters: `md_cache_hit`, `md_cache_miss`, `md_disk_hit`.
