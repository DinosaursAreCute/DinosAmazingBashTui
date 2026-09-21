#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load ../helpers
setup() { dapk_setup; P="$T/proj"; make_project "$P"; }

@test "build: produces the .dapk, sidecars and prints the artifact path on stdout" {
    run --separate-stderr build_project "$P"
    [ "$status" -eq 0 ]
    [ "$output" = "$P/dist/demoapp-1.2.3-7.dapk" ]
    for f in demoapp-1.2.3-7.dapk demoapp-1.2.3-7.dapk.sha256 demoapp-news.txt RELEASE_NOTES.md build.log; do [ -f "$P/dist/$f" ]; done
    [ "$(tar -tzf "$output" | head -1)" = "demoapp-1.2.3-7/MANIFEST" ]
}

@test "build: byte-identical for identical input (reproducible)" {
    build_project "$P" >/dev/null 2>&1; cp "$(pkg_of "$P")" "$T/first.dapk"; rm -rf "$P/dist"
    build_project "$P" >/dev/null 2>&1
    cmp "$T/first.dapk" "$(pkg_of "$P")"
}

@test "build: MANIFEST lists every top-level entry with checksums and the descriptor" {
    build_project "$P" >/dev/null 2>&1
    m="$(tar -xzOf "$(pkg_of "$P")" demoapp-1.2.3-7/MANIFEST)"
    [[ "$m" == "# DABT-MANIFEST 1"* ]]
    for k in name=demoapp version=1.2.3 build=7 entry=app.sh "signer=$FP"; do grep -qxF "$k" <<< "$m"; done
    for e in .dabt.metadata CHANGELOG.md NEWS app.sh config docs share; do grep -qE "^[fd] [0-9a-f]{64} .* $e\$" <<< "$m"; done
    grep -qE '^d [0-9a-f]{64} - - config$' <<< "$m"
    grep -qE '^f [0-9a-f]{64} [0-9]+ 755 app.sh$' <<< "$m"
}

@test "build: changelog Unreleased is closed in the package (not in the working tree); News extracted" {
    build_project "$P" >/dev/null 2>&1
    tar -xzOf "$(pkg_of "$P")" demoapp-1.2.3-7/CHANGELOG.md > "$T/cl.md"
    grep -qx '## \[Unreleased\]' "$T/cl.md"; grep -qx '## \[1.2.3\] - 2023-11-14' "$T/cl.md"
    grep -qx '## \[Unreleased\]' "$P/CHANGELOG.md"; ! grep -q '1.2.3' "$P/CHANGELOG.md"
    grep -q $'^1.2.3\tShiny new thing$' "$P/dist/demoapp-news.txt"
    grep -q $'^1.2.3\tTwo line bullet$' "$P/dist/demoapp-news.txt"
    grep -q $'^1.2.2\tOld thing$' "$P/dist/demoapp-news.txt"
}

@test "build: --suffix gives 1.2.3-dev-7 and a suffixed changelog header" {
    build_project "$P" --suffix dev >/dev/null 2>&1
    [ -f "$P/dist/demoapp-1.2.3-dev-7.dapk" ]
    tar -xzOf "$P/dist/demoapp-1.2.3-dev-7.dapk" demoapp-1.2.3-dev-7/CHANGELOG.md | grep -qx '## \[1.2.3-dev-7\] - 2023-11-14'
    tar -xzOf "$P/dist/demoapp-1.2.3-dev-7.dapk" demoapp-1.2.3-dev-7/.dabt.metadata | grep -qE 'version *= 1.2.3-dev$'
}

@test "build: a CI tag overrides VERSION, and the run number is the build number" {
    ( cd "$P" && GITHUB_REF_TYPE=tag GITHUB_REF_NAME=v2.0.0-rc.1 GITHUB_RUN_NUMBER=42 DABT_BUILD_NUMBER= DABT_SIGN_KEY="$(<"$T/key")" bash "$DABT" build ) >/dev/null 2>&1
    [ -f "$P/dist/demoapp-2.0.0-rc.1-42.dapk" ]
}

