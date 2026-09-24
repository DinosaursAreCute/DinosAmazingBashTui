### `tui.cmd.load`

```bash
tui.cmd.load FILE
```

Registers the commands in an XML file, one `<cmd id="…" title="…" action="…" [group="…"] [desc="…"] [when="…"] [key="…"]/>` per line.

**Returns:** `1` when `FILE` can't be read.

**Notes**

- Lines missing `id`, `title` or `action` are skipped. `share/defaults/commands.xml` is an example.
