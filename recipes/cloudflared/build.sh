#!/usr/bin/env bash
set -euo pipefail
# cloudflared: official darwin-arm64 release binary, repackaged unmodified.
#
# Official verification (in addition to the pinned SHA-256 of the .tgz):
#  1. the SHA-256 of the binary inside must equal the one Cloudflare lists under
#     "SHA256 Checksums" in the GitHub release notes;
#  2. the binary must carry a valid Developer ID signature from Cloudflare
#     (Team ID 68WVV388M8). package.sh keeps that signature untouched.
CLOUDFLARE_TEAM_ID="68WVV388M8"
BIN="$SRC_DIR/cloudflared"
[[ -f "$BIN" ]] || { echo "cloudflared binary not found in archive" >&2; exit 1; }

API="repos/cloudflare/cloudflared/releases/tags/$PKG_VERSION"
if command -v gh >/dev/null 2>&1 && BODY="$(gh api "$API" --jq .body 2>/dev/null)"; then
  :
else
  BODY="$(curl -fsSL "https://api.github.com/$API" | jq -r .body)"
fi
EXPECTED="$(printf '%s\n' "$BODY" | tr -d '\r' \
            | awk -F': *' '$1 == "cloudflared-darwin-arm64.tgz" {print $2; exit}' | tr -d ' ')"
ACTUAL="$(shasum -a 256 "$BIN" | awk '{print $1}')"
if [[ -z "$EXPECTED" ]]; then
  echo "no SHA-256 for cloudflared-darwin-arm64.tgz in the $PKG_VERSION release notes" >&2; exit 1
fi
if [[ "$EXPECTED" != "$ACTUAL" ]]; then
  echo "cloudflared binary SHA-256 mismatch: release notes $EXPECTED, actual $ACTUAL" >&2; exit 1
fi
echo "cloudflared: binary matches the SHA-256 in the official release notes" >&2

codesign --verify --strict "$BIN"
SIGINFO="$(codesign -dv --verbose=2 "$BIN" 2>&1)"
if ! grep -q "^TeamIdentifier=$CLOUDFLARE_TEAM_ID\$" <<<"$SIGINFO" \
   || ! grep -q "^Authority=Developer ID Application: Cloudflare" <<<"$SIGINFO"; then
  printf '%s\n' "$SIGINFO" >&2
  echo "cloudflared is not signed by Cloudflare's Developer ID ($CLOUDFLARE_TEAM_ID)" >&2; exit 1
fi
echo "cloudflared: valid Developer ID signature (Team $CLOUDFLARE_TEAM_ID)" >&2

mkdir -p "$STAGE_DIR/bin" "$STAGE_DIR/share/licenses/cloudflared"
cp -p "$BIN" "$STAGE_DIR/bin/cloudflared"
chmod 0755 "$STAGE_DIR/bin/cloudflared"
# The release archive has no license file; LICENSE is vendored from the
# upstream repository (Apache-2.0), see recipes/cloudflared/LICENSE.
cp "$RECIPE_DIR/LICENSE" "$STAGE_DIR/share/licenses/cloudflared/LICENSE"
cat >"$WORK_DIR/meta.json" <<JSON
{
  "upstream": "https://github.com/cloudflare/cloudflared",
  "signedBy": "Developer ID Application: Cloudflare Inc. ($CLOUDFLARE_TEAM_ID)"
}
JSON
