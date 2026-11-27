#!/usr/bin/env bash
set -euo pipefail
# Verify manifest.json against its Ed25519 signature, the same way the app does.
#
#   verify-manifest.sh <manifest.json> [<signature>]
#
# <signature> defaults to <manifest.json>.sig (base64 of the 64-byte signature).
# Accepted keys: keys/manifest-public-*.pem (override the directory with
# MANIFEST_PUBLIC_KEYS_DIR). Exit 0 only if one of them verifies the exact
# bytes of the manifest and the manifest has the expected top-level shape.

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

MANIFEST="${1:?usage: verify-manifest.sh <manifest.json> [<signature>]}"
SIG="${2:-$MANIFEST.sig}"
KEYS_DIR="${MANIFEST_PUBLIC_KEYS_DIR:-$ROOT_DIR/keys}"
[[ -f "$MANIFEST" ]] || die "not found: $MANIFEST"
[[ -f "$SIG" ]] || die "signature not found: $SIG"
OPENSSL="$(find_openssl3)" || die "OpenSSL 3 is required (macOS: brew install openssl@3)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

tr -d ' \r\n\t' <"$SIG" | "$OPENSSL" base64 -d -A -out "$TMP/sig.bin" 2>/dev/null || true
if [[ ! -s "$TMP/sig.bin" || "$(file_size "$TMP/sig.bin")" != "64" ]]; then
  die "INVALID: signature is not base64 of 64 bytes"
fi

KEYS=0
for pub in "$KEYS_DIR"/manifest-public-*.pem; do
  [[ -f "$pub" ]] || continue
  KEYS=$((KEYS + 1))
  if "$OPENSSL" pkeyutl -verify -pubin -inkey "$pub" -rawin \
       -in "$MANIFEST" -sigfile "$TMP/sig.bin" >/dev/null 2>&1; then
    if command -v jq >/dev/null 2>&1; then
      jq -e '.schemaVersion == 1 and (.packages | type == "array")' "$MANIFEST" >/dev/null \
        || die "INVALID: signature ok but manifest structure is unexpected"
    fi
    log "OK: $(basename "$MANIFEST") is signed by $(basename "$pub")"
    exit 0
  fi
done
[[ "$KEYS" -gt 0 ]] || die "no public keys found in $KEYS_DIR (manifest-public-*.pem)"
die "INVALID: signature does not match any of $KEYS public key(s)"
