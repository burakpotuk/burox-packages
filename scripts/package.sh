#!/usr/bin/env bash
set -euo pipefail
# Turn a recipe's staged install into the final, signed, verified archive.
#
#   package.sh <package> <version> <work-dir>
#
# Reads   <work-dir>/stage/          (filled by recipes/<package>/build.sh)
#         <work-dir>/records/*.json  (source records from fetch-source.sh)
#         <work-dir>/meta.json       (optional, recipe-specific metadata)
#         $DEPS_PREFIX/share/{licenses,burox-deps}  (static dependencies used)
# Writes  $OUT_DIR/<name>-<version>-darwin-arm64.tar.xz
#         $OUT_DIR/<name>-<version>-darwin-arm64.tar.xz.sha256
#         $OUT_DIR/<name>-<version>-darwin-arm64.package.json  (manifest sidecar)

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
require_cmd jq tar codesign strip file

PKG="${1:?package}"
VERSION="${2:?version}"
WORK="${3:?work dir}"
STAGE="$WORK/stage"
DEPS_PREFIX="${DEPS_PREFIX:-$BUILD_ROOT/deps-prefix}"
[[ -d "$STAGE" ]] || die "stage directory missing: $STAGE"

VFILE="$(recipe_dir "$PKG")/versions.json"
ENTRY="$(build_entry "$PKG" "$VERSION")"
KIND="$(jq -r '.kind // "source"' "$VFILE")"
CHANNEL="$(jq -r '.channel' <<<"$ENTRY")"
REVISION="$(jq -r '.revision // 0' <<<"$ENTRY")"
PUBVER="$(published_version "$PKG" "$VERSION")"
BASE="$(archive_basename "$PKG" "$PUBVER")"
[[ -n "$CHANNEL" && "$CHANNEL" != "null" ]] || die "versions.json: build $VERSION has no channel"
# Minimum macOS of this package: 14.0 unless versions.json declares a higher one
# (only for upstream binaries we cannot rebuild, e.g. cloudflared).
PKG_MIN_MACOS="$(jq -r --argjson e "$ENTRY" '$e.minMacOS // .minMacOS // empty' "$VFILE")"
PKG_MIN_MACOS="${PKG_MIN_MACOS:-$MIN_MACOS}"
if [[ "$PKG_MIN_MACOS" != "$MIN_MACOS" ]]; then
  [[ "$KIND" == "binary" ]] || die "minMacOS override is only allowed for prebuilt binary packages"
  warn "$PKG $VERSION requires macOS $PKG_MIN_MACOS (project minimum is $MIN_MACOS)"
fi

