#!/usr/bin/env bash
set -euo pipefail
# Smoke test for an unpacked lego package: smoke-test.sh <package-root>

# shellcheck source=../../scripts/lib/smoke.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/smoke.sh"
PKG="$(cd "${1:?usage: smoke-test.sh <package-root>}" && pwd)"
[[ -x "$PKG/bin/lego" ]] || smoke_fail "missing bin/lego"
EXPECTED_VERSION="$(jq -r .upstreamVersion "$PKG/PACKAGE.json")"

V="$(clean_env "$PKG/bin/lego" --version 2>&1)"
assert_contains "$V" "lego version $EXPECTED_VERSION" "lego --version"
assert_contains "$V" "darwin/arm64" "darwin/arm64 build"
H="$(clean_env "$PKG/bin/lego" --help 2>&1)"
assert_contains "$H" "dns" "lego --help lists DNS options"
