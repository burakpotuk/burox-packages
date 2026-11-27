#!/usr/bin/env bash
set -euo pipefail
set +x
# Generate the two Ed25519 manifest signing key pairs (primary + backup).
# Run this ONCE, on your own Mac:
#
#   scripts/generate-signing-keys.sh [<private-key-dir>]
#
# - Private keys go to <private-key-dir> (default: ~/burox-manifest-keys),
#   OUTSIDE the repository, mode 0600. They are never printed.
# - Public keys are copied into keys/manifest-public-{primary,backup}.pem in this
#   repository (commit them) and printed as raw base64 for embedding in the app.

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

OUT="${1:-$HOME/burox-manifest-keys}"
OPENSSL="$(find_openssl3)" || die "OpenSSL 3 gerekli. Kurmak için: brew install openssl@3"

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
case "$OUT/" in
  "$ROOT_DIR"/*) die "özel anahtarlar repo içine yazılamaz ($OUT). Repo dışında bir klasör verin." ;;
esac
chmod 700 "$OUT"

for role in primary backup; do
  [[ ! -e "$OUT/manifest-signing-$role.key.pem" ]] \
    || die "$OUT/manifest-signing-$role.key.pem zaten var; üzerine yazmıyorum."
  [[ ! -e "$ROOT_DIR/keys/manifest-public-$role.pem" ]] \
    || die "keys/manifest-public-$role.pem zaten var; anahtarlar daha önce üretilmiş."
done

mkdir -p "$ROOT_DIR/keys"
for role in primary backup; do
  priv="$OUT/manifest-signing-$role.key.pem"
  (umask 077 && "$OPENSSL" genpkey -algorithm ED25519 -out "$priv")
  chmod 600 "$priv"
  "$OPENSSL" pkey -in "$priv" -pubout -out "$ROOT_DIR/keys/manifest-public-$role.pem"
done

echo
echo "Anahtarlar üretildi."
echo
echo "  Özel anahtarlar (GİZLİ, repoya koymayın):"
echo "    $OUT/manifest-signing-primary.key.pem   -> GitHub Secret MANIFEST_SIGNING_KEY"
echo "    $OUT/manifest-signing-backup.key.pem    -> yalnızca parola yöneticisinde saklayın"
echo
echo "  Public anahtarlar (repoya commit edilecek):"
for role in primary backup; do
  raw="$("$OPENSSL" pkey -pubin -in "$ROOT_DIR/keys/manifest-public-$role.pem" -outform DER | tail -c 32 | "$OPENSSL" base64 -A)"
  echo "    keys/manifest-public-$role.pem   (uygulamaya gömülecek ham anahtar: $raw)"
done
echo
echo "Sonraki adımlar: README.md > 'İmza anahtarları' bölümü."
