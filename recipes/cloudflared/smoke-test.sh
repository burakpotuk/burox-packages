#!/usr/bin/env bash
set -euo pipefail
# Smoke test for an unpacked cloudflared package: smoke-test.sh <package-root>

# shellcheck source=../../scripts/lib/smoke.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/smoke.sh"
PKG="$(cd "${1:?usage: smoke-test.sh <package-root>}" && pwd)"
BIN="$PKG/bin/cloudflared"
[[ -x "$BIN" ]] || smoke_fail "missing bin/cloudflared"
EXPECTED_VERSION="$(jq -r .upstreamVersion "$PKG/PACKAGE.json")"

V="$(clean_env "$BIN" --version 2>&1)"
assert_contains "$V" "cloudflared version $EXPECTED_VERSION" "cloudflared --version"
codesign --verify --strict "$BIN" || smoke_fail "Cloudflare signature no longer valid after packaging"
smoke_ok "Developer ID signature intact"
