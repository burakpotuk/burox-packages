#!/usr/bin/env bash
set -euo pipefail
# Offline self-tests for the pipeline's safety checks (runs in CI on every push):
#   1. manifest: sign + verify round trip, 1-byte tamper is rejected, garbage
#      signature is rejected, unknown signing key is refused, backup key works
#   2. fetch-source: wrong pinned SHA-256 is rejected, right one extracts
#   3. verify-relocatable (macOS only): a binary linked to a non-system dylib
#      is rejected, a system-only binary passes
# Uses throwaway keys; never touches keys/ or the real signing key.

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
require_cmd jq python3
OPENSSL="$(find_openssl3)" || die "OpenSSL 3 is required (macOS: brew install openssl@3)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0
ok()   { PASS=$((PASS + 1)); printf 'PASS  %s\n' "$*"; }
bad()  { printf 'FAIL  %s\n' "$*" >&2; exit 1; }
expect_fail() { local what="$1"; shift; if "$@" >"$TMP/out.log" 2>&1; then cat "$TMP/out.log" >&2; bad "$what (should have failed)"; else ok "$what"; fi; }
expect_ok()   { local what="$1"; shift; if "$@" >"$TMP/out.log" 2>&1; then ok "$what"; else cat "$TMP/out.log" >&2; bad "$what"; fi; }

S="$ROOT_DIR/scripts"

# --- 1. manifest signing ------------------------------------------------------------
mkdir -p "$TMP/keys" "$TMP/other" "$TMP/pkgs"
for k in primary backup; do
  "$OPENSSL" genpkey -algorithm ED25519 -out "$TMP/$k.key.pem" 2>/dev/null
  "$OPENSSL" pkey -in "$TMP/$k.key.pem" -pubout -out "$TMP/keys/manifest-public-$k.pem"
done
"$OPENSSL" genpkey -algorithm ED25519 -out "$TMP/stranger.key.pem" 2>/dev/null

printf 'fake archive\n' >"$TMP/pkgs/demo-1.0.0-darwin-arm64.tar.xz"
jq -n --arg sha "$(sha256_file "$TMP/pkgs/demo-1.0.0-darwin-arm64.tar.xz")" \
      --argjson size "$(file_size "$TMP/pkgs/demo-1.0.0-darwin-arm64.tar.xz")" \
  '{name: "demo", channel: "stable", version: "1.0.0", arch: "arm64",
    file: "demo-1.0.0-darwin-arm64.tar.xz", sha256: $sha, size: $size,
    minMacOS: "14.0", meta: {}}' >"$TMP/pkgs/demo-1.0.0-darwin-arm64.package.json"

M="$TMP/manifest.json"
expect_ok "make-manifest (local mode)" python3 "$S/make-manifest.py" --local-dir "$TMP/pkgs" \
  --base-url https://example.invalid/ --out "$M"
jq -e '.schemaVersion == 1 and (.packages | length == 1) and .packages[0].url == "https://example.invalid/demo-1.0.0-darwin-arm64.tar.xz"' "$M" >/dev/null \
  || bad "manifest content"
ok "manifest content"

export MANIFEST_PUBLIC_KEYS_DIR="$TMP/keys"
expect_ok "sign with primary key" env MANIFEST_SIGNING_KEY="$(cat "$TMP/primary.key.pem")" "$S/sign-manifest.sh" "$M"
expect_ok "verify signed manifest" "$S/verify-manifest.sh" "$M"

