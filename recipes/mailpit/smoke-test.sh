#!/usr/bin/env bash
set -euo pipefail
# Smoke test for an unpacked Mailpit package: smoke-test.sh <package-root>
# --version, then start on 127.0.0.1, deliver one message over SMTP and read it
# back through the REST API.

# shellcheck source=../../scripts/lib/smoke.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/smoke.sh"
PKG="$(cd "${1:?usage: smoke-test.sh <package-root>}" && pwd)"
MAILPIT="$PKG/bin/mailpit"
[[ -x "$MAILPIT" ]] || smoke_fail "missing $MAILPIT"
EXPECTED_VERSION="$(jq -r .upstreamVersion "$PKG/PACKAGE.json")"

T="$(mktemp -d /tmp/bxs-mailpit.XXXXXX)"
MP_PID=""
cleanup() {
  [[ -n "$MP_PID" ]] && kill "$MP_PID" 2>/dev/null || true
  rm -rf "$T"
}
trap cleanup EXIT

V="$(clean_env "$MAILPIT" version --no-release-check 2>&1)"
assert_contains "$V" "v$EXPECTED_VERSION" "mailpit version $EXPECTED_VERSION"

HTTP_PORT="$(free_port)"
SMTP_PORT="$(free_port)"
clean_env "$MAILPIT" --listen "127.0.0.1:$HTTP_PORT" --smtp "127.0.0.1:$SMTP_PORT" \
  --database "$T/mailpit.db" --disable-version-check >"$T/mailpit.log" 2>&1 &
MP_PID=$!
disown "$MP_PID" 2>/dev/null || true
if ! wait_for_tcp "$SMTP_PORT" || ! wait_for_tcp "$HTTP_PORT"; then
  cat "$T/mailpit.log" >&2
  smoke_fail "mailpit did not start"
fi
smoke_ok "mailpit started"

printf 'From: smoke@burox.test\r\nTo: dev@burox.test\r\nSubject: burox smoke\r\n\r\nhello\r\n' >"$T/msg.eml"
curl -fsS "smtp://127.0.0.1:$SMTP_PORT" --mail-from smoke@burox.test \
  --mail-rcpt dev@burox.test --upload-file "$T/msg.eml" || smoke_fail "SMTP delivery failed"
smoke_ok "SMTP delivery"

for _ in $(seq 1 25); do
  R="$(curl -fsS "http://127.0.0.1:$HTTP_PORT/api/v1/messages" || true)"
  [[ "$R" == *"burox smoke"* ]] && break
  sleep 0.2
done
assert_contains "$R" "burox smoke" "message visible in REST API"
