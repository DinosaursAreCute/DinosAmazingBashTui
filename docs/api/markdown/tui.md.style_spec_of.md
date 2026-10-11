### `tui.md.style_spec_of`

```bash
tui.md.style_spec_of CLASS VAR
```

Stores in `VAR` the spec of the current style of `CLASS`.

**Parameters**

- `CLASS`: a style class, as for [`tui.md.style_spec`](/api/markdown/tui.md.style_spec.html).
- `VAR`: the name of the variable that receives the spec.

**Notes**

- The spec has the form `FG[/BG][:MOD,MOD...]`, as for [`tui.md.style_spec`](/api/markdown/tui.md.style_spec.html).
- The spec is the one `CLASS` was set with. A class that was never set has its spec read back from its default SGR sequence, for example `default:bold`.

**Example**

```bash
tui.md.style_spec_of h1 spec    # spec="cyan:bold,underline" after the h1 example
```
