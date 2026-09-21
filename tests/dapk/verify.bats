#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load ../helpers
setup() {
    dapk_setup; P="$T/proj"; make_project "$P"; build_project "$P" >/dev/null 2>&1; PKG="$(pkg_of "$P")"; ROOT="demoapp-1.2.3-7"
}
# repack DIR OUT : tar DIR/$ROOT with MANIFEST first (a tampered copy of the package)
repack() { ( cd "$1" && { echo "$ROOT/MANIFEST"; echo "$ROOT/MANIFEST.sig"; find "$ROOT" ! -name MANIFEST ! -name MANIFEST.sig; } | tar --no-recursion -czf "$2" -T - ); }
unpack() { rm -rf "$T/x"; mkdir "$T/x"; tar -xzf "$PKG" -C "$T/x"; }

@test "verify: a good package passes with --trust-key, then without it (signer is pinned)" {
    run bash "$DABT" pkg verify "$PKG" --trust-key "$FP"; [ "$status" -eq 0 ]; [[ "$output" == *"verified: demoapp 1.2.3-7"* ]]
    grep -q '^demoapp namespaces="dabt-pkg" ssh-ed25519 ' "$TUI_HOME/trusted_signers"
    run bash "$DABT" pkg verify "$PKG"; [ "$status" -eq 0 ]; [[ "$output" == *"trusted signer"* ]]
}

@test "verify: an unknown signer is refused without --trust-key (no terminal), and a wrong fingerprint is refused" {
    run bash "$DABT" pkg verify "$PKG"; [ "$status" -eq 1 ]; [[ "$output" == *"unknown signer $FP"* ]]
    run bash "$DABT" pkg verify "$PKG" --trust-key SHA256:nope; [ "$status" -eq 1 ]; [[ "$output" == *"does not match the package signer"* ]]
    [ ! -s "$TUI_HOME/trusted_signers" ]
}

@test "verify: a modified file is detected by its checksum" {
    bash "$DABT" pkg verify "$PKG" --trust-key "$FP" >/dev/null 2>&1
    unpack; echo evil >> "$T/x/$ROOT/app.sh"; repack "$T/x" "$T/bad.dapk"
    run bash "$DABT" pkg verify "$T/bad.dapk"; [ "$status" -eq 1 ]; [[ "$output" == *"checksum mismatch: app.sh"* ]]
}

@test "verify: a deep change inside a directory changes the top-level directory hash" {
    bash "$DABT" pkg verify "$PKG" --trust-key "$FP" >/dev/null 2>&1
    unpack; echo evil >> "$T/x/$ROOT/share/assets/one.txt"; repack "$T/x" "$T/bad.dapk"
    run bash "$DABT" pkg verify "$T/bad.dapk"; [ "$status" -eq 1 ]; [[ "$output" == *"checksum mismatch: share"* ]]
}

@test "verify: an added or removed member is detected" {
    bash "$DABT" pkg verify "$PKG" --trust-key "$FP" >/dev/null 2>&1
    unpack; echo x > "$T/x/$ROOT/extra.txt"; repack "$T/x" "$T/bad.dapk"
    run bash "$DABT" pkg verify "$T/bad.dapk"; [ "$status" -eq 1 ]; [[ "$output" == *"not listed in the manifest: extra.txt"* ]]
    unpack; rm "$T/x/$ROOT/app.sh"; repack "$T/x" "$T/bad2.dapk"
    run bash "$DABT" pkg verify "$T/bad2.dapk"; [ "$status" -eq 1 ]; [[ "$output" == *"missing from the package: app.sh"* ]]
}

@test "verify: an edited MANIFEST invalidates the signature" {
    bash "$DABT" pkg verify "$PKG" --trust-key "$FP" >/dev/null 2>&1
    unpack; sed -i 's/^build=7/build=8/' "$T/x/$ROOT/MANIFEST"; repack "$T/x" "$T/bad.dapk"
    run bash "$DABT" pkg verify "$T/bad.dapk"; [ "$status" -eq 1 ]; [[ "$output" == *"signature is invalid"* ]]
}

@test "verify: a valid signature from a different key than the trusted one fails hard (signer changed)" {
    bash "$DABT" pkg verify "$PKG" --trust-key "$FP" >/dev/null 2>&1
    ssh-keygen -q -t ed25519 -N "" -f "$T/key2" -C other </dev/null
    rm -rf "$P/dist"; ( cd "$P" && DABT_SIGN_KEY="$(<"$T/key2")" bash "$DABT" build ) >/dev/null 2>&1
    run bash "$DABT" pkg verify "$(pkg_of "$P")"; [ "$status" -eq 1 ]; [[ "$output" == *"not from the trusted key"* ]]
}

@test "verify: the signer= header must equal the signature's key" {
    unpack; sed -i "s/^signer=.*/signer=SHA256:forged/" "$T/x/$ROOT/MANIFEST"; repack "$T/x" "$T/bad.dapk"
    run bash "$DABT" pkg verify "$T/bad.dapk" --trust-key "$FP"; [ "$status" -eq 1 ]
}

@test "verify: plain tarballs, links and paths outside the root are rejected" {
    mkdir -p "$T/plain/d"; echo a > "$T/plain/d/f"; tar -czf "$T/plain.dapk" -C "$T/plain" d
    run bash "$DABT" pkg verify "$T/plain.dapk"; [ "$status" -eq 1 ]; [[ "$output" == *"first member must be"* ]]
    unpack; ln -s /etc/passwd "$T/x/$ROOT/link"; repack "$T/x" "$T/link.dapk"
    run bash "$DABT" pkg verify "$T/link.dapk"; [ "$status" -eq 1 ]; [[ "$output" == *"not a regular file or directory"* ]]
    unpack; ( cd "$T/x" && { echo "$ROOT/MANIFEST"; echo "$ROOT/../evil"; } | tar --no-recursion --transform 's,^x/,,' -czf "$T/esc.dapk" -T - 2>/dev/null ) || true
    mkdir -p "$T/esc/$ROOT"; cp "$T/x/$ROOT/MANIFEST" "$T/esc/$ROOT/"; echo e > "$T/esc/evil"
    ( cd "$T/esc" && tar -czf "$T/esc2.dapk" "$ROOT/MANIFEST" "$ROOT/../evil" --absolute-names 2>/dev/null )
    run bash "$DABT" pkg verify "$T/esc2.dapk"; [ "$status" -eq 1 ]
}

@test "info: prints the descriptor and News without extracting or verifying" {
    run bash "$DABT" pkg info "$PKG"; [ "$status" -eq 0 ]
    [[ "$output" == *"name           demoapp"* ]]; [[ "$output" == *"signer         $FP"* ]]; [[ "$output" == *"Shiny new thing"* ]]; [[ "$output" == *"not verified"* ]]
}

@test "news: from a package, a sidecar file, a changelog, with --since" {
    run bash "$DABT" pkg news "$PKG"; [[ "$output" == *"1.2.3"*"Shiny new thing"*"1.2.2"*"Old thing"* ]]
    run bash "$DABT" pkg news "$P/dist/demoapp-news.txt" --since 1.2.2; [[ "$output" == *"Shiny new thing"* ]]; [[ "$output" != *"Old thing"* ]]
    run bash "$DABT" pkg news "$P/CHANGELOG.md"; [[ "$output" == *"Two line bullet"* ]]
}
