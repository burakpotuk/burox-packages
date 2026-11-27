#!/usr/bin/env bash
set -euo pipefail
# Smoke test for an unpacked Apache httpd package: smoke-test.sh <package-root>
# Loads every shipped module, config test, start on 127.0.0.1, then checks
# mod_rewrite (server config + .htaccess), headers, expires, deflate, remoteip,
# setenvif, mod_proxy and mod_proxy_fcgi over a unix socket, and stops.

# shellcheck source=../../scripts/lib/smoke.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/smoke.sh"
FCGI_ECHO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib" && pwd)/fcgi_echo.py"

PKG="$(cd "${1:?usage: smoke-test.sh <package-root>}" && pwd)"
HTTPD="$PKG/sbin/httpd"
[[ -x "$HTTPD" ]] || smoke_fail "missing $HTTPD"

T="$(mktemp -d /tmp/bxs-httpd.XXXXXX)"
FCGI_PID=""
cleanup() {
  if [[ -f "$T/run/httpd.pid" ]]; then
    kill -TERM "$(cat "$T/run/httpd.pid")" 2>/dev/null || true
    sleep 0.5
  fi
  [[ -n "$FCGI_PID" ]] && kill "$FCGI_PID" 2>/dev/null || true
  rm -rf "$T"
}
trap cleanup EXIT

PORT="$(free_port)"
mkdir -p "$T/run" "$T/logs" "$T/htdocs/sub"
echo "burox-apache-index" >"$T/htdocs/index.html"
echo "new-target" >"$T/htdocs/new.html"
echo "<?php // handled by the FastCGI echo backend" >"$T/htdocs/test.php"
printf '%s\n' 'RewriteEngine On' 'RewriteRule ^ht-old$ ht-new [R=302,L]' >"$T/htdocs/sub/.htaccess"
python3 -c 'print("x" * 4000)' >"$T/htdocs/big.txt"

FCGI_SOCK="$T/run/fcgi.sock"
python3 "$FCGI_ECHO" "$FCGI_SOCK" &
FCGI_PID=$!
disown "$FCGI_PID" 2>/dev/null || true

# Every module shipped, in the order httpd's own generated config lists them
# (it respects inter-module dependencies such as proxy before proxy_fcgi).
grep -Eo '^#?LoadModule[[:space:]]+[a-z0-9_]+[[:space:]]+lib/httpd/modules/mod_[a-z0-9_]+\.so' \
    "$PKG/etc-default/httpd.conf" | sed 's/^#//' | awk '!seen[$2]++' \
  | while read -r _ name path; do
      [[ -f "$PKG/$path" ]] && printf 'LoadModule %s %s\n' "$name" "$path"
    done >"$T/modules.conf"
for so in "$PKG"/lib/httpd/modules/mod_*.so; do
  grep -q "/$(basename "$so")\$" "$T/modules.conf" || smoke_fail "module not in reference config: $(basename "$so")"
done
smoke_ok "$(wc -l <"$T/modules.conf" | tr -d ' ') modules listed"

cat >"$T/httpd.conf" <<EOF
ServerRoot "$PKG"
Include "$T/modules.conf"
Listen 127.0.0.1:$PORT
ServerName 127.0.0.1:$PORT
DefaultRuntimeDir "$T/run"
PidFile "$T/run/httpd.pid"
ErrorLog "$T/logs/error.log"
LogLevel info
<IfModule cgid_module>
    ScriptSock "$T/run/cgisock"
</IfModule>
TypesConfig "$PKG/etc-default/mime.types"
LogFormat "%a %h \"%r\" %>s" smoke
CustomLog "$T/logs/access.log" smoke

DocumentRoot "$T/htdocs"
<Directory "$T/htdocs">
    AllowOverride All
    Require all granted
</Directory>
DirectoryIndex index.html

RemoteIPHeader X-Forwarded-For
RemoteIPInternalProxy 127.0.0.1
SetEnvIf X-Forwarded-Proto "^https\$" HTTPS=on

