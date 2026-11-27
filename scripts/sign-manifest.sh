#!/usr/bin/env bash
set -euo pipefail
set +x  # never trace: the private key passes through this script
# Sign manifest.json with Ed25519.
#
#   sign-manifest.sh <manifest.json> [<signature-out>]
#
# Private key (PEM, PKCS#8 Ed25519), one of:
#   MANIFEST_SIGNING_KEY        the PEM text (GitHub Secret in CI)
#   MANIFEST_SIGNING_KEY_FILE   path to the PEM file (local use)
# The key must belong to one of the public keys in keys/manifest-public-*.pem
# (override the directory with MANIFEST_PUBLIC_KEYS_DIR), otherwise we refuse
# to sign: a manifest the app cannot verify is useless.
#
# Output: <manifest.json>.sig (default) containing the 64-byte raw Ed25519
# signature over the exact manifest bytes, base64-encoded on one line.
# The private key is only ever passed to openssl through a pipe; it is never
# written to disk, printed or logged.

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

MANIFEST="${1:?usage: sign-manifest.sh <manifest.json> [<signature-out>]}"
SIG_OUT="${2:-$MANIFEST.sig}"
KEYS_DIR="${MANIFEST_PUBLIC_KEYS_DIR:-$ROOT_DIR/keys}"
[[ -f "$MANIFEST" ]] || die "not found: $MANIFEST"
OPENSSL="$(find_openssl3)" || die "OpenSSL 3 is required (macOS: brew install openssl@3)"

if [[ -n "${MANIFEST_SIGNING_KEY_FILE:-}" ]]; then
  [[ -f "$MANIFEST_SIGNING_KEY_FILE" ]] || die "MANIFEST_SIGNING_KEY_FILE not found"
  key_stream() { cat "$MANIFEST_SIGNING_KEY_FILE"; }
elif [[ -n "${MANIFEST_SIGNING_KEY:-}" ]]; then
  key_stream() { printf '%s\n' "$MANIFEST_SIGNING_KEY"; }
else
  die "MANIFEST_SIGNING_KEY is not set. Add the private key as a GitHub Actions secret named MANIFEST_SIGNING_KEY (see README: 'İmza anahtarları')."
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Public half of the secret key, normalised to PEM.
if ! "$OPENSSL" pkey -in <(key_stream) -pubout -out "$TMP/signer.pub.pem" 2>/dev/null; then
  die "MANIFEST_SIGNING_KEY is not a valid PEM private key"
fi
"$OPENSSL" pkey -pubin -in "$TMP/signer.pub.pem" -noout -text 2>/dev/null | grep -q '^ED25519 Public-Key' \
  || die "MANIFEST_SIGNING_KEY is not an Ed25519 key"

MATCH=""
for pub in "$KEYS_DIR"/manifest-public-*.pem; do
  [[ -f "$pub" ]] || continue
  if cmp -s <("$OPENSSL" pkey -pubin -in "$pub" -pubout 2>/dev/null) "$TMP/signer.pub.pem"; then
    MATCH="$(basename "$pub")"
    break
  fi
done
[[ -n "$MATCH" ]] || die "the signing key does not match any keys/manifest-public-*.pem; commit its public key first"

"$OPENSSL" pkeyutl -sign -rawin -inkey <(key_stream) -in "$MANIFEST" -out "$TMP/sig.bin" \
  || die "signing failed"
[[ "$(file_size "$TMP/sig.bin")" == "64" ]] || die "unexpected Ed25519 signature length"
"$OPENSSL" base64 -A -in "$TMP/sig.bin" >"$SIG_OUT"
printf '\n' >>"$SIG_OUT"
log "signed $(basename "$MANIFEST") with the key matching $MATCH -> $SIG_OUT"
