#!/usr/bin/env bash
set -euo pipefail
# Decide which versions of a package a workflow run must build.
#
#   plan-builds.sh <package> [<versions>] [<force:true|false>] [<publish:true|false>]
#
# <versions>: space/comma separated upstream versions; empty = every build in
# recipes/<package>/versions.json. When publishing without force, versions that
# already have a complete GitHub Release are skipped.
# Prints GitHub Actions outputs:  matrix=<json>  and  count=<n>

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
require_cmd jq

PKG="${1:?package}"
FILTER="${2:-}"
FORCE="${3:-false}"
PUBLISH="${4:-true}"
VFILE="$(recipe_dir "$PKG")/versions.json"
[[ -f "$VFILE" ]] || die "unknown package: $PKG"

ALL=()
while IFS= read -r v; do ALL+=("$v"); done < <(jq -r '.builds[].version' "$VFILE")

SELECTED=()
if [[ -n "${FILTER//[ ,]/}" ]]; then
  for v in ${FILTER//,/ }; do
    case " ${ALL[*]-} " in
      *" $v "*) SELECTED+=("$v") ;;
      *) die "$PKG $v is not listed in recipes/$PKG/versions.json" ;;
    esac
  done
else
  SELECTED=(${ALL[@]+"${ALL[@]}"})
fi

is_published() {
  local tag="$1" base="$2" json
  json="$(gh release view "$tag" --json assets,isDraft 2>/dev/null)" || return 1
  jq -e --arg a "$base.tar.xz" --arg s "$base.package.json" \
    '(.isDraft | not) and ([.assets[].name] | index($a) and index($s))' <<<"$json" >/dev/null
}

INCLUDE='[]'
for v in ${SELECTED[@]+"${SELECTED[@]}"}; do
  pub="$(published_version "$PKG" "$v")"
  if [[ "$PUBLISH" == "true" && "$FORCE" != "true" ]] && is_published "$PKG-$pub" "$(archive_basename "$PKG" "$pub")"; then
    log "$PKG $pub: already published, skipping"
    continue
  fi
  log "$PKG $pub: will build"
  INCLUDE="$(jq -c --arg v "$v" --arg p "$pub" '. + [{version: $v, published: $p}]' <<<"$INCLUDE")"
done

printf 'matrix=%s\n' "$(jq -c '{include: .}' <<<"$INCLUDE")"
printf 'count=%s\n' "$(jq 'length' <<<"$INCLUDE")"
