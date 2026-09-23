#!/usr/bin/env bash
# ci_integration.sh PKG.dapk [BASELINE_DIR] - installs and updates DABT from a built package inside a throwaway HOME (nothing outside it is touched).
#   1. fresh install: the package's own install.sh; `dabt --version` must equal the package version
#   2. update: install BASELINE_DIR (default: the package); its VERSION is forced to 0.0.0, then `dabt update` from the package (offline: file:// URLs)
#   3. the updated tree must be identical to a fresh install of the package
set -euo pipefail
pkg="$(readlink -f "${1:?usage: ci_integration.sh PKG.dapk [BASELINE_DIR]}")"
base="${2:-}"
work="$(mktemp -d "${TMPDIR:-/tmp}/dabt_it.XXXXXX")"
trap 'rm -rf "$work"' EXIT
step() { printf '\n== %s\n' "$*"; }
fail() {
	echo "FAIL: $*" >&2
	exit 1
}
# an isolated environment: own HOME, own PATH entry, no inherited DABT settings
env_for() { # NAME -> exports HOME etc. for that install
	export HOME="$work/$1/home" XDG_CONFIG_HOME="$work/$1/home/.config" XDG_DATA_HOME="$work/$1/home/.local/share"
	export PATH="$HOME/.local/bin:$ORIG_PATH"
	mkdir -p "$HOME"
	unset TUI_HOME TUI_ROOT DABT_HOME TUI_UPDATE_REPO TUI_UPDATE_BRANCH TUI_UPDATE_CHANNEL TUI_UPDATE_TAG TUI_UPDATE_VERSION_URL TUI_UPDATE_ARCHIVE_URL
}
ORIG_PATH="$PATH"

mkdir -p "$work/pkg"
tar -xzf "$pkg" -C "$work/pkg" --strip-components=1
[[ -f "$work/pkg/install.sh" && -f "$work/pkg/VERSION" ]] || fail "$pkg does not contain install.sh and VERSION"
read -r want <"$work/pkg/VERSION"
want="${want//[[:space:]]/}"

step "1/3 fresh install from ${pkg##*/}"
env_for fresh
bash "$work/pkg/install.sh" --yes --no-scan
got="$(dabt --version)"
[[ "$got" == "DABT $want" ]] || fail "dabt --version says '$got', expected 'DABT $want'"
dabt -d >/dev/null || fail "dabt --details failed"
dabt --help >/dev/null || fail "dabt --help failed"
echo "ok: $got"
fresh_root="$(dirname "$(readlink -f "$(command -v dabt)")")/.."

step "2/3 update to ${pkg##*/}"
if [[ -z "$base" ]]; then base="$work/pkg"; fi
# always force the baseline older than the package, else a same-version previous release makes `dabt update` a no-op
cp -r "$base" "$work/baseline"
echo 0.0.0 >"$work/baseline/VERSION"
base="$work/baseline"
env_for upd
bash "$base/install.sh" --yes --no-scan
before="$(dabt --version)"
echo "installed: $before"
export TUI_UPDATE_CHANNEL=dev TUI_UPDATE_NOSCAN=1 TUI_UPDATE_VERSION_URL="file://$work/pkg/VERSION" TUI_UPDATE_ARCHIVE_URL="file://$pkg"
# an older dabt (baseline) is overwritten while it runs, so bash may choke on the rest of its own file (fixed in bin/dabt since; only
# the OLD copy is affected): the outcome is judged by the message and the resulting version, not by that copy's exit code
out="$(dabt update --yes --policy override 2>&1)" || echo "note: the baseline dabt exited non-zero after updating itself"
printf '%s\n' "$out"
grep -q "^updated to $want" <<<"$out" || fail "dabt update did not report 'updated to $want'"
after="$(dabt --version)"
[[ "$after" == "DABT $want" ]] || fail "after the update dabt says '$after', expected 'DABT $want'"
echo "ok: $before -> $after"

step "3/3 updated tree equals a fresh install"
upd_root="$(dirname "$(readlink -f "$(command -v dabt)")")/.."
# files only the OLD release had (e.g. docs/ from a repo checkout) may stay behind; everything the package ships must match
{ diff -rq -x dabt.env -x install.meta -x backups -x '*.new' "$fresh_root" "$upd_root" || true; } | grep -v "^Only in $upd_root" >"$work/diff.txt" || true
[[ ! -s "$work/diff.txt" ]] || {
	head -30 "$work/diff.txt"
	fail "updated program differs from a fresh install"
}
echo "ok: identical"