@test "build: without a key it fails; --no-sign builds an unsigned package that install refuses" {
    run bash -c "cd '$P' && bash '$DABT' build"; [ "$status" -eq 1 ]; [[ "$output" == *"no signing key"* ]]
    run bash -c "cd '$P' && bash '$DABT' build --no-sign"; [ "$status" -eq 0 ]
    run bash "$DABT" app install "$(pkg_of "$P")" --no-scan; [ "$status" -eq 1 ]; [[ "$output" == *"not signed"* ]]
    run bash "$DABT" app install "$(pkg_of "$P")" --no-scan --allow-unsigned; [ "$status" -eq 0 ]
}

@test "build: the working tree and the project are not modified" {
    ( cd "$P" && find . -path ./dist -prune -o -type f -print0 | sort -z | xargs -0 sha256sum ) > "$T/before"
    build_project "$P" >/dev/null 2>&1
    ( cd "$P" && find . -path ./dist -prune -o -type f -print0 | sort -z | xargs -0 sha256sum ) > "$T/after"
    cmp "$T/before" "$T/after"
}

@test "build --plan: prints the resolved source -> target list and writes nothing" {
    run --separate-stderr bash -c "cd '$P' && bash '$DABT' build --plan"
    [ "$status" -eq 0 ]; [[ "$output" == *"LICENSE -> docs/LICENSE"* ]]; [[ "$output" == *"assets -> share/assets"* ]]
    [ ! -e "$P/dist" ]
}

@test "build: CLI -f/-d entries are appended after the file entries" {
    echo extra > "$P/extra.txt"; mkdir -p "$P/more/sub"; echo m > "$P/more/sub/m.txt"; echo t > "$P/more/t.txt"
    run --separate-stderr bash -c "cd '$P' && bash '$DABT' build --plan -f -s extra.txt -t bin/extra.txt -d -s more -t share/more"
    [[ "$output" == *"extra.txt -> bin/extra.txt (1 files)"* ]]; [[ "$output" == *"more -> share/more (1 files)"* ]]   # non-recursive: top-level files only
    run --separate-stderr bash -c "cd '$P' && bash '$DABT' build --plan -d -s more -t share/more -r"
    [[ "$output" == *"more -> share/more (2 files)"* ]]
}

@test "include rules: escape, collision, missing source, symlink, empty directory" {
    cd "$P"
    printf '[[include]]\ntype="file"\nsource="../outside"\ntarget="x"\n' >> dabt.pkg; echo o > "$T/outside"
    run bash "$DABT" build --plan; [ "$status" -eq 1 ]; [[ "$output" == *"outside the project"* ]]
    run bash "$DABT" build --plan --allow-external; [ "$status" -eq 0 ]
    make_project "$P"
    printf '[[include]]\ntype="file"\nsource="LICENSE"\ntarget="docs/LICENSE"\n' >> dabt.pkg
    run bash "$DABT" build --plan; [ "$status" -eq 1 ]; [[ "$output" == *"produced twice"* ]]
    make_project "$P"; printf '[[include]]\ntype="file"\nsource="nope"\ntarget="x"\n' >> dabt.pkg
    run bash "$DABT" build --plan; [ "$status" -eq 1 ]; [[ "$output" == *"does not exist"* ]]
    make_project "$P"; printf '[[include]]\ntype="file"\nsource="nope"\ntarget="x"\noptional=true\n' >> dabt.pkg
    run bash "$DABT" build --plan; [ "$status" -eq 0 ]
    make_project "$P"; ln -s app.sh link.sh; printf '[[include]]\ntype="file"\nsource="link.sh"\ntarget="x.sh"\n' >> dabt.pkg
    run bash "$DABT" build --plan; [ "$status" -eq 1 ]; [[ "$output" == *"symlink"* ]]
    make_project "$P"; mkdir emptydir; printf '[[include]]\ntype="directory"\nsource="emptydir"\ntarget="share/empty"\n' >> dabt.pkg
    run bash -c "bash '$DABT' build --no-sign 2>&1"; [ "$status" -eq 0 ]; [[ "$output" == *"matched no files"* ]]
    tar -tzf "$(pkg_of "$P")" | grep -qx 'demoapp-1.2.3-7/share/empty/'
    run bash "$DABT" build --no-sign --strict; [ "$status" -eq 1 ]                      # --strict: the warning fails the build
}

