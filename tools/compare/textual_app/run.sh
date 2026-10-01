#!/usr/bin/env bash
# run.sh - launches the Textual side of the comparison. Uses COMPARE_VENV (default ~/.cache/dabt-compare-venv).
HERE="$(cd "$(dirname "$0")" && pwd)"
VENV="${COMPARE_VENV:-$HOME/.cache/dabt-compare-venv}"
[[ -x "$VENV/bin/python" ]] || {
	echo "no venv at $VENV: python3 -m venv \"$VENV\" && \"$VENV/bin/pip\" install -r \"$HERE/requirements.txt\"" >&2
	exit 1
}
exec "$VENV/bin/python" "$HERE/app.py"
