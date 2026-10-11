### `tui.md.config_apply`

```bash
tui.md.config_apply
```

Loads the persisted Markdown settings from the app config: `md.fonts` (0/1), `md.breaks` (0/1), `md.link_url` (`inline` or `hidden`), `md.font.N` (a font name or `style`, `N` = 1..6) and `md.style.CLASS` (a style spec).

**Notes**

- Called by [`tui.config.apply`](/api/config/tui.config.apply.html). The Settings > Markdown page writes these keys.
- A style key is applied with [`tui.md.style_spec`](/api/markdown/tui.md.style_spec.html), so an invalid value is ignored.

**Example**

```bash
tui.config.apply    # also loads the md.* keys
```