@test "pkg include/dep add/list/rm edit dabt.pkg" {
    cd "$P"
    run bash "$DABT" pkg include add -f -s app.sh -t bin/app.sh; [ "$status" -eq 0 ]
    run bash "$DABT" pkg include list; [[ "$output" == *"3  file"*"app.sh -> bin/app.sh"* ]]
    run bash "$DABT" pkg include rm 3; run bash "$DABT" pkg include list; [[ "$output" != *"bin/app.sh"* ]]
    run bash "$DABT" pkg dep add -n rg --apt ripgrep --pacman ripgrep --optional; [ "$status" -eq 0 ]
    run bash "$DABT" pkg dep list; [[ "$output" == *"1  rg  (optional)"* ]]
    run bash "$DABT" pkg dep rm 1; run bash "$DABT" pkg dep list; [ -z "$output" ]
}

@test "release notes: template variables, sections, conditionals; unknown variable is an error" {
    build_project "$P" >/dev/null 2>&1
    grep -q '^# demoapp 1.2.3' "$P/dist/RELEASE_NOTES.md"; grep -q '^- Shiny new thing' "$P/dist/RELEASE_NOTES.md"; grep -q '^- a bug' "$P/dist/RELEASE_NOTES.md"
    grep -qE '^[0-9a-f]{64}  app.sh$' "$P/dist/RELEASE_NOTES.md"; ! grep -q 'Full changelog' "$P/dist/RELEASE_NOTES.md"
    mkdir -p "$P/.dabt"; printf '{{name}} {{oops}}\n' > "$P/.dabt/release.tpl"
    run bash -c "cd '$P' && DABT_SIGN_KEY=\"\$(<'$T/key')\" bash '$DABT' build"; [ "$status" -eq 1 ]; [[ "$output" == *"unknown variable 'oops'"* ]]
    printf '{{#if section:Fixed}}FIXED {{section:Fixed}}{{/if}}\n{{#if nothing}}\n' > "$P/.dabt/release.tpl"
    run bash -c "cd '$P' && DABT_SIGN_KEY=\"\$(<'$T/key')\" bash '$DABT' build"; [ "$status" -eq 1 ]
}

@test "release: bumps VERSION, closes Unreleased on disk, commits and tags" {
    cd "$P"; git init -q; git config user.email t@t; git config user.name t; git add -A; git commit -qm init
    run bash "$DABT" pkg release minor; [ "$status" -eq 0 ]
    [ "$(<VERSION)" = 1.3.0 ]; grep -qx '## \[1.3.0\] - .*' CHANGELOG.md; grep -qx '## \[Unreleased\]' CHANGELOG.md
    git tag | grep -qx v1.3.0; [ -z "$(git status --porcelain)" ]
    run bash "$DABT" pkg release patch; [ "$status" -eq 1 ]; [[ "$output" == *"Unreleased section"*"empty"* ]]
}

@test "version: show and bump" {
    cd "$P"; run bash "$DABT" pkg version; [ "$output" = "1.2.3-7" ]
    run bash "$DABT" pkg version bump major; [ "$(<VERSION)" = 2.0.0 ]
}

@test "ci init copies the template and refuses to overwrite without --force" {
    cd "$P"; run bash "$DABT" pkg ci init github; [ "$status" -eq 0 ]; [ -f .github/workflows/dabt-release.yml ]
    run bash "$DABT" pkg ci init github; [ "$status" -eq 1 ]
    run bash "$DABT" pkg ci init github --force; [ "$status" -eq 0 ]
    run bash "$DABT" pkg ci init gitlab; [ -f .gitlab-ci.yml ]
}

