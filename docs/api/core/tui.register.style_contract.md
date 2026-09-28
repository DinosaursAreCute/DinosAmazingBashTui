### `tui.register.style_contract`

```bash
tui.register.style_contract NAME DESC...
```

Registers `NAME`'s style contract (registry kind `style`): the pseudo-states it can enter and the framework classes it draws with, e.g. `"states:hover focus"` `"classes:.list_sel"`.

**Notes**

- One contract table serves the CSS lint, the XSD generator and `tui.class`, instead of a state list hard-coded in each.
- Every existing widget type and chrome element's contract is registered by `lib/tui_registry.sh` itself.
