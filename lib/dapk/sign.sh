#!/usr/bin/env bash
# sign.sh - Ed25519 signatures with ssh-keygen -Y (namespace dabt-pkg) and the trust store.
#
# The signature covers MANIFEST only; the manifest pins every top-level checksum, so it covers the whole package. MANIFEST.sig travels
# inside the package. Trust store: $TUI_HOME/trusted_signers (ssh allowed_signers format, one principal per app name).
#
# dapk.sign.resolve_key [KEY] [CFGKEY] [AUTO]   sets DAPK_SIGN_KEYFILE. Priority: KEY (--key) > a private temp file written from $DABT_SIGN_KEY >
#                                        CFGKEY (sign_key in dabt.pkg) > the default key $TUI_HOME/keys/dabt_ed25519 when it exists;
#                                        AUTO=1 (--auto-sign) generates the default key when none of those exist
# dapk.sign.default_key                  path of the default key       dapk.sign.generate [PATH]   create a passphrase-less Ed25519 key (mode 600)
# dapk.sign.cleanup                      remove the temp key
# dapk.sign.fingerprint KEYFILE          prints SHA256:...
# dapk.sign.sign MANIFEST KEYFILE        writes MANIFEST.sig next to MANIFEST
# dapk.sign.inspect SIG MANIFEST         validates the signature cryptographically (any key) -> DAPK_SIGN_FPR, DAPK_SIGN_TYPE, DAPK_SIGN_B64
# dapk.sign.trust_file / trusted NAME / trust_add NAME TYPE B64 / verify SIG MANIFEST NAME
# The key never appears in logs; a passphrase-protected key is asked for by ssh-keygen itself.

declare -g DAPK_SIGN_KEYFILE="" DAPK_SIGN_FPR="" DAPK_SIGN_TYPE="" DAPK_SIGN_B64="" DAPK_SIGN_ERROR="" _DAPK_SIGN_TMP=""

dapk.sign.trust_file() { printf '%s' "${DAPK_TRUST_FILE:-$TUI_HOME/trusted_signers}"; }

dapk.sign.default_key() { printf '%s' "${DAPK_DEFAULT_KEY:-$TUI_HOME/keys/dabt_ed25519}"; }

dapk.sign.generate() {
    local k="${1:-$(dapk.sign.default_key)}"
    command -v ssh-keygen >/dev/null 2>&1 || { DAPK_SIGN_ERROR="ssh-keygen (OpenSSH) is required"; return 1; }
    [[ ! -e "$k" ]] || { DAPK_SIGN_ERROR="$k already exists"; return 1; }
    mkdir -p "$(dirname "$k")" && chmod 700 "$(dirname "$k")" 2>/dev/null
    ssh-keygen -q -t ed25519 -N "" -C "dabt-pkg" -f "$k" </dev/null >/dev/null 2>&1 && chmod 600 "$k" || { DAPK_SIGN_ERROR="key generation failed"; return 1; }
    DAPK_SIGN_KEYFILE="$k"
}

dapk.sign.resolve_key() {
    DAPK_SIGN_ERROR=""
    command -v ssh-keygen >/dev/null 2>&1 || { DAPK_SIGN_ERROR="ssh-keygen (OpenSSH) is required for signing"; return 1; }
    if [[ -n "${1:-}" ]]; then
        [[ -r "$1" ]] || { DAPK_SIGN_ERROR="signing key not readable: $1"; return 1; }
        DAPK_SIGN_KEYFILE="$1"; return 0
    fi
    if [[ -z "${DABT_SIGN_KEY:-}" && -n "${2:-}" ]]; then
        [[ -r "$2" ]] || { DAPK_SIGN_ERROR="signing key not readable: $2 (sign_key in dabt.pkg)"; return 1; }
        DAPK_SIGN_KEYFILE="$2"; return 0
    fi
    if [[ -n "${DABT_SIGN_KEY:-}" ]]; then
        _DAPK_SIGN_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dapk_key.XXXXXX")" || return 1
        chmod 700 "$_DAPK_SIGN_TMP"; ( umask 077; printf '%s\n' "$DABT_SIGN_KEY" > "$_DAPK_SIGN_TMP/key" ); chmod 600 "$_DAPK_SIGN_TMP/key"
        DAPK_SIGN_KEYFILE="$_DAPK_SIGN_TMP/key"; return 0
    fi
    if [[ -r "$(dapk.sign.default_key)" ]]; then DAPK_SIGN_KEYFILE="$(dapk.sign.default_key)"; return 0; fi
    if [[ "${3:-0}" == 1 ]]; then dapk.sign.generate && return 0; return 1; fi
    DAPK_SIGN_ERROR="no signing key: set sign_key in dabt.pkg, pass --key FILE, export DABT_SIGN_KEY, or build with --auto-sign (or --no-sign)"; return 1
}

