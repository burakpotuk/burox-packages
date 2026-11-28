#!/usr/bin/env bash
set -euo pipefail
# Build one package version end to end. The same script runs locally and in CI.
#
#   build-package.sh <package> <version>              fetch, deps, build, package, smoke test
#   build-package.sh --deps-only <package> <version>  only build/restore dependencies
#   build-package.sh --print-deps-key <package> <version>
#   build-package.sh --no-smoke <package> <version>   skip the smoke test (debugging only)
#
# <version> is the upstream version as listed in recipes/<package>/versions.json.
#
# Recipe contract (recipes/<package>/build.sh), run with cwd = $SRC_DIR and:
#   PKG_NAME, PKG_VERSION (upstream), PKG_PUBLISHED_VERSION, SRC_DIR, STAGE_DIR,
#   WORK_DIR, RECIPE_DIR, EXTRAS_DIR (extracted "extras"), BUILD_ENTRY (the
#   versions.json build entry as JSON), DEPS_PREFIX (+ JOBS and the compiler env from
#   scripts/lib/build-env.sh for "kind": "source" recipes)
# It must populate $STAGE_DIR (bin/ sbin/ lib/ share/ etc-default/), install
# upstream licenses into $STAGE_DIR/share/licenses/$PKG_NAME/ and may write
# extra metadata to $WORK_DIR/meta.json.
#
# Smoke test contract: recipes/<package>/smoke-test.sh <unpacked-package-root>
# runs against a fresh extraction of the final archive in a different directory.

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
require_cmd jq

MODE="all"
SMOKE=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --deps-only) MODE="deps"; shift ;;
    --print-deps-key) MODE="key"; shift ;;
    --no-smoke) SMOKE=0; shift ;;
    -*) die "unknown option: $1" ;;
    *) break ;;
  esac
done
[[ $# -eq 2 ]] || die "usage: build-package.sh [--deps-only|--print-deps-key|--no-smoke] <package> <version>"
PKG="$1"
VERSION="$2"

RECIPE="$(recipe_dir "$PKG")"
[[ -d "$RECIPE" ]] || die "unknown package: $PKG"
VFILE="$RECIPE/versions.json"
ENTRY="$(build_entry "$PKG" "$VERSION")"
KIND="$(jq -r '.kind // "source"' "$VFILE")"
DEPS=()
while IFS= read -r d; do
  [[ -n "$d" ]] && DEPS+=("$d")
done < <(jq -r --argjson e "$ENTRY" '($e.deps // .deps // [])[]' "$VFILE")

export DEPS_PREFIX="${DEPS_PREFIX:-$BUILD_ROOT/deps-prefix}"

case "$MODE" in
  key)
    "$ROOT_DIR/scripts/build-deps.sh" --print-key ${DEPS[@]+"${DEPS[@]}"}
    exit 0 ;;
  deps)
    "$ROOT_DIR/scripts/build-deps.sh" ${DEPS[@]+"${DEPS[@]}"}
    exit 0 ;;
esac

PUBVER="$(published_version "$PKG" "$VERSION")"
BASE="$(archive_basename "$PKG" "$PUBVER")"
WORK="$BUILD_ROOT/work/$PKG-$PUBVER"
log "building $PKG $PUBVER ($KIND) deps: ${DEPS[*]-none}"

rm -rf "$WORK"
mkdir -p "$WORK/stage" "$WORK/records"
# Marker checked by publish-release.sh: no smoke test, no release.
rm -f "$OUT_DIR/$BASE.smoke-passed"

"$ROOT_DIR/scripts/fetch-source.sh" --record "$WORK/records/$PKG.json" \
  "$RECIPE/sources.json" "$VERSION" "$WORK/src"

# Extra sources pinned per build, e.g. PECL extensions for PHP:
#   versions.json build entry: "extras": {"xdebug": "3.5.3"}
#   source description:        recipes/<package>/extras/xdebug.json
mkdir -p "$WORK/extras"
while IFS=$'\t' read -r ename ever; do
  [[ -n "$ename" ]] || continue
  "$ROOT_DIR/scripts/fetch-source.sh" --record "$WORK/records/$ename.json" \
    "$RECIPE/extras/$ename.json" "$ever" "$WORK/extras/$ename"
done < <(jq -r '(.extras // {}) | to_entries[] | [.key, .value] | @tsv' <<<"$ENTRY")

"$ROOT_DIR/scripts/build-deps.sh" ${DEPS[@]+"${DEPS[@]}"}

group_start "build $PKG $PUBVER"
(
  export PKG_NAME="$PKG" PKG_VERSION="$VERSION" PKG_PUBLISHED_VERSION="$PUBVER" \
         SRC_DIR="$WORK/src" STAGE_DIR="$WORK/stage" WORK_DIR="$WORK" RECIPE_DIR="$RECIPE" \
         EXTRAS_DIR="$WORK/extras" BUILD_ENTRY="$ENTRY"
  if [[ "$KIND" == "source" ]]; then
    # shellcheck source=lib/build-env.sh
    source "$ROOT_DIR/scripts/lib/build-env.sh"
  fi
  cd "$SRC_DIR"
  bash "$RECIPE/build.sh"
)
group_end

group_start "package $PKG $PUBVER"
"$ROOT_DIR/scripts/package.sh" "$PKG" "$VERSION" "$WORK"
group_end

if [[ "$SMOKE" == "1" ]]; then
  group_start "smoke test $PKG $PUBVER"
  # Short path on purpose: unix socket paths are limited to 104 bytes.
  SMOKE_ROOT="$(mktemp -d /tmp/burox-smoke.XXXXXX)"
  tar -xf "$OUT_DIR/$BASE.tar.xz" -C "$SMOKE_ROOT"
  if ! bash "$RECIPE/smoke-test.sh" "$SMOKE_ROOT"; then
    rm -rf "$SMOKE_ROOT"
    die "smoke test FAILED for $PKG $PUBVER"
  fi
  rm -rf "$SMOKE_ROOT"
  group_end
  date -u +%Y-%m-%dT%H:%M:%SZ >"$OUT_DIR/$BASE.smoke-passed"
  log "smoke test passed for $PKG $PUBVER"
else
  warn "smoke test skipped for $PKG $PUBVER (--no-smoke); do not publish this build"
fi

log "done: $OUT_DIR/$BASE.tar.xz"
