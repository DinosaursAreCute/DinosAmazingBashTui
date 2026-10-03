#!/usr/bin/env bash
# Brings the explorer's data up to date and opens it. No arguments.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$here/explore.py" || exit 1
for o in xdg-open open; do command -v "$o" >/dev/null && {
	"$o" "$here/explorer/index.html" >/dev/null 2>&1 &
	exit 0
}; done
