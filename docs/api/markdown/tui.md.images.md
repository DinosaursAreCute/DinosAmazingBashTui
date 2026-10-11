### `tui.md.images`

```bash
tui.md.images placeholder|alt|hidden|graphics
```

Chooses what `![alt](src)` draws in a rendered document.

**Parameters**

- `placeholder|alt|hidden|graphics`: `placeholder` draws `[img: alt]`, `alt` draws only the alt text, `hidden` draws nothing, `graphics` draws the picture itself where the terminal allows it and falls back to the placeholder where it does not.

**Returns:** `1` for another name.

**Notes**

- `graphics` needs a terminal where [`tui.md.image_protocol`](/api/markdown/tui.md.image_protocol.html) says `kitty` (kitty, Ghostty) and a paragraph that holds **only images**, linked or not; several share a row like badges and wrap like words. Each picture is sent once, by file path, as a virtual placement, and drawn as rows of Unicode placeholder cells, so it scrolls, clips and folds like text. Images inside a sentence or a heading stay placeholders.
- Formats: PNG is used as it is. SVG (`rsvg-convert`) and GIF, JPEG, WebP and others (ImageMagick `magick` or `convert`, else `ffmpeg`: the first frame) are converted once into a PNG under `~/.cache/DABT/md-images`. Without such a tool they are placeholders.
- Remote images (`http://`, `https://`) are fetched only with `TUI_MD_IMAGE_FETCH=1` (config `md.fetch`, Settings > Markdown): `curl` or `wget` downloads in the background, 15 s and 8 MB at most, and the pane re-renders when a file arrived.
- Size: about 9 x 18 pixels per cell, at most `TUI_MD_IMAGE_MAX_COLS` x `TUI_MD_IMAGE_MAX_ROWS` (60 x 20) and never wider than the pane. Relative paths resolve against the document's folder (`TUI_MD_BASE_DIR`; [`tui.md.show_file`](/api/markdown/tui.md.show_file.html) sets it).
- The size comes from the PNG header.
- Persisted as `md.images` in the config.

**Example**

```bash
tui.md.images alt
```
