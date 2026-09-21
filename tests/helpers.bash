# tests/helpers.bash - shared setup for the bats tests (installer.bats, updater.bats, home.bats).
# RULES: everything is mocked or lives in $BATS_TEST_TMPDIR. HOME, XDG_* and every install / config / program location point into it,
# `curl` and `wget` are replaced by a mock that serves files from $REMOTE (nothing touches the network), and the source tree is only read.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"; export REPO

setup_env() {
    T="$BATS_TEST_TMPDIR"; export T
    export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_DATA_HOME="$T/home/.local/share"
    mkdir -p "$HOME"
    unset TUI_HOME DABT_HOME TUI_ROOT TUI_DEFAULTS_DIR TUI_APP_CONF TUI_PLUGINS_DIR TUI_SYNC_POLICY TUI_SYNC_STAMP TUI_SYNC_BACKUP \
          TUI_UPDATE_REPO TUI_UPDATE_BRANCH TUI_UPDATE_CHANNEL TUI_UPDATE_TAG TUI_UPDATE_VERSION_URL TUI_UPDATE_ARCHIVE_URL MOCK_CURL_FAIL
    export TUI_APP_NAME=dabt
    export TUI_UPDATE_NOSCAN=1                    # the security scan is slow (~2s per install/update) and has its own tests
    MOCKBIN="$T/mockbin"; REMOTE="$T/remote"; mkdir -p "$MOCKBIN" "$REMOTE"
    export PATH="$MOCKBIN:$PATH" REMOTE MOCKBIN
    : > "$T/curl.log"
    export CURL_LOG="$T/curl.log"
    marker="$T/.marker"; : > "$marker"; sleep 0.01
}

# a curl that answers from $REMOTE:  .../VERSION -> $REMOTE/VERSION,  *.tar.gz -> $REMOTE/release.tar.gz ; MOCK_CURL_FAIL=1 makes it fail
mock_network() {
    cat > "$MOCKBIN/curl" <<'MOCK'
#!/usr/bin/env bash
out=""; url=""
while (( $# )); do case "$1" in -o) out="$2"; shift ;; --max-time) shift ;; -*) ;; *) url="$1" ;; esac; shift; done
echo "$url" >> "$CURL_LOG"
[[ -n "${MOCK_CURL_FAIL:-}" ]] && exit 22
case "$url" in */releases/latest) src="$REMOTE/latest.json" ;; */VERSION) src="$REMOTE/VERSION" ;; *.tar.gz) src="$REMOTE/release.tar.gz" ;; *) exit 22 ;; esac
[[ -f "$src" ]] || exit 22
if [[ -n "$out" ]]; then cp "$src" "$out"; else cat "$src"; fi
MOCK
    chmod +x "$MOCKBIN/curl"
    printf '#!/bin/sh\nexit 1\n' > "$MOCKBIN/wget"; chmod +x "$MOCKBIN/wget"       # never used, but must not reach the real one
}

# make_release DIR VERSION : a small but valid DABT release (real sync/install libs, stub everything else). Every default file says
# "<name> v<VERSION>", so a new version changes them all unless a test rewrites one.
make_release() {
    local d="$1" v="$2" f
    mkdir -p "$d/lib" "$d/bin" "$d/share/defaults/pages" "$d/share/plugins" "$d/docs"
    printf '%s\n' "$v" > "$d/VERSION"
    printf '# stub\n' > "$d/lib/tui.sh"
    cp "$REPO/lib/tui_sync.sh" "$REPO/lib/tui_install.sh" "$d/lib/"
    printf '#!/usr/bin/env bash\necho dabt %s\n' "$v" > "$d/bin/dabt"; chmod +x "$d/bin/dabt"
    cp "$REPO/install.sh" "$d/install.sh"
    for f in keybinds.xml commands.xml theme.css pages/settings.xml; do printf '%s v%s\n' "$f" "$v" > "$d/share/defaults/$f"; done
    printf 'plugin p v%s\n' "$v" > "$d/share/plugins/p.plugin.sh"
    printf 'docs v%s\n' "$v" > "$d/docs/README.md"; printf 'readme v%s\n' "$v" > "$d/README.md"
}

# pack_release DIR : $REMOTE/release.tar.gz shaped like a GitHub archive (one top folder) + $REMOTE/VERSION
pack_release() {
    local d="$1" top="$T/pack/DinosAmazingBashTui-main"
    rm -rf "$T/pack"; mkdir -p "$T/pack"; cp -R "$d" "$top"
    tar -czf "$REMOTE/release.tar.gz" -C "$T/pack" DinosAmazingBashTui-main
    cp "$d/VERSION" "$REMOTE/VERSION"
    printf '{"tag_name": "v%s"}\n' "$(<"$d/VERSION")" > "$REMOTE/latest.json"
}

# the source tree must never be modified by a test
assert_repo_untouched() { [[ -z "$(find "$REPO" -newer "$marker" -type f -not -path '*/.git/*' -not -path '*/__pycache__/*' 2>/dev/null | head -1)" ]]; }

file_has() { grep -qF -- "$2" "$1"; }

# ── dapk (packaging) helpers ─────────────────────────────────────────────
# dapk_setup : isolated env + a throwaway Ed25519 key ($T/key, fingerprint in $FP); dabt is run from the source tree
dapk_setup() {
    setup_env
    export TUI_HOME="$T/home/.config/DABT" DABT="$REPO/bin/dabt" DAPK_SUDO="" SOURCE_DATE_EPOCH=1700000000 DABT_BUILD_NUMBER=7
    unset CI GITHUB_ACTIONS GITLAB_CI GITHUB_TOKEN GH_TOKEN DABT_SIGN_KEY NO_COLOR
    # a tag-triggered CI run sets these and would override the fixture's VERSION (1.2.3)
    unset GITHUB_REF GITHUB_REF_NAME GITHUB_REF_TYPE CI_COMMIT_TAG
    mkdir -p "$TUI_HOME"
    ssh-keygen -q -t ed25519 -N "" -f "$T/key" -C test </dev/null
    FP="$(ssh-keygen -lf "$T/key" | awk '{print $2}')"; export FP
}

# make_project DIR : a small app (entry app.sh, config/, assets/, LICENSE, CHANGELOG with News, VERSION 1.2.3) and a dabt.pkg
make_project() {
    local d="$1"
    mkdir -p "$d/config" "$d/assets"
    printf '#!/usr/bin/env bash\necho hi\n' > "$d/app.sh"; chmod +x "$d/app.sh"
    echo x > "$d/config/a.xml"; echo lic > "$d/LICENSE"; echo one > "$d/assets/one.txt"
    printf '# Changelog\n\n## [Unreleased]\n### News\n- Shiny new thing\n- Two line\n  bullet\n### Fixed\n- a bug\n\n## [1.2.2] - 2026-01-01\n### News\n- Old thing\n' > "$d/CHANGELOG.md"
    echo 1.2.3 > "$d/VERSION"
    cat > "$d/dabt.pkg" <<'T'
name = "demoapp"
entry = "app.sh"
include_paths = ["app.sh", "config"]

[[include]]
type = "file"
source = "LICENSE"
target = "docs/"

[[include]]
type = "directory"
source = "assets"
target = "share/assets"
recursive = true
T
}

# build_project DIR [build args] : runs dabt build signed with the test key; prints nothing, the package is $DIR/dist/demoapp-*.dapk
build_project() { local d="$1"; shift; ( cd "$d" && DABT_SIGN_KEY="$(<"$T/key")" bash "$DABT" build "$@" ); }
pkg_of() { ls "$1"/dist/*.dapk | head -1; }
