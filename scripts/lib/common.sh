#!/usr/bin/env bash
# shellcheck shell=bash
# Shared helpers. Source this file; do not execute it.
#
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

if [[ -n "${BUROX_COMMON_SH:-}" ]]; then
  return 0
fi
BUROX_COMMON_SH=1

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_ROOT="${BUILD_ROOT:-$ROOT_DIR/build}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/out}"
PLATFORM="darwin-arm64"
TARGET_ARCH="arm64"
MIN_MACOS="14.0"
export ROOT_DIR BUILD_ROOT OUT_DIR PLATFORM TARGET_ARCH MIN_MACOS

in_ci() { [[ "${GITHUB_ACTIONS:-}" == "true" ]]; }

log()  { printf '==> %s\n' "$*" >&2; }
warn() {
  if in_ci; then printf '::warning::%s\n' "$*" >&2; else printf 'warning: %s\n' "$*" >&2; fi
}
die() {
  if in_ci; then printf '::error::%s\n' "$*" >&2; else printf 'error: %s\n' "$*" >&2; fi
  exit 1
}

# Collapsible log sections on GitHub Actions.
group_start() { if in_ci; then printf '::group::%s\n' "$*"; else log "$*"; fi; }
group_end()   { if in_ci; then printf '::endgroup::\n'; fi; }

require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "required command not found: $c"
  done
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

ncpu() { sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4; }

file_size() { wc -c <"$1" | tr -d ' '; }

utc_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Locate an OpenSSL >= 3 binary (needed for Ed25519 with -rawin).
# macOS ships LibreSSL as /usr/bin/openssl, which cannot do this.
find_openssl3() {
  local cand
  for cand in "${OPENSSL:-}" openssl \
              /opt/homebrew/opt/openssl@3/bin/openssl \
              /usr/local/opt/openssl@3/bin/openssl; do
    [[ -n "$cand" ]] || continue
    command -v "$cand" >/dev/null 2>&1 || continue
    if "$cand" version 2>/dev/null | grep -Eq '^OpenSSL ([3-9]|[1-9][0-9])\.'; then
      command -v "$cand"
      return 0
    fi
  done
  return 1
}

# Recipe / dependency lookup -------------------------------------------------

recipe_dir() { printf '%s/recipes/%s' "$ROOT_DIR" "$1"; }
dep_dir()    { printf '%s/deps/%s' "$ROOT_DIR" "$1"; }

# Print the versions.json build entry for <pkg> <version> as compact JSON.
build_entry() {
  local pkg="$1" version="$2" vfile
  vfile="$(recipe_dir "$pkg")/versions.json"
  [[ -f "$vfile" ]] || die "no versions.json for package '$pkg'"
  jq -ce --arg v "$version" '.builds[] | select(.version == $v)' "$vfile" \
    || die "version '$version' is not listed in recipes/$pkg/versions.json"
}

# Full published version string: upstream version plus optional _<revision>.
published_version() {
  local pkg="$1" version="$2" rev
  rev="$(build_entry "$pkg" "$version" | jq -r '.revision // 0')"
  if [[ "$rev" == "0" ]]; then printf '%s' "$version"; else printf '%s_%s' "$version" "$rev"; fi
}

archive_basename() { printf '%s-%s-%s' "$1" "$2" "$PLATFORM"; }
