#!/usr/bin/env bash
set -euo pipefail
# Pin a new upstream version after verifying it (GPG signature, official
# checksum file and/or GitHub release digest), then record it.
#
#   add-version.sh <package> <version> [--channel <channel>] [--replace]
#       recipes/<package>/sources.json  += pinned sha256
#       recipes/<package>/versions.json += build entry (unless already listed)
#       --replace: drop the other builds of the same channel from versions.json
#
#   add-version.sh --dep <dependency> <version>
#       deps/<dependency>/sources.json: version + pinned sha256 (old pin removed)
#
#   --url <exact-url>: for upstreams whose download path is not derivable from
#       the version (SQLite); stored next to the pin in sources.json.
#
# Example: scripts/add-version.sh nginx 1.30.9 --replace

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
require_cmd jq

DEP=0
CHANNEL=""
REPLACE=0
URL_OVERRIDE=""
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dep) DEP=1; shift ;;
    --channel) CHANNEL="$2"; shift 2 ;;
    --replace) REPLACE=1; shift ;;
    --url) URL_OVERRIDE="$2"; shift 2 ;;
    -h|--help) sed -n '3,15p' "$0"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
[[ ${#ARGS[@]} -eq 2 ]] || die "usage: add-version.sh [--dep] <name> <version> [--channel C] [--replace]"
NAME="${ARGS[0]}"
VERSION="${ARGS[1]}"
[[ "$VERSION" =~ ^[0-9A-Za-z][0-9A-Za-z._+-]*$ ]] || die "invalid version: $VERSION"

if [[ "$DEP" == "1" ]]; then
  SOURCES="$(dep_dir "$NAME")/sources.json"
else
  SOURCES="$(recipe_dir "$NAME")/sources.json"
fi
[[ -f "$SOURCES" ]] || die "not found: $SOURCES"

SHA="$(BUROX_SOURCE_URL="$URL_OVERRIDE" "$ROOT_DIR/scripts/fetch-source.sh" --pin "$SOURCES" "$VERSION" | tail -n1)"
[[ "$SHA" =~ ^[0-9a-f]{64}$ ]] || die "could not determine sha256"

write_json() {
  # write_json <file> <jq-filter> [jq args...]
  local file="$1" filter="$2" tmp
  shift 2
  tmp="$(mktemp "$file.XXXXXX")"
  jq --indent 2 "$@" "$filter" "$file" >"$tmp"
  mv -f "$tmp" "$file"
}

if [[ "$DEP" == "1" ]]; then
  write_json "$SOURCES" '.version = $v | .versions = {($v): (if $url == "" then $sha else {sha256: $sha, url: $url} end)}' \
    --arg v "$VERSION" --arg sha "$SHA" --arg url "$URL_OVERRIDE"
  log "pinned dependency $NAME $VERSION ($SHA)"
  exit 0
fi

write_json "$SOURCES" '.versions[$v] = (if $url == "" then $sha else {sha256: $sha, url: $url} end)' \
  --arg v "$VERSION" --arg sha "$SHA" --arg url "$URL_OVERRIDE"

VERSIONS="$(recipe_dir "$NAME")/versions.json"
[[ -f "$VERSIONS" ]] || die "not found: $VERSIONS"
if [[ -z "$CHANNEL" ]]; then
  CHANNEL="$(jq -r '.builds[-1].channel // "stable"' "$VERSIONS")"
fi
if jq -e --arg v "$VERSION" '.builds | any(.version == $v)' "$VERSIONS" >/dev/null; then
  log "$NAME $VERSION already listed in versions.json"
else
  if [[ "$REPLACE" == "1" ]]; then
    write_json "$VERSIONS" '.builds |= map(select(.channel != $c))' --arg c "$CHANNEL"
  fi
  write_json "$VERSIONS" '.builds += [{version: $v, channel: $c}]' --arg v "$VERSION" --arg c "$CHANNEL"
  log "added $NAME $VERSION (channel $CHANNEL) to versions.json"
fi

# Keep sources.json tidy: drop pins for versions that are no longer built.
write_json "$SOURCES" '.versions |= with_entries(select(.key as $k | $keep | index($k)))' \
  --argjson keep "$(jq -c '[.builds[].version]' "$VERSIONS")"
log "pinned $NAME $VERSION ($SHA)"
