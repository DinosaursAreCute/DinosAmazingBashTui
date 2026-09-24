### `tui.confirm`

```bash
tui.confirm MESSAGE [ON_YES [ON_NO]] [flags]
```

Shows a Yes/No dialog and returns immediately; the callback runs after the user answers.

**Parameters**

- `ON_YES`, `ON_NO`: commands: a function name plus fixed arguments, split on spaces. Either may be empty.

**Options**

- `--danger`: red primary button, title `Warning`, and No selected by default.
- `--default yes|no`, `--title T`, `--width N`, `--yes LABEL`, `--no LABEL`.

**Notes**

- Keys: `y` yes, `n` or Esc no, arrows/Tab move, Enter picks. Mouse clicks work.
- The callback runs after the dialog is closed and the screen repainted, so it may open another dialog or change page. `TUI_DIALOG_RESULT` is `yes` or `no`.
- Commands can't chain with `;` or quote arguments, and must be shell functions. Pass values with spaces through a variable.
- Does nothing before the app runs.

**Example**

```bash
tui.confirm "Delete report.csv?" "rm_file report.csv" --danger --yes Delete --no Keep
```
