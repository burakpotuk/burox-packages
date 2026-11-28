#!/usr/bin/env bash
set -euo pipefail
# Build (or restore from the local cache) static dependency libraries into the
# shared deps prefix, in dependency order.
#
#   build-deps.sh <dep>...               populate $BUILD_ROOT/deps-prefix
#   build-deps.sh --print-key <dep>...   print one combined cache key and exit
#
# Every dependency lives in deps/<dep>/ with:
#   sources.json  (see fetch-source.sh; plus "version", "requires", "license")
#   build.sh      configure/make with --prefix="$PREFIX", install to "$DESTDIR"
#
# Each finished dependency is stored as $BUILD_ROOT/dep-cache/<dep>-<key>.tar.
# <key> hashes the recipe files, scripts/lib/build-env.sh, the prefix path and
# the keys of the dependencies it requires, so editing a recipe rebuilds it and
# everything above it. CI persists dep-cache/ with actions/cache.

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
require_cmd jq tar

PRINT_KEY=0
if [[ "${1:-}" == "--print-key" ]]; then PRINT_KEY=1; shift; fi

DEPS_PREFIX="${DEPS_PREFIX:-$BUILD_ROOT/deps-prefix}"
DEP_CACHE="${DEP_CACHE:-$BUILD_ROOT/dep-cache}"
export DEPS_PREFIX

dep_json() { printf '%s/sources.json' "$(dep_dir "$1")"; }

# --- dependency closure (topological order) ---------------------------------------
ORDER=()
VISITING=" "
visit() {
  local d="$1" r
  [[ -f "$(dep_json "$d")" ]] || die "unknown dependency '$d' (no deps/$d/sources.json)"
  case " ${ORDER[*]-} " in *" $d "*) return 0 ;; esac
  case "$VISITING" in *" $d "*) die "dependency cycle at '$d'" ;; esac
  VISITING+="$d "
  while IFS= read -r r; do
    [[ -n "$r" ]] && visit "$r"
  done < <(jq -r '.requires[]?' "$(dep_json "$d")")
  ORDER+=("$d")
}
for d in "$@"; do visit "$d"; done

if [[ ${#ORDER[@]} -eq 0 ]]; then
  # Nothing to build (e.g. prebuilt binary packages): leave an empty prefix.
  if [[ "$PRINT_KEY" == "1" ]]; then echo "none"; exit 0; fi
  rm -rf "$DEPS_PREFIX"; mkdir -p "$DEPS_PREFIX"
  log "no dependencies"
  exit 0
fi

# --- cache keys -------------------------------------------------------------------
KEYS_NAMES=()
KEYS_VALUES=()
key_of() {
  local i
  [[ ${#KEYS_NAMES[@]} -gt 0 ]] || die "internal: no key for $1"
  for i in "${!KEYS_NAMES[@]}"; do
    if [[ "${KEYS_NAMES[$i]}" == "$1" ]]; then printf '%s' "${KEYS_VALUES[$i]}"; return 0; fi
  done
  die "internal: no key for $1"
}
compute_key() {
  local d="$1" f r
  {
    printf 'burox-dep-v1\n%s\n%s\n%s\n' "$d" "$DEPS_PREFIX" "$MIN_MACOS"
    sha256_file "$ROOT_DIR/scripts/lib/build-env.sh"
    sha256_file "$ROOT_DIR/scripts/build-deps.sh"
    while IFS= read -r f; do
      printf '%s ' "${f#"$ROOT_DIR"/}"
      sha256_file "$f"
    done < <(find "$(dep_dir "$d")" -type f | LC_ALL=C sort)
    while IFS= read -r r; do
      [[ -n "$r" ]] && printf 'requires %s %s\n' "$r" "$(key_of "$r")"
    done < <(jq -r '.requires[]?' "$(dep_json "$d")")
  } | sha256_stdin | cut -c1-24
}
for d in "${ORDER[@]}"; do
  KEYS_NAMES+=("$d")
  KEYS_VALUES+=("$(compute_key "$d")")
done

if [[ "$PRINT_KEY" == "1" ]]; then
  for d in "${ORDER[@]}"; do printf '%s=%s\n' "$d" "$(key_of "$d")"; done | sha256_stdin | cut -c1-24
  exit 0
fi

# --- build / restore ----------------------------------------------------------------
rm -rf "$DEPS_PREFIX"
mkdir -p "$DEPS_PREFIX" "$DEP_CACHE"

build_one() {
  local d="$1" tarball="$2" version work stage lic
  version="$(jq -r '.version' "$(dep_json "$d")")"
  work="$BUILD_ROOT/dep-work/$d"
  stage="$work/stage"
  rm -rf "$work"
  mkdir -p "$work" "$stage"

  "$ROOT_DIR/scripts/fetch-source.sh" --record "$work/record.json" \
    "$(dep_json "$d")" "$version" "$work/src"

  group_start "build dependency $d $version"
  (
    export SRC_DIR="$work/src" PREFIX="$DEPS_PREFIX" DESTDIR="$stage" DEP_VERSION="$version"
    # shellcheck source=lib/build-env.sh
    source "$ROOT_DIR/scripts/lib/build-env.sh"
    cd "$SRC_DIR"
    bash "$(dep_dir "$d")/build.sh"
  )
  group_end

  local root="$stage$DEPS_PREFIX"
  [[ -d "$root/lib" ]] || die "dependency $d installed nothing under $DEPS_PREFIX/lib"
  # Static only: a stray dylib would silently win over the .a at link time.
  find "$root" -name '*.dylib' -print -delete | sed 's/^/removed shared library: /' >&2 || true
  # ...and tell libtool there is no shared variant, so it links the .a.
  while IFS= read -r -d '' la; do
    sed -i.bak -e "s/^dlname=.*/dlname=''/" -e "s/^library_names=.*/library_names=''/" "$la"
    rm -f "$la.bak"
  done < <(find "$root" -name '*.la' -type f -print0)

  mkdir -p "$root/share/burox-deps" "$root/share/licenses/$d"
  cp "$work/record.json" "$root/share/burox-deps/$d.json"
  while IFS= read -r lic; do
    [[ -n "$lic" ]] || continue
    [[ -f "$work/src/$lic" ]] || die "dependency $d: license file not found: $lic"
    cp "$work/src/$lic" "$root/share/licenses/$d/"
  done < <(jq -r '.license[]?' "$(dep_json "$d")")
  [[ -n "$(ls -A "$root/share/licenses/$d")" ]] || die "dependency $d: no license files (set \"license\" in sources.json)"

  tar -C "$root" -cf "$tarball.tmp" .
  mv -f "$tarball.tmp" "$tarball"
  rm -rf "$work"
}

NEEDED=()
for d in "${ORDER[@]}"; do
  tarball="$DEP_CACHE/$d-$(key_of "$d").tar"
  NEEDED+=("$(basename "$tarball")")
  if [[ -f "$tarball" ]]; then
    log "dependency $d: cache hit ($(basename "$tarball"))"
  else
    log "dependency $d: cache miss, building"
    build_one "$d" "$tarball"
  fi
  tar -C "$DEPS_PREFIX" -xf "$tarball"
done

if [[ "${BUROX_PRUNE_DEP_CACHE:-0}" == "1" ]]; then
  for f in "$DEP_CACHE"/*.tar; do
    [[ -e "$f" ]] || continue
    case " ${NEEDED[*]} " in *" $(basename "$f") "*) ;; *) log "pruning $(basename "$f")"; rm -f "$f" ;; esac
  done
fi

log "dependencies ready in $DEPS_PREFIX: ${ORDER[*]-none}"
