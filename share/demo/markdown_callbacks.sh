#!/usr/bin/env bash
# markdown_callbacks.sh - Markdown page: a textarea in markdown mode with a live rendered preview.
# Only public tui.* calls.

_MD_SAMPLE='# Markdown editor

Edit this text: the pane on the right follows as you type.

## Inline

**bold**, *italic*, `code` and a [link](https://example.com).

## Lists

- first item
- second item
  - nested item

1. one
2. two

> A quote.

## Code

```bash
echo "hello"
```

| Key | Action |
|-----|--------|
| alt+z | undo |
| alt+y | redo |'

md_visit() {
	tui.set md_text "$_MD_SAMPLE"
	tui.text.set_cursor md_text 0
	tui.focus md_text
	md_changed
}

# re-renders the preview from the editor text; tui.md.show remembers it and re-fits on resize
md_changed() {
	local text
	tui.capture text tui.get md_text
	tui.md.show md_preview "$text"
}
