# Markdown: rendering, settings, themes and documents in panes

DABT renders Markdown into styled, wrapped rows: a document can be shown in a pane ([`tui.md.show`](../api/markdown/tui.md.show.md), or the `<markdown>` tag), edited with a styled source view ([`tui.md.style`](../api/markdown/tui.md.style.md)), or read as plain text ([`tui.md.strip`](../api/markdown/tui.md.strip.md)). API tables: [../api/markdown.md](../api/markdown.md).

## What the renderer draws

| Supported | Not supported |
|---|---|
| ATX and setext headings; headings with block-letter fonts | Math |
| Paragraphs, hard and soft breaks, block quotes, nested lists | Footnotes |
| Task lists (`- [ ]`, `- [x]`) | Raw HTML beyond the subset |
| Fenced and indented code, with highlighting for `bash`, `sh`, `shell`, `zsh` and `json` | Pictures other than local PNGs on kitty/Ghostty |
| `**bold**`, `*italic*`, `~~strike~~`, `` `code` ``, `<autolinks>` | |
| Inline, reference (`[t][ref]`) and `<a>` links | |
| Pipe tables | |
| HTML subset: `<br>`, `<img>`, `<a>`, `<b>`, `<i>`, `<code>`, `<s>`, `<hr>`, `<h1>` to `<h6>`, comments (other tags are dropped, their text kept) | |

Wide characters (CJK, emoji) take two cells under a UTF-8 locale. A render also reports the rows of links and headings (`TUI_MD_LINK_ROWS`, `TUI_MD_HEADS`, `TUI_MD_ANCHORS`), which the reading keys below use.

## Settings > Markdown

The Settings page writes these keys (see [../api/config.md](../api/config.md)):

- **Profile** (`md.profile`): `dabt` for DABT's own look, or `theme` to take the active theme's Markdown classes.
- **Fonts per level** (`md.font.1` to `md.font.6`): `style` (plain styled text), or a block font such as `block5`, `blk3`, `seg3`, `box3` or `half2`.
- **Tables** (`md.tables`): `grid`, `rounded`, `plain` or `stacked`. Overflowing cells wrap or truncate (`md.table_overflow`).
- **Images** (`md.images`): `placeholder`, `alt`, `hidden` or `graphics`.
- **Styles** (`md.style.CLASS`): a spec `FG[/BG][:MODS]`, for example `white/#102030:bold`. The `page` class sets the document background.

## Themes

With profile `theme`, every `.md_CLASS` rule of the active theme sets that class (`fg`, `bg` and `mods`). A class the theme does not define keeps DABT's look, and a style set in Settings goes on top:

```css
.md_h1 { fg: cyan; mods: bold underline; }
.md_link { fg: blue; mods: underline; }
.md_page { bg: #1e1e2e; }
```

The classes are `h1` to `h6`, `strong`, `em`, `code`, `codeblock`, `quote`, `bullet`, `link`, `hr`, `marker`, `strike`, `hl_keyword`, `hl_string`, `hl_comment`, `hl_number`, `hl_var`, `page`, `table` (the outline of tables) and `table_head` (the header row). The base look is `Theme default` in the profile setting; `dabt` restores DABT's table.

## Reading documents in a pane

A Markdown pane reads with the keyboard and the mouse; nothing has to be bound by the app. The keys act on the keyboard pane, else the pane under the pointer, else the only Markdown pane of the page. `f2` shows the list with the keys as bound right now.

| Key | Action |
|---|---|
| left click on a link | follow it ([`tui.md.click`](../api/markdown/tui.md.click.md)) |
| `alt+j` / `alt+k` | next / previous link |
| `alt+l` | follow the focused link ([`tui.md.link_open`](../api/markdown/tui.md.link_open.md)) |
| `alt+b`, `alt+left`, mouse side button 2 | back to the previous document or position ([`tui.md.back`](../api/markdown/tui.md.back.md)) |
| `alt+right`, mouse side button 1 | forward again ([`tui.md.forward`](../api/markdown/tui.md.forward.md)) |
| `alt+s` | search ([`tui.md.search_prompt`](../api/markdown/tui.md.search_prompt.md)) |
| `alt+g` / `alt+h` | next / previous match |
| `alt+o` | outline: jump to a heading ([`tui.md.outline_choose`](../api/markdown/tui.md.outline_choose.md)) |
| `alt+z` | fold or unfold the section at the top ([`tui.md.fold_toggle`](../api/markdown/tui.md.fold_toggle.md)) |
| `alt+y` / `alt+u` | copy the section / the document ([`tui.md.copy`](../api/markdown/tui.md.copy.md)) |

**Reader mode.** `<markdown pane="docs" src="x.md" keys="reader"/>` or `tui.md.keys docs reader` adds plain keys, in the style of a pager, that act while the pane has the keyboard (click it or press `f6`): `n` / `N` next / previous link, `Enter` follow, `b` or `Backspace` back, `/` search, `]` / `[` next / previous match, `o` outline, `z` fold, `y` / `Y` copy section / document, `g` / `G` top / bottom, and `j` / `k` scroll as in any pane. A focused text box keeps its keys. `none` turns the keys off for a pane. The demo's Docs and Case Study pages use reader mode.

Links to `#anchor` scroll to that heading; a relative `.md` link loads that file in the pane ([`tui.md.on_navigate`](../api/markdown/tui.md.on_navigate.md) is called); other links are copied to the clipboard. A pane filled with [`tui.md.show`](../api/markdown/tui.md.show.md) needs the `FILE` argument for relative links to resolve. Set a custom handler for the first case with [`tui.md.on_link`](../api/markdown/tui.md.on_link.md).

## Images

`![alt](src)` draws `[img: alt]`, only the alt text, or nothing, as set by `md.images` (`placeholder`, `alt`, `hidden`). With `graphics` it draws the picture itself where it can:

- **Terminal:** kitty or Ghostty ([`tui.md.image_protocol`](../api/markdown/tui.md.image_protocol.md) says `kitty`). iTerm2 and WezTerm speak another protocol that is not drawn yet; inside tmux nothing is drawn.
- **Images:** a paragraph made only of images, `![alt](file)` or `[![alt](file)](link)`; several share a row (badges) and wrap like words. A linked image registers its link. An image inside a sentence or a heading stays a placeholder.
- **Formats:** PNG as it is; SVG with `rsvg-convert`, and GIF, JPEG, WebP ... with ImageMagick (else `ffmpeg`) converted once to a PNG in `~/.cache/DABT/md-images`. Without the tool: placeholder.
- **Remote images** (the README badges) are fetched only when you turn on *Fetch remote images* (`md.fetch`): `curl` or `wget` in the background, shown when they arrive.
- **How:** DABT sends the file path to the terminal once (kitty reads the file itself, so no base64 of the image and no chunking), creates a *virtual placement* of the right size in cells, and fills the rows with Unicode placeholder cells (`U+10EEEE` plus row and column diacritics, the image id in the foreground color). To everything else the picture is ordinary text, so wrapping, scrolling, clipping, folding, search and the row cache need no placement layer.
- **Size:** about 9 x 18 pixels per cell, at most 60 x 20 cells (`TUI_MD_IMAGE_MAX_COLS`, `TUI_MD_IMAGE_MAX_ROWS`) and never wider than the pane; the aspect ratio is kept. The size comes from the PNG header.
- **Lifetime:** images are deleted from the terminal when the document changes and when the app exits.

Set it in Settings > Markdown > Images, or `tui.md.images graphics` (config `md.images=graphics`).
