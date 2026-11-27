#!/usr/bin/env bash
set -euo pipefail
# Static consistency checks for recipes/ and deps/ (no network, no build):
#   - every recipe has sources.json, versions.json, build.sh, smoke-test.sh
#   - every build in versions.json has a pinned SHA-256 and a channel
#   - every dependency exists, has a pinned SHA-256 for its version and a license
#   - signature-checked sources reference an existing keys/upstream/<keyring>.asc

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
require_cmd jq

ERRORS=0
err() { ERRORS=$((ERRORS + 1)); printf 'error: %s\n' "$*" >&2; }

check_sources() {
  local f="$1" keyring
  jq -e '.name and .url and (.versions | type == "object")' "$f" >/dev/null || err "$f: needs name, url, versions"
  if jq -e '.signature' "$f" >/dev/null; then
    keyring="$(jq -r '.keyring // empty' "$f")"
    [[ -n "$keyring" && -f "$ROOT_DIR/keys/upstream/$keyring.asc" ]] || err "$f: missing keys/upstream/${keyring:-?}.asc"
  fi
  while IFS= read -r v; do
    err "$f: invalid sha256 for $v"
  done < <(jq -r '.versions | to_entries[] | select(.value | test("^[0-9a-f]{64}$") | not) | .key' "$f")
}

for dir in "$ROOT_DIR"/deps/*/; do
  d="$(basename "$dir")"
  f="$dir/sources.json"
  [[ -f "$f" ]] || { err "deps/$d: missing sources.json"; continue; }
  [[ -x "$dir/build.sh" ]] || err "deps/$d: missing or non-executable build.sh"
  check_sources "$f"
  v="$(jq -r '.version // empty' "$f")"
  [[ -n "$v" ]] || err "deps/$d: missing version"
  jq -e --arg v "$v" '.versions[$v]' "$f" >/dev/null || err "deps/$d: version $v is not pinned"
  jq -e '(.license | type == "array") and (.license | length > 0)' "$f" >/dev/null || err "deps/$d: no license files listed"
  for r in $(jq -r '.requires[]?' "$f"); do
    [[ -f "$ROOT_DIR/deps/$r/sources.json" ]] || err "deps/$d: requires unknown dependency $r"
  done
done

for dir in "$ROOT_DIR"/recipes/*/; do
  p="$(basename "$dir")"
  for x in sources.json versions.json; do [[ -f "$dir/$x" ]] || err "recipes/$p: missing $x"; done
  for x in build.sh smoke-test.sh; do [[ -x "$dir/$x" ]] || err "recipes/$p: missing or non-executable $x"; done
  [[ -f "$dir/sources.json" && -f "$dir/versions.json" ]] || continue
  check_sources "$dir/sources.json"
  jq -e '.kind == "source" or .kind == "binary"' "$dir/versions.json" >/dev/null || err "recipes/$p: kind must be source or binary"
  [[ "$(jq -r .name "$dir/versions.json")" == "$p" ]] || err "recipes/$p: versions.json name mismatch"
  while IFS=$'\t' read -r v ch; do
    [[ -n "$ch" && "$ch" != "null" ]] || err "recipes/$p: build $v has no channel"
    jq -e --arg v "$v" '.versions[$v]' "$dir/sources.json" >/dev/null || err "recipes/$p: version $v is not pinned in sources.json"
  done < <(jq -r '.builds[] | [.version, .channel] | @tsv' "$dir/versions.json")
  for d in $(jq -r '[.deps[]?, (.builds[].deps // [])[]] | unique[]' "$dir/versions.json"); do
    [[ -f "$ROOT_DIR/deps/$d/sources.json" ]] || err "recipes/$p: unknown dependency $d"
  done
done

[[ "$ERRORS" -eq 0 ]] || die "check-recipes: $ERRORS problem(s)"
log "check-recipes: all recipes and dependencies are consistent"
