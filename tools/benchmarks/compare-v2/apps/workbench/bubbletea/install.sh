#!/usr/bin/env bash
# install.sh - installs what the Bubble Tea workbench needs: the Go toolchain check, the module dependencies, and the binary.
# Go itself is not installed here (system package manager territory); the script says what to run when it is missing.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
NEED_GO=1.24

if ! command -v go >/dev/null; then
	echo "Go is not installed (need >= $NEED_GO). Install it, then re-run:" >&2
	echo "  Arch:   sudo pacman -S go        Debian/Ubuntu: sudo apt install golang-go (or https://go.dev/dl/)" >&2
	echo "  Fedora: sudo dnf install golang  macOS: brew install go" >&2
	exit 1
fi
have="$(go env GOVERSION)"
have="${have#go}"
if [[ "$(printf '%s\n%s\n' "$NEED_GO" "$have" | sort -V | head -n1)" != "$NEED_GO" ]]; then
	echo "Go $have is too old (need >= $NEED_GO); newer toolchains are fetched automatically only by Go >= 1.21 (GOTOOLCHAIN=auto)." >&2
fi

cd "$HERE"
echo "downloading modules ..."
go mod download
echo "building wb-bubbletea ..."
go build -o wb-bubbletea .
echo "ok: $HERE/wb-bubbletea"
