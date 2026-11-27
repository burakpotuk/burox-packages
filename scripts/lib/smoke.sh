#!/usr/bin/env bash
# shellcheck shell=bash
# Helpers for recipes/*/smoke-test.sh. Source this file.

smoke_fail() { printf 'SMOKE FAIL: %s\n' "$*" >&2; exit 1; }
smoke_ok()   { printf 'smoke ok: %s\n' "$*" >&2; }

# A free TCP port on 127.0.0.1.
free_port() {
  python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

# wait_for_tcp <port> [tries]  (0.2 s apart)
wait_for_tcp() {
  local port="$1" tries="${2:-75}" i
  for ((i = 0; i < tries; i++)); do
    if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then return 0; fi
    sleep 0.2
  done
  return 1
}

# Self-signed certificate for localhost: make_cert <cert.pem> <key.pem>
make_cert() {
  openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj '/CN=localhost' \
    -keyout "$2" -out "$1" >/dev/null 2>&1 || smoke_fail "could not create test certificate"
}

# assert_contains <haystack> <needle> <what>
assert_contains() {
  case "$1" in
    *"$2"*) smoke_ok "$3" ;;
    *) printf '%s\n' "$1" >&2; smoke_fail "$3: expected to find '$2'" ;;
  esac
}

# Run a binary with an empty environment (no Homebrew paths, no DYLD_*), so the
# test proves the package works on a clean Mac.
clean_env() { env -i HOME="${HOME:-/tmp}" PATH=/usr/bin:/bin:/usr/sbin:/sbin "$@"; }
