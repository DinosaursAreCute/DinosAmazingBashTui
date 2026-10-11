# Markdown editor

Type on the left, read on the right. Press **alt+m** to flip between the *rendered* view,
the *styled source* and the plain text.

## Inline

This is **bold**, this is *italic*, this is ***both***, and this is `inline code`.
Underscores work too: __bold__ and _italic_, but snake_case_names stay as they are.
A backslash escapes: \*not italic\*.

A [link to the docs](https://github.com/DinosaursAreCute/DinosAmazingBashTui) and
[another one](https://example.com/a_(b) "with a title").

Two spaces at the end of a line  
make a hard break.

## Quotes

> A quote that is long enough to wrap around the preview pane once the window is narrow.
>
> > A nested quote with **bold** text.

## Lists

- first item
- second item with a [link](https://example.com)
  - nested item
    - and deeper
- third item

1. one
2. two
   - a bullet inside a number
3. three

## Code

```bash
echo "fences keep **everything** literal"
for f in *.md; do wc -l "$f"; done
```

---

Not supported yet: tables, images, raw HTML, setext headings.