@test "signing: the default key is picked up automatically; --auto-sign creates it once (mode 600) and reuses it" {
    unset DABT_SIGN_KEY
    run bash -c "cd '$P' && bash '$DABT' build"; [ "$status" -eq 1 ]; [[ "$output" == *"--auto-sign"* ]]
    [ ! -e "$TUI_HOME/keys/dabt_ed25519" ]
    run bash -c "cd '$P' && bash '$DABT' build --auto-sign"; [ "$status" -eq 0 ]
    [ "$(stat -c %a "$TUI_HOME/keys/dabt_ed25519")" = 600 ]
    fp1="$(ssh-keygen -lf "$TUI_HOME/keys/dabt_ed25519" | awk '{print $2}')"
    tar -xzOf "$P/dist/demoapp-1.2.3-7.dapk" demoapp-1.2.3-7/MANIFEST | grep -qx "signer=$fp1"
    rm -rf "$P/dist"; run bash -c "cd '$P' && bash '$DABT' build"; [ "$status" -eq 0 ]          # no flag needed once the key exists
    [ "$(ssh-keygen -lf "$TUI_HOME/keys/dabt_ed25519" | awk '{print $2}')" = "$fp1" ]           # not regenerated
    run bash "$DABT" app install "$(pkg_of "$P")" --no-scan --no-deps --trust-key "$fp1"; [ "$status" -eq 0 ]
}

@test "signing: --key and DABT_SIGN_KEY win over the default key; dabt pkg key prints the fingerprint" {
    bash "$DABT" pkg key --generate >/dev/null 2>&1
    run bash "$DABT" pkg key; [ "$status" -eq 0 ]; [[ "$output" == *"fingerprint  SHA256:"* ]]; [[ "$output" == *"--trust-key SHA256:"* ]]
    run bash "$DABT" pkg key --generate; [ "$status" -eq 1 ]                                    # never overwrites an existing key
    build_project "$P" >/dev/null 2>&1                                                            # DABT_SIGN_KEY (the test key) beats the default
    tar -xzOf "$(pkg_of "$P")" demoapp-1.2.3-7/MANIFEST | grep -qx "signer=$FP"
}

# ── build numbers ────────────────────────────────────────────────────────
NOCI="-u GITHUB_RUN_NUMBER -u CI_PIPELINE_IID -u BUILDKITE_BUILD_NUMBER -u CIRCLE_BUILD_NUM -u BUILD_NUMBER -u BUILD_BUILDID"   # a CI runner sets these itself
bn() { ( cd "$P" && env $NOCI DABT_BUILD_NUMBER= "$@" bash "$DABT" pkg version ) 2>&1; }

@test "build number: the CI run counter is used and only grows; re-running the same run gives the same number" {
    [ "$(bn GITHUB_RUN_NUMBER=42)" = "1.2.3-42" ]; [ "$(bn GITHUB_RUN_NUMBER=43)" = "1.2.3-43" ]; [ "$(bn GITHUB_RUN_NUMBER=42)" = "1.2.3-42" ]
    [ "$(bn GITHUB_RUN_NUMBER=100)" = "1.2.3-100" ]                                    # numeric, not lexical: 100 > 43
    [ "$(bn CI_PIPELINE_IID=9)" = "1.2.3-9" ]; [ "$(bn BUILD_NUMBER=15)" = "1.2.3-15" ]; [ "$(bn CIRCLE_BUILD_NUM=3)" = "1.2.3-3" ]
    [ "$(bn BUILDKITE_BUILD_NUMBER=8)" = "1.2.3-8" ]; [ "$(bn BUILD_BUILDID=77)" = "1.2.3-77" ]
}