dapk.sign.cleanup() { [[ -n "$_DAPK_SIGN_TMP" && -d "$_DAPK_SIGN_TMP" ]] && rm -rf "$_DAPK_SIGN_TMP"; _DAPK_SIGN_TMP=""; }

dapk.sign.fingerprint() { ssh-keygen -lf "$1" 2>/dev/null | awk '{print $2; exit}'; }

dapk.sign.sign() {
    local manifest="$1" key="$2"
    rm -f "$manifest.sig"
    ssh-keygen -Y sign -q -f "$key" -n "$DAPK_SIG_NAMESPACE" "$manifest" >/dev/null 2>"${manifest}.signerr" || { DAPK_SIGN_ERROR="ssh-keygen failed: $(<"${manifest}.signerr")"; rm -f "${manifest}.signerr"; return 1; }
    rm -f "${manifest}.signerr"
    [[ -s "$manifest.sig" ]]
}

# the public key embedded in an SSHSIG armor: "TYPE BASE64" (magic 6 + version 4, then a length-prefixed public key blob)
_dapk.sign.pubkey() {
    local sig="$1" tmp b len t tl
    tmp="$(mktemp "${TMPDIR:-/tmp}/dapk_sig.XXXXXX")" || return 1
    sed '1d;$d' "$sig" | tr -d '\n\r' | base64 -d > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
    read -r b1 b2 b3 b4 < <(od -An -tu1 -j10 -N4 "$tmp")
    len=$(( (b1 << 24) | (b2 << 16) | (b3 << 8) | b4 ))
    (( len > 0 && len < 4096 )) || { rm -f "$tmp"; return 1; }
    read -r b1 b2 b3 b4 < <(od -An -tu1 -j14 -N4 "$tmp")
    tl=$(( (b1 << 24) | (b2 << 16) | (b3 << 8) | b4 ))
    t="$(dd if="$tmp" bs=1 skip=18 count="$tl" 2>/dev/null)"
    DAPK_SIGN_TYPE="$t"
    DAPK_SIGN_B64="$(dd if="$tmp" bs=1 skip=14 count="$len" 2>/dev/null | base64 | tr -d '\n')"
    rm -f "$tmp"; [[ "$t" == ssh-* && -n "$DAPK_SIGN_B64" ]]
}

dapk.sign.inspect() {
    local sig="$1" manifest="$2" out
    DAPK_SIGN_FPR="" DAPK_SIGN_TYPE="" DAPK_SIGN_B64="" DAPK_SIGN_ERROR=""
    command -v ssh-keygen >/dev/null 2>&1 || { DAPK_SIGN_ERROR="ssh-keygen (OpenSSH) is required to verify signatures"; return 1; }
    out="$(ssh-keygen -Y check-novalidate -n "$DAPK_SIG_NAMESPACE" -s "$sig" < "$manifest" 2>&1)" || { DAPK_SIGN_ERROR="the signature is invalid (${out##*$'\n'})"; return 1; }
    [[ "$out" =~ (SHA256:[A-Za-z0-9+/=]+) ]] && DAPK_SIGN_FPR="${BASH_REMATCH[1]}"
    [[ -n "$DAPK_SIGN_FPR" ]] || { DAPK_SIGN_ERROR="cannot read the signer from the signature"; return 1; }
    _dapk.sign.pubkey "$sig" || { DAPK_SIGN_ERROR="cannot read the public key from the signature"; return 1; }
    return 0
}

dapk.sign.trusted() { local f; f="$(dapk.sign.trust_file)"; [[ -r "$f" ]] && grep -q "^$1[[:space:]]" "$f"; }

dapk.sign.trust_add() {
    local f; f="$(dapk.sign.trust_file)"; mkdir -p "$(dirname "$f")" || return 1
    printf '%s namespaces="%s" %s %s\n' "$1" "$DAPK_SIG_NAMESPACE" "$2" "$3" >> "$f"
}

dapk.sign.verify() {   # SIG MANIFEST NAME
    ssh-keygen -Y verify -f "$(dapk.sign.trust_file)" -I "$3" -n "$DAPK_SIG_NAMESPACE" -s "$1" < "$2" >/dev/null 2>&1
}