# --- layout -------------------------------------------------------------------------
find "$STAGE" -name '.DS_Store' -delete
for entry in "$STAGE"/* "$STAGE"/.[!.]*; do
  [[ -e "$entry" ]] || continue
  case "$(basename "$entry")" in
    bin|sbin|lib|share|etc-default) ;;
    *) die "unexpected top-level entry in package: $(basename "$entry") (allowed: bin sbin lib share etc-default)" ;;
  esac
done
if find "$STAGE" \( -name '*.a' -o -name '*.la' \) | grep -q .; then
  die "static libraries (.a/.la) must not be shipped: $(find "$STAGE" \( -name '*.a' -o -name '*.la' \) | head -n3 | tr '\n' ' ')"
fi

# --- licenses ---------------------------------------------------------------------
LIC="$STAGE/share/licenses"
if [[ -z "$(ls -A "$LIC/$PKG" 2>/dev/null)" ]]; then
  die "recipe must install upstream license files into share/licenses/$PKG/"
fi
if [[ -d "$DEPS_PREFIX/share/licenses" ]]; then
  for d in "$DEPS_PREFIX/share/licenses"/*; do
    [[ -d "$d" ]] || continue
    mkdir -p "$LIC/$(basename "$d")"
    cp -R "$d/." "$LIC/$(basename "$d")/"
  done
fi

# --- strip + sign -------------------------------------------------------------------
MACHO=()
while IFS= read -r -d '' f; do
  if [[ "$(file -b "$f")" == Mach-O* ]]; then MACHO+=("$f"); fi
done < <(find "$STAGE" -type f -print0)

for f in ${MACHO[@]+"${MACHO[@]}"}; do
  if [[ "$KIND" == "source" ]]; then
    # -x keeps global symbols: httpd modules resolve APR/httpd symbols from the
    # main executable at load time.
    strip -x "$f"
    codesign --force --sign - --timestamp=none "$f" 2>/dev/null
  elif codesign --verify --strict "$f" 2>/dev/null; then
    # Prebuilt upstream binary with a valid signature (Developer ID or the Go
    # linker's ad-hoc signature): keep it untouched.
    :
  else
    codesign --force --sign - --timestamp=none "$f" 2>/dev/null
  fi
done
log "signed ${#MACHO[@]} Mach-O file(s)"

"$ROOT_DIR/scripts/verify-relocatable.sh" --min-macos "$PKG_MIN_MACOS" "$STAGE"

# --- PACKAGE.json -------------------------------------------------------------------
META='{}'
[[ -f "$WORK/meta.json" ]] && META="$(jq -c . "$WORK/meta.json")"
SOURCES='[]'
if compgen -G "$WORK/records/*.json" >/dev/null; then
  SOURCES="$(jq -cs . "$WORK"/records/*.json)"
fi
DEPENDENCIES='[]'
if compgen -G "$DEPS_PREFIX/share/burox-deps/*.json" >/dev/null; then
  DEPENDENCIES="$(jq -cs 'sort_by(.name)' "$DEPS_PREFIX"/share/burox-deps/*.json)"
fi
RUN_URL=""
if in_ci; then RUN_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"; fi
GIT_COMMIT="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
HOST_MACOS="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
XCODE="$(xcodebuild -version 2>/dev/null | head -n1 | awk '{print $2}' || echo unknown)"

jq -n \
  --arg name "$PKG" --arg version "$PUBVER" --arg upstream "$VERSION" \
  --argjson revision "$REVISION" --arg channel "$CHANNEL" --arg kind "$KIND" \
  --arg platform "$PLATFORM" --arg minos "$PKG_MIN_MACOS" --arg date "$(utc_now)" \
  --arg commit "$GIT_COMMIT" --arg run "$RUN_URL" --arg host "$HOST_MACOS" --arg xcode "$XCODE" \
  --argjson sources "$SOURCES" --argjson deps "$DEPENDENCIES" --argjson meta "$META" \
  '{
     schemaVersion: 1,
     name: $name, version: $version, upstreamVersion: $upstream, revision: $revision,
     channel: $channel, kind: $kind, platform: $platform, arch: "arm64", minMacOS: $minos,
     buildDate: $date,
     build: ({gitCommit: $commit, hostMacOS: $host, xcode: $xcode}
             + (if $run != "" then {runUrl: $run} else {} end)),
     sources: $sources,
     dependencies: $deps,
     meta: $meta
   }' >"$STAGE/PACKAGE.json"

# --- archive ------------------------------------------------------------------------
mkdir -p "$OUT_DIR"
ARCHIVE="$OUT_DIR/$BASE.tar.xz"
rm -f "$ARCHIVE" "$ARCHIVE.sha256" "$OUT_DIR/$BASE.package.json"
ENTRIES=()
for e in PACKAGE.json bin sbin lib share etc-default; do
  [[ -e "$STAGE/$e" ]] && ENTRIES+=("$e")
done
COPYFILE_DISABLE=1 tar -C "$STAGE" \
  --uid 0 --gid 0 --uname root --gname wheel \
  --no-mac-metadata --no-xattrs --no-acls --no-fflags \
  --options xz:compression-level=9 \
  -cJf "$ARCHIVE" "${ENTRIES[@]}"

SHA="$(sha256_file "$ARCHIVE")"
SIZE="$(file_size "$ARCHIVE")"
printf '%s  %s\n' "$SHA" "$BASE.tar.xz" >"$ARCHIVE.sha256"

jq -n --arg name "$PKG" --arg channel "$CHANNEL" --arg version "$PUBVER" \
      --arg file "$BASE.tar.xz" --arg sha "$SHA" --argjson size "$SIZE" \
      --arg minos "$PKG_MIN_MACOS" --argjson meta "$META" \
  '{name: $name, channel: $channel, version: $version, arch: "arm64",
    file: $file, sha256: $sha, size: $size, minMacOS: $minos, meta: $meta}' \
  >"$OUT_DIR/$BASE.package.json"

log "package: $ARCHIVE ($SIZE bytes, sha256 $SHA)"