@test "build number: build_offset continues numbering after a CI move; DABT_BUILD_NUMBER is used exactly as given" {
    printf 'build_offset = 100\n' | cat - "$P/dabt.pkg" > "$T/pkg" && mv "$T/pkg" "$P/dabt.pkg"
    [ "$(bn GITHUB_RUN_NUMBER=42)" = "1.2.3-142" ]
    [ "$(cd "$P" && DABT_BUILD_NUMBER=5 bash "$DABT" pkg version)" = "1.2.3-5" ]
    sed -i 's/^build_offset.*/build_offset = -1/' "$P/dabt.pkg"; run bash -c "cd '$P' && bash '$DABT' pkg version"; [ "$status" -ne 0 ]
}

@test "build number: the build output names the counter it used" {
    run bash -c "cd '$P' && GITHUB_RUN_NUMBER=42 DABT_BUILD_NUMBER= DABT_SIGN_KEY=\"\$(<'$T/key')\" bash '$DABT' build 2>&1"
    [ "$status" -eq 0 ]; [[ "$output" == *"build      42  (GITHUB_RUN_NUMBER)"* ]]; [ -f "$P/dist/demoapp-1.2.3-42.dapk" ]
}

@test "build number: without a CI counter the git commit count is used; a shallow clone warns" {
    cd "$P"; git init -q; git config user.email t@t; git config user.name t; git add -A; git commit -qm one; echo a >> LICENSE; git commit -qam two; echo b >> LICENSE; git commit -qam three
    [ "$(bn)" = "1.2.3-3" ]
    git clone -q --depth 1 "file://$P" "$T/shallow"; cp "$P/dabt.pkg" "$T/shallow/" 2>/dev/null
    run bash -c "cd '$T/shallow' && env $NOCI DABT_BUILD_NUMBER= bash '$DABT' pkg version 2>&1"; [[ "$output" == *"shallow git clone"* ]]; [[ "$output" == *"1.2.3-1"* ]]
    run bash -c "cd '$T/shallow' && env $NOCI DABT_BUILD_NUMBER= DABT_SIGN_KEY=\"\$(<'$T/key')\" bash '$DABT' build 2>&1"; [[ "$output" == *"shallow git clone"* ]]
}

@test "release: writes and commits the version header; the notes use the header images, the logo and the summary" {
    cd "$P"; mkdir -p assets; printf 'png\n' > assets/logo.png
    printf 'release_title = "Demo App"\nrelease_logo = "assets/logo.png"\npublish_repo = "me/demoapp"\n' | cat - dabt.pkg > "$T/pkg" && mv "$T/pkg" dabt.pkg
    printf '# Changelog\n\n## [Unreleased]\n\nA summary line.\n\n### News\n\n- Something new.\n\n### Fixed\n\n* A bug.\n' > CHANGELOG.md
    git init -q; git config user.email t@t; git config user.name t; git add -A; git commit -qm init
    run bash "$DABT" pkg release minor; [ "$status" -eq 0 ]
    [ -f assets/headers/v1-3-0.svg ]; grep -q '<rect' assets/headers/v1-3-0.svg; git ls-files --error-unmatch assets/headers/v1-3-0.svg
    [ -z "$(git status --porcelain)" ]
    run env GITHUB_REF_TYPE=tag GITHUB_REF_NAME=v1.3.0 bash "$DABT" pkg notes; [ "$status" -eq 0 ]
    [[ "$output" == *'<img src="https://raw.githubusercontent.com/me/demoapp/v1.3.0/assets/logo.png"'* ]]
    [[ "$output" == *'<h1><img src="https://raw.githubusercontent.com/me/demoapp/v1.3.0/assets/headers/v1-3-0.svg" alt="Demo App 1.3.0"'* ]]
    [[ "$output" == *"A summary line."* ]]
    [[ "$output" == *'headers/release-new.svg" alt="What'* ]]; [[ "$output" == *'headers/release-fixed.svg" alt="Fixed"'* ]]
    [[ "$output" != *"release-added.svg"* ]]                        # no ### Added: no header
}

@test "release notes: without a version header file the heading falls back to plain markdown" {
    cd "$P"; run bash "$DABT" pkg notes; [ "$status" -eq 0 ]; [[ "$output" == "# demoapp 1.2.3"* ]]
}
