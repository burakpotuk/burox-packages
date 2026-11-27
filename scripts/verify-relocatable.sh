#!/usr/bin/env bash
set -euo pipefail
# Fail if any Mach-O file under <dir> could depend on something outside the
# operating system, i.e. would break when the package is unpacked elsewhere.
#
#   verify-relocatable.sh [--min-macos <ver>] <dir>
#
# For every Mach-O file (executable, .dylib, .so/.bundle):
#   - contains an arm64 slice
#   - every linked library (otool -L) is under /usr/lib/ or /System/
#   - no LC_RPATH outside /usr/lib/ or /System/
#   - minimum macOS (LC_BUILD_VERSION minos) <= 14.0 (or the package's
#     declared minMacOS passed with --min-macos)
#   - has a valid code signature (ad-hoc or real)
# Text files that mention the build directory only produce a warning.

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
require_cmd otool lipo codesign file

if [[ "${1:-}" == "--min-macos" ]]; then
  MIN_MACOS="${2:?--min-macos needs a version}"
  shift 2
fi
DIR="${1:?usage: verify-relocatable.sh [--min-macos <ver>] <dir>}"
[[ -d "$DIR" ]] || die "not a directory: $DIR"

allowed_path() {
  case "$1" in
    /usr/lib/*|/System/*) return 0 ;;
    *) return 1 ;;
  esac
}

# version_le A B  -> true if A <= B (dotted numeric versions)
version_le() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    na = split(a, x, "."); nb = split(b, y, ".");
    n = (na > nb) ? na : nb;
    for (i = 1; i <= n; i++) {
      xi = (i <= na) ? x[i] + 0 : 0; yi = (i <= nb) ? y[i] + 0 : 0;
      if (xi < yi) exit 0; if (xi > yi) exit 1;
    }
    exit 0 }'
}

VIOLATIONS=0
COUNT=0
violation() {
  VIOLATIONS=$((VIOLATIONS + 1))
  if in_ci; then
    printf '::error title=verify-relocatable::%s: %s\n' "$1" "$2" >&2
  else
    printf '  VIOLATION %s: %s\n' "$1" "$2" >&2
  fi
}

while IFS= read -r -d '' f; do
  desc="$(file -b "$f")"
  [[ "$desc" == Mach-O* ]] || continue
  COUNT=$((COUNT + 1))
  rel="${f#"$DIR"/}"

  archs="$(lipo -archs "$f" 2>/dev/null || true)"
  if [[ " $archs " != *" arm64 "* ]]; then
    violation "$rel" "no arm64 slice (archs: ${archs:-unknown})"
    continue
  fi

  own_id="$(otool -arch arm64 -D "$f" | tail -n +2 | head -n1)"
  libs=()
  while IFS= read -r lib; do
    [[ -n "$lib" ]] || continue
    [[ -n "$own_id" && "$lib" == "$own_id" ]] && continue
    libs+=("$lib")
    allowed_path "$lib" || violation "$rel" "links $lib"
  done < <(otool -arch arm64 -L "$f" | tail -n +2 | awk '{print $1}')

  while IFS= read -r rp; do
    [[ -n "$rp" ]] || continue
    allowed_path "$rp" || violation "$rel" "LC_RPATH $rp"
  done < <(otool -arch arm64 -l "$f" | awk '$1 == "cmd" && $2 == "LC_RPATH" {getline; getline; print $2}')

  minos="$(otool -arch arm64 -l "$f" | awk '
      $1 == "cmd" && $2 == "LC_BUILD_VERSION" { want = 1 }
      want && $1 == "minos" { print $2; exit }
      $1 == "cmd" && $2 == "LC_VERSION_MIN_MACOSX" { getline; getline; print $2; exit }')"
  if [[ -z "$minos" ]]; then
    violation "$rel" "no minimum macOS version load command"
  elif ! version_le "$minos" "$MIN_MACOS"; then
    violation "$rel" "requires macOS $minos (> $MIN_MACOS)"
  fi

  if ! codesign --verify --strict "$f" 2>/dev/null; then
    violation "$rel" "missing or invalid code signature"
  fi

  printf '  checked %-45s minos=%-6s libs=%s\n' "$rel" "${minos:-?}" "${libs[*]-none}" >&2
done < <(find "$DIR" -type f -print0)

# Advisory only: hard-coded build paths in text files (scripts, .pc, configs).
if grep -rIl --exclude='PACKAGE.json' -- "$BUILD_ROOT" "$DIR" >/dev/null 2>&1; then
  while IFS= read -r t; do
    warn "build path ($BUILD_ROOT) appears in ${t#"$DIR"/}"
  done < <(grep -rIl --exclude='PACKAGE.json' -- "$BUILD_ROOT" "$DIR")
fi

[[ "$COUNT" -gt 0 ]] || warn "no Mach-O files found under $DIR"
if [[ "$VIOLATIONS" -gt 0 ]]; then
  die "verify-relocatable: $VIOLATIONS violation(s) in $COUNT Mach-O file(s)"
fi
log "verify-relocatable: $COUNT Mach-O file(s) OK (only /usr/lib and /System dependencies)"
