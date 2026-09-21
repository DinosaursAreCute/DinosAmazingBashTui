#!/usr/bin/env bash
# verify.sh - full verification of a .dapk: structure, signature and trust, then every checksum. Fails closed.
#
# dapk.verify.run PKG   extracts into a private temp dir and checks, in order:
#     1 structure (first member MANIFEST, safe members)   2 signature + trust (fingerprint == signer= header)   3 recomputed checksums
#   Options (set before): DAPK_VERIFY_TRUST_KEY=SHA256:...  trust this exact new signer without asking
#                         DAPK_VERIFY_ALLOW_UNSIGNED=1      accept a package without MANIFEST.sig (warns)
#                         DAPK_VERIFY_ASK=1                 (default) ask on a terminal before trusting a new signer
#   Results: DAPK_VERIFY_WORK (temp dir: caller removes it with dapk.verify.cleanup), DAPK_VERIFY_DIR (the extracted <root>),
#            DAPK_VERIFY_FPR, DAPK_VERIFY_SIGNED (0|1), DAPK_VERIFY_ERROR. DAPK_MANIFEST_H holds the parsed header afterwards.
# Nothing is trusted until all three steps pass; a known app whose signer changed is a hard failure.

declare -g DAPK_VERIFY_WORK="" DAPK_VERIFY_DIR="" DAPK_VERIFY_FPR="" DAPK_VERIFY_SIGNED=0 DAPK_VERIFY_ERROR=""
declare -g DAPK_VERIFY_TRUST_KEY="" DAPK_VERIFY_ALLOW_UNSIGNED=0 DAPK_VERIFY_ASK=1

dapk.verify.cleanup() { [[ -n "$DAPK_VERIFY_WORK" && -d "$DAPK_VERIFY_WORK" ]] && rm -rf "$DAPK_VERIFY_WORK"; DAPK_VERIFY_WORK=""; }

_dapk.verify.fail() { DAPK_VERIFY_ERROR="$*"; dapk.ui.err "$*"; return 1; }

dapk.verify.run() {
    local pkg="$1" dir name p
    DAPK_VERIFY_DIR="" DAPK_VERIFY_FPR="" DAPK_VERIFY_SIGNED=0 DAPK_VERIFY_ERROR=""
    dapk.verify.cleanup
    dapk.pack.check "$pkg" || { _dapk.verify.fail "$DAPK_PACK_ERROR"; return 1; }
    dapk.ui.ok "structure ($DAPK_PACK_COUNT entries)"
    DAPK_VERIFY_WORK="$(mktemp -d "${TMPDIR:-/tmp}/dapk_verify.XXXXXX")" || return 1
    dapk.pack.extract "$pkg" "$DAPK_VERIFY_WORK" || { _dapk.verify.fail "$DAPK_PACK_ERROR"; return 1; }
    dir="$DAPK_VERIFY_WORK/$DAPK_PACK_ROOT"
    dapk.manifest.read "$dir/MANIFEST" || { _dapk.verify.fail "$DAPK_MANIFEST_ERROR"; return 1; }
    name="${DAPK_MANIFEST_H[name]}"
    [[ "$name" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || { _dapk.verify.fail "invalid app name in manifest: $name"; return 1; }

    if [[ -f "$dir/MANIFEST.sig" ]]; then
        dapk.sign.inspect "$dir/MANIFEST.sig" "$dir/MANIFEST" || { _dapk.verify.fail "$DAPK_SIGN_ERROR"; return 1; }
        DAPK_VERIFY_FPR="$DAPK_SIGN_FPR" DAPK_VERIFY_SIGNED=1
        [[ "${DAPK_MANIFEST_H[signer]:-}" == "$DAPK_SIGN_FPR" ]] || { _dapk.verify.fail "signer mismatch: manifest says '${DAPK_MANIFEST_H[signer]:-none}', signature is from $DAPK_SIGN_FPR"; return 1; }
        if dapk.sign.trusted "$name"; then
            dapk.sign.verify "$dir/MANIFEST.sig" "$dir/MANIFEST" "$name" \
                || { _dapk.verify.fail "the signature is valid but not from the trusted key for '$name' (signer changed: $DAPK_SIGN_FPR); remove its line from $(dapk.sign.trust_file) only if you trust the new key"; return 1; }
            dapk.ui.ok "signature (trusted signer $DAPK_SIGN_FPR)"
        elif [[ -n "$DAPK_VERIFY_TRUST_KEY" ]]; then
            [[ "$DAPK_VERIFY_TRUST_KEY" == "$DAPK_SIGN_FPR" ]] || { _dapk.verify.fail "--trust-key $DAPK_VERIFY_TRUST_KEY does not match the package signer $DAPK_SIGN_FPR"; return 1; }
            dapk.sign.trust_add "$name" "$DAPK_SIGN_TYPE" "$DAPK_SIGN_B64"; dapk.ui.ok "signature (new signer $DAPK_SIGN_FPR trusted via --trust-key)"
        elif (( DAPK_VERIFY_ASK )) && [[ -t 0 ]]; then
            dapk.ui.warn "first install of '$name': signed by $DAPK_SIGN_FPR (not yet trusted)"
            dapk.ui.confirm "Trust this signer for '$name'?" n || { _dapk.verify.fail "signer not trusted"; return 1; }
            dapk.sign.trust_add "$name" "$DAPK_SIGN_TYPE" "$DAPK_SIGN_B64"; dapk.ui.ok "signature (signer $DAPK_SIGN_FPR trusted)"
        else _dapk.verify.fail "unknown signer $DAPK_SIGN_FPR for '$name': verify the fingerprint, then rerun with --trust-key $DAPK_SIGN_FPR"; return 1; fi
    elif (( DAPK_VERIFY_ALLOW_UNSIGNED )); then dapk.ui.warn "the package is not signed (--allow-unsigned)"
    else _dapk.verify.fail "the package is not signed (--allow-unsigned accepts it)"; return 1; fi

    DAPK_MANIFEST_PROGRESS=1 dapk.manifest.scan "$dir" || { _dapk.verify.fail "$DAPK_MANIFEST_ERROR"; return 1; }
    local -a computed=("${DAPK_MANIFEST_ENTRIES[@]}")
    dapk.manifest.read "$dir/MANIFEST" || return 1
    DAPK_MANIFEST_COMPUTED=("${computed[@]}")
    if ! dapk.manifest.compare; then
        for p in "${DAPK_MANIFEST_PROBLEMS[@]}"; do dapk.ui.err "$p"; done
        DAPK_VERIFY_ERROR="checksum verification failed"; return 1
    fi
    DAPK_VERIFY_DIR="$dir"
    return 0
}
