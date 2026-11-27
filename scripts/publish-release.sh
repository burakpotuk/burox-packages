#!/usr/bin/env bash
set -euo pipefail
# Publish a built package as the GitHub Release "<package>-<version>".
#
#   publish-release.sh <package> <version>
#
# Uploads out/<archive>.tar.xz, .tar.xz.sha256 and .package.json (the manifest
# sidecar). Refuses unless the smoke test passed for exactly this build
# (out/<archive>.smoke-passed). The release is created as a draft, filled, then
# published, so half-uploaded releases are never visible to make-manifest.py.
#
# Env: BUROX_FORCE=1 replaces an existing complete release (normally a new
#      build of the same version should bump "revision" in versions.json).
#      GH_TOKEN, GH_REPO (set by the workflow).

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
require_cmd gh jq

PKG="${1:?package}"
VERSION="${2:?version}"
PUBVER="$(published_version "$PKG" "$VERSION")"
BASE="$(archive_basename "$PKG" "$PUBVER")"
TAG="$PKG-$PUBVER"

ARCHIVE="$OUT_DIR/$BASE.tar.xz"
FILES=("$ARCHIVE" "$ARCHIVE.sha256" "$OUT_DIR/$BASE.package.json")
for f in "${FILES[@]}"; do [[ -f "$f" ]] || die "missing build output: $f"; done
[[ -f "$OUT_DIR/$BASE.smoke-passed" ]] || die "smoke test has not passed for $BASE; refusing to publish"
[[ "$(sha256_file "$ARCHIVE")" == "$(jq -r .sha256 "$OUT_DIR/$BASE.package.json")" ]] \
  || die "archive does not match its sidecar"

release_state() {
  # prints: none | complete | incomplete
  local json
  if ! json="$(gh release view "$TAG" --json assets,isDraft 2>/dev/null)"; then
    echo none; return
  fi
  if jq -e --arg a "$BASE.tar.xz" --arg s "$BASE.package.json" \
       '(.isDraft | not) and ([.assets[].name] | index($a) and index($s))' <<<"$json" >/dev/null; then
    echo complete
  else
    echo incomplete
  fi
}

STATE="$(release_state)"
case "$STATE" in
  complete)
    [[ "${BUROX_FORCE:-0}" == "1" ]] || die "release $TAG already exists (bump \"revision\" in versions.json or use force)"
    warn "force: deleting existing release $TAG"
    gh release delete "$TAG" --cleanup-tag --yes ;;
  incomplete)
    warn "deleting incomplete release $TAG"
    gh release delete "$TAG" --cleanup-tag --yes ;;
esac

PJ="$(tar -xOf "$ARCHIVE" PACKAGE.json)"
NOTES="$(mktemp)"
trap 'rm -f "$NOTES"' EXIT
{
  echo "**$PKG $PUBVER** for macOS $(jq -r .minMacOS <<<"$PJ")+ (Apple Silicon, arm64)"
  echo
  echo "| | |"
  echo "|---|---|"
  echo "| Archive | \`$BASE.tar.xz\` |"
  echo "| SHA-256 | \`$(sha256_file "$ARCHIVE")\` |"
  echo "| Size | $(file_size "$ARCHIVE") bytes |"
  echo "| Built | $(jq -r .buildDate <<<"$PJ") |"
  if [[ -n "$(jq -r '.build.runUrl // empty' <<<"$PJ")" ]]; then
    echo "| CI run | $(jq -r .build.runUrl <<<"$PJ") |"
  fi
  echo "| Commit | \`$(jq -r .build.gitCommit <<<"$PJ")\` |"
  echo
  echo "### Upstream sources"
  jq -r '.sources[] | "- \(.name) \(.version): <\(.url)>  \n  sha256 `\(.sha256)`" +
         (if .signature then "  \n  GPG signature verified (key `\(.signature.signer)`)" else "" end) +
         (if .checksumFile then "  \n  official checksum file verified" else "" end)' <<<"$PJ"
  if [[ "$(jq '.dependencies | length' <<<"$PJ")" != "0" ]]; then
    echo
    echo "### Statically linked dependencies"
    jq -r '.dependencies[] | "- \(.name) \(.version) (sha256 `\(.sha256)`" +
           (if .signature then ", GPG key `\(.signature.signer)`" else "" end) + ")"' <<<"$PJ"
  fi
  echo
  echo "Smoke test passed; every Mach-O file links only to /usr/lib and /System."
} >"$NOTES"

TARGET="${GITHUB_SHA:-$(git -C "$ROOT_DIR" rev-parse HEAD)}"
gh release create "$TAG" --draft --title "$PKG $PUBVER" --notes-file "$NOTES" \
  --target "$TARGET" "${FILES[@]}"
gh release edit "$TAG" --draft=false --latest=false
log "published release $TAG"