RewriteEngine On
RewriteRule "^/old\$" "/new.html" [R=301,L]

Header always set X-Burox-Smoke "ok"
Header always set X-Client-Ip "expr=%{REMOTE_ADDR}"
ExpiresActive On
ExpiresDefault "access plus 1 hour"
AddOutputFilterByType DEFLATE text/plain text/html

ProxyPass "/proxied/" "http://127.0.0.1:$PORT/"
<FilesMatch "\.php\$">
    SetHandler "proxy:unix:$FCGI_SOCK|fcgi://localhost"
</FilesMatch>
EOF

V="$(clean_env "$HTTPD" -V 2>&1)"
printf '%s\n' "$V" >&2
assert_contains "$V" "Server MPM:     event" "event MPM built in"
assert_contains "$V" "Apache/2.4." "httpd 2.4"

clean_env "$HTTPD" -d "$PKG" -f "$T/httpd.conf" -t 2>&1 | tee "$T/t.out" >&2
grep -q "Syntax OK" "$T/t.out" || smoke_fail "httpd -t failed"
smoke_ok "httpd -t with all modules loaded"

M="$(clean_env "$HTTPD" -d "$PKG" -f "$T/httpd.conf" -M 2>&1)"
for m in rewrite headers proxy proxy_fcgi remoteip setenvif expires deflate ssl; do
  assert_contains "$M" " ${m}_module (shared)" "module $m loads"
done

clean_env "$HTTPD" -d "$PKG" -f "$T/httpd.conf" -k start
wait_for_tcp "$PORT" || { cat "$T/logs/error.log" >&2; smoke_fail "httpd did not start"; }
BASE="http://127.0.0.1:$PORT"

assert_contains "$(curl -fsS "$BASE/")" "burox-apache-index" "HTTP 200 static file"

H="$(curl -sS -o /dev/null -D - "$BASE/old")"
assert_contains "$H" "301" "mod_rewrite redirect status"
assert_contains "$H" "Location: http://127.0.0.1:$PORT/new.html" "mod_rewrite redirect target"

H="$(curl -sS -o /dev/null -D - "$BASE/sub/ht-old")"
assert_contains "$H" "302" ".htaccess rewrite (AllowOverride All)"

H="$(curl -sS -o /dev/null -D - -H 'X-Forwarded-For: 10.9.8.7' "$BASE/")"
assert_contains "$H" "X-Burox-Smoke: ok" "mod_headers"
assert_contains "$H" "X-Client-Ip: 10.9.8.7" "mod_remoteip"
assert_contains "$H" "Expires:" "mod_expires"

H="$(curl -sS -o /dev/null -D - -H 'Accept-Encoding: gzip' "$BASE/big.txt")"
assert_contains "$H" "Content-Encoding: gzip" "mod_deflate"

assert_contains "$(curl -fsS "$BASE/proxied/index.html")" "burox-apache-index" "mod_proxy (http)"

F="$(curl -fsS -H 'X-Forwarded-Proto: https' "$BASE/test.php?x=1")"
assert_contains "$F" "fcgi-ok" "mod_proxy_fcgi over unix socket"
assert_contains "$F" "SCRIPT_FILENAME=" "FastCGI params passed"
assert_contains "$F" "HTTPS=on" "SetEnvIf X-Forwarded-Proto -> HTTPS=on"

clean_env "$HTTPD" -d "$PKG" -f "$T/httpd.conf" -k stop
for _ in $(seq 1 50); do
  [[ -f "$T/run/httpd.pid" ]] || break
  sleep 0.2
done
[[ ! -f "$T/run/httpd.pid" ]] || smoke_fail "httpd did not stop"
smoke_ok "stop"

for t in ab htpasswd rotatelogs; do
  [[ -x "$PKG/bin/$t" ]] || smoke_fail "missing bin/$t"
done
clean_env "$PKG/bin/htpasswd" -nbB smoke secret | grep -q '^smoke:\$2y\$' || smoke_fail "htpasswd"
smoke_ok "htpasswd (bcrypt)"