cp "$M" "$TMP/tampered.json"
python3 - "$TMP/tampered.json" <<'PY'
import sys
p = sys.argv[1]
b = bytearray(open(p, "rb").read())
b[len(b) // 2] ^= 0x01          # flip one bit in one byte
open(p, "wb").write(bytes(b))
PY
cp "$M.sig" "$TMP/tampered.json.sig"
expect_fail "1-byte tampered manifest is rejected" "$S/verify-manifest.sh" "$TMP/tampered.json"

printf 'bm90IGEgc2lnbmF0dXJl\n' >"$TMP/garbage.sig"
expect_fail "garbage signature is rejected" "$S/verify-manifest.sh" "$M" "$TMP/garbage.sig"

expect_fail "unknown signing key is refused" env MANIFEST_SIGNING_KEY="$(cat "$TMP/stranger.key.pem")" \
  "$S/sign-manifest.sh" "$M" "$TMP/stranger.sig"
"$OPENSSL" pkeyutl -sign -rawin -inkey "$TMP/stranger.key.pem" -in "$M" -out "$TMP/stranger.bin"
"$OPENSSL" base64 -A -in "$TMP/stranger.bin" >"$TMP/stranger.sig"
expect_fail "signature by an unknown key is rejected" "$S/verify-manifest.sh" "$M" "$TMP/stranger.sig"

expect_ok "sign with backup key" env MANIFEST_SIGNING_KEY_FILE="$TMP/backup.key.pem" "$S/sign-manifest.sh" "$M"
expect_ok "backup-key signature verifies" "$S/verify-manifest.sh" "$M"
unset MANIFEST_PUBLIC_KEYS_DIR

# --- 2. fetch-source pinning ---------------------------------------------------------
mkdir -p "$TMP/src/demo-1.0" "$TMP/build"
echo "hello" >"$TMP/src/demo-1.0/README"
tar -C "$TMP/src" -czf "$TMP/demo-1.0.tar.gz" demo-1.0
GOOD="$(sha256_file "$TMP/demo-1.0.tar.gz")"
WRONG="$(printf 'x' | sha256_stdin)"
for v in good wrong; do
  sha="$GOOD"; [[ "$v" == "wrong" ]] && sha="$WRONG"
  jq -n --arg url "file://$TMP/demo-{version}.tar.gz" --arg sha "$sha" \
    '{name: "demo", url: $url, versions: {"1.0": $sha}}' >"$TMP/sources-$v.json"
done
expect_fail "wrong pinned SHA-256 is rejected" env BUILD_ROOT="$TMP/build" \
  "$S/fetch-source.sh" "$TMP/sources-wrong.json" 1.0 "$TMP/x-wrong"
expect_ok "correct pinned SHA-256 is accepted" env BUILD_ROOT="$TMP/build" \
  "$S/fetch-source.sh" "$TMP/sources-good.json" 1.0 "$TMP/x-good"
[[ "$(cat "$TMP/x-good/README")" == "hello" ]] || bad "extraction"
ok "extraction strips the top-level directory"
expect_fail "unpinned version is refused" env BUILD_ROOT="$TMP/build" \
  "$S/fetch-source.sh" "$TMP/sources-good.json" 2.0 "$TMP/x-none"

# --- 3. verify-relocatable (macOS only) -------------------------------------------------
if [[ "$(uname -s)" == "Darwin" ]]; then
  mkdir -p "$TMP/reloc/good/bin" "$TMP/reloc/bad/bin" "$TMP/reloc/lib"
  printf 'int helper(void) { return 7; }\n' >"$TMP/reloc/helper.c"
  printf 'int helper(void);\nint main(void) { return helper() == 7 ? 0 : 1; }\n' >"$TMP/reloc/main.c"
  printf 'int main(void) { return 0; }\n' >"$TMP/reloc/plain.c"
  clang -mmacosx-version-min=14.0 -dynamiclib -o "$TMP/reloc/lib/libhelper.dylib" "$TMP/reloc/helper.c"
  clang -mmacosx-version-min=14.0 -o "$TMP/reloc/bad/bin/app" "$TMP/reloc/main.c" -L"$TMP/reloc/lib" -lhelper
  clang -mmacosx-version-min=14.0 -o "$TMP/reloc/good/bin/app" "$TMP/reloc/plain.c"
  clang -mmacosx-version-min=15.0 -o "$TMP/reloc/newer" "$TMP/reloc/plain.c"
  mkdir -p "$TMP/reloc/toonew/bin" && mv "$TMP/reloc/newer" "$TMP/reloc/toonew/bin/app"
  expect_fail "binary linked to a non-system dylib is rejected" "$S/verify-relocatable.sh" "$TMP/reloc/bad"
  expect_fail "binary requiring macOS 15 is rejected" "$S/verify-relocatable.sh" "$TMP/reloc/toonew"
  expect_ok "system-only binary passes" "$S/verify-relocatable.sh" "$TMP/reloc/good"
else
  echo "SKIP  verify-relocatable tests (not macOS)"
fi

echo "selftest: $PASS checks passed"
