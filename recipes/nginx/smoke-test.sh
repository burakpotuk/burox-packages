#!/usr/bin/env bash
set -euo pipefail
# Smoke test for an unpacked nginx package: smoke-test.sh <package-root>
# config test, start on 127.0.0.1, HTTP 200, HTTPS + HTTP/2, stub_status,
# sub_filter, auth_request, realip, PCRE2, fastcgi_pass over a unix socket,
# then a clean stop.

# shellcheck source=../../scripts/lib/smoke.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/smoke.sh"
FCGI_ECHO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib" && pwd)/fcgi_echo.py"

PKG="$(cd "${1:?usage: smoke-test.sh <package-root>}" && pwd)"
NGINX="$PKG/sbin/nginx"
[[ -x "$NGINX" ]] || smoke_fail "missing $NGINX"

T="$(mktemp -d /tmp/bxs-nginx.XXXXXX)"
FCGI_PID=""
cleanup() {
  if [[ -f "$T/logs/nginx.pid" ]]; then
    kill -TERM "$(cat "$T/logs/nginx.pid")" 2>/dev/null || true
    sleep 0.5
  fi
  [[ -n "$FCGI_PID" ]] && kill "$FCGI_PID" 2>/dev/null || true
  rm -rf "$T"
}
trap cleanup EXIT

HTTP_PORT="$(free_port)"
HTTPS_PORT="$(free_port)"
mkdir -p "$T/conf" "$T/logs" "$T/temp" "$T/html/protected" "$T/html/denied"
cp "$PKG/etc-default/mime.types" "$PKG/etc-default/fastcgi_params" "$T/conf/"
echo "<?php // handled by the FastCGI echo backend" >"$T/html/test.php"
python3 "$FCGI_ECHO" "$T/fcgi.sock" &
FCGI_PID=$!
disown "$FCGI_PID" 2>/dev/null || true
make_cert "$T/conf/cert.pem" "$T/conf/key.pem"
echo "burox-smoke-index" >"$T/html/index.html"
echo "burox-smoke-protected" >"$T/html/protected/index.html"
echo "should-not-see" >"$T/html/denied/index.html"

cat >"$T/conf/nginx.conf" <<EOF
worker_processes 1;
pid logs/nginx.pid;
error_log logs/error.log info;
events { worker_connections 64; }
http {
    include mime.types;
    access_log logs/access.log;
    client_body_temp_path temp/client_body;
    proxy_temp_path temp/proxy;
    fastcgi_temp_path temp/fastcgi;
    uwsgi_temp_path temp/uwsgi;
    scgi_temp_path temp/scgi;
    set_real_ip_from 127.0.0.1;
    real_ip_header X-Forwarded-For;

    server {
        listen 127.0.0.1:${HTTP_PORT};
        root html;
        location = /status { stub_status; }
        location = /sub {
            default_type text/html;
            sub_filter 'REPLACE-ME' 'replaced-ok';
            return 200 "<p>REPLACE-ME</p>";
        }
        location = /ip { default_type text/plain; return 200 "\$remote_addr"; }
        location /protected/ { auth_request /auth-yes; }
        location /denied/ { auth_request /auth-no; }
        location = /auth-yes { internal; return 204; }
        location = /auth-no { internal; return 403; }
        location ~ ^/re/(?<word>[a-z]+)\$ { default_type text/plain; return 200 "pcre:\$word"; }
        location ~ \.php\$ {
            include fastcgi_params;
            fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
            fastcgi_pass unix:$T/fcgi.sock;
        }
    }
    server {
        listen 127.0.0.1:${HTTPS_PORT} ssl;
        http2 on;
        ssl_certificate cert.pem;
        ssl_certificate_key key.pem;
        location / { default_type text/plain; return 200 "tls-ok"; }
    }
}
EOF

V="$(clean_env "$NGINX" -V 2>&1)"
printf '%s\n' "$V" >&2
for m in http_ssl_module http_v2_module http_realip_module http_sub_module \
         http_auth_request_module http_stub_status_module pcre-jit; do
  assert_contains "$V" "--with-$m" "compiled with $m"
done
assert_contains "$V" "built with OpenSSL 3." "OpenSSL 3 statically linked"

clean_env "$NGINX" -p "$T/" -c conf/nginx.conf -e logs/error.log -t 2>&1 \
  | grep -q "test is successful" || smoke_fail "nginx -t failed"
smoke_ok "nginx -t"

clean_env "$NGINX" -p "$T/" -c conf/nginx.conf -e logs/error.log
wait_for_tcp "$HTTP_PORT" || { cat "$T/logs/error.log" >&2; smoke_fail "nginx did not start"; }
wait_for_tcp "$HTTPS_PORT" || smoke_fail "nginx TLS listener did not start"

BASE="http://127.0.0.1:$HTTP_PORT"
assert_contains "$(curl -fsS "$BASE/")" "burox-smoke-index" "HTTP 200 static file"
assert_contains "$(curl -fsS "$BASE/status")" "Active connections" "stub_status"
assert_contains "$(curl -fsS "$BASE/sub")" "replaced-ok" "sub_filter"
assert_contains "$(curl -fsS -H 'X-Forwarded-For: 10.1.2.3' "$BASE/ip")" "10.1.2.3" "realip"
assert_contains "$(curl -fsS "$BASE/protected/")" "burox-smoke-protected" "auth_request allow"
CODE="$(curl -s -o /dev/null -w '%{http_code}' "$BASE/denied/")"
[[ "$CODE" == "403" ]] || smoke_fail "auth_request deny: expected 403, got $CODE"
smoke_ok "auth_request deny"
assert_contains "$(curl -fsS "$BASE/re/camel")" "pcre:camel" "PCRE2 regex location"
F="$(curl -fsS "$BASE/test.php?x=1")"
assert_contains "$F" "fcgi-ok" "fastcgi_pass over unix socket"
assert_contains "$F" "SCRIPT_FILENAME=$T/html/test.php" "SCRIPT_FILENAME param"

TLS="$(curl -fsS -k --http2 -w ' proto=%{http_version}' "https://127.0.0.1:$HTTPS_PORT/")"
assert_contains "$TLS" "tls-ok" "HTTPS"
assert_contains "$TLS" "proto=2" "HTTP/2 over TLS"

clean_env "$NGINX" -p "$T/" -c conf/nginx.conf -e logs/error.log -s quit
for _ in $(seq 1 50); do
  [[ -f "$T/logs/nginx.pid" ]] || break
  sleep 0.2
done
[[ ! -f "$T/logs/nginx.pid" ]] || smoke_fail "nginx did not stop"
smoke_ok "graceful stop"
