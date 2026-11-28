#!/usr/bin/env bash
set -euo pipefail
# Smoke test for an unpacked PHP package: smoke-test.sh <package-root>
#  - php -v, php -m against the expected built-in extension list
#  - every shared extension loads (-d extension= / -d zend_extension=)
#  - OPcache and Xdebug really active ("with Zend OPcache", "with Xdebug")
#  - phpize/php-config report the unpacked location (relocatable)
#  - php-fpm -t, then FPM on a unix socket answers a FastCGI request
#  - mini tests: openssl, pdo_sqlite, mbstring, intl (tr_TR), gd (PNG), curl to
#    https://example.com with an explicit CA bundle, zip, sodium, xsl, gmp

# shellcheck source=../../scripts/lib/smoke.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/smoke.sh"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "${1:?usage: smoke-test.sh <package-root>}" && pwd)"
PHP="$PKG/bin/php"
FPM="$PKG/sbin/php-fpm"
EXT="$PKG/lib/php/extensions"
[[ -x "$PHP" && -x "$FPM" ]] || smoke_fail "missing bin/php or sbin/php-fpm"

BRANCH="$(jq -r .meta.branch "$PKG/PACKAGE.json")"
VERSION="$(jq -r .upstreamVersion "$PKG/PACKAGE.json")"
php() { clean_env "$PHP" -n -d "extension_dir=$EXT" "$@"; }

T="$(mktemp -d /tmp/bxs-php.XXXXXX)"
cleanup() {
  [[ -f "$T/fpm.pid" ]] && kill -QUIT "$(cat "$T/fpm.pid")" 2>/dev/null || true
  sleep 0.3
  rm -rf "$T"
}
trap cleanup EXIT

V="$(php -v)"
assert_contains "$V" "PHP $VERSION" "php -v reports $VERSION"

# --- built-in extensions ---------------------------------------------------------------
EXPECTED_BUILTIN=(bcmath bz2 calendar ctype curl date dom exif fileinfo filter ftp gd gettext gmp hash
                  iconv intl json libxml mbstring mysqli mysqlnd openssl pcntl pcre pdo pdo_mysql
                  pdo_sqlite phar posix random readline reflection session simplexml soap sockets
                  sodium spl sqlite3 standard tokenizer xml xmlreader xmlwriter xsl zip zlib)
MODS="$(php -m | tr '[:upper:]' '[:lower:]')"
for m in "${EXPECTED_BUILTIN[@]}"; do
  # random became a separate extension in 8.2
  if [[ "$m" == "random" ]] && ! printf '%s\n8.2\n' "$BRANCH" | sort -V | head -n1 | grep -qx 8.2; then continue; fi
  grep -qx "$m" <<<"$MODS" || smoke_fail "built-in extension missing: $m"
done
smoke_ok "${#EXPECTED_BUILTIN[@]} built-in extensions present"

# --- shared extensions ---------------------------------------------------------------
SHARED="$(jq -r '.meta.sharedExtensions[]' "$PKG/PACKAGE.json")"
for so in "$EXT"/*.so; do
  name="$(basename "$so" .so)"
  grep -qx "$name" <<<"$SHARED" || smoke_fail "$name.so not listed in PACKAGE.json sharedExtensions"
  case "$name" in
    opcache|xdebug) directive="zend_extension" ;;
    *) directive="extension" ;;
  esac
  # Load prerequisites first (redis/memcached need igbinary's symbols).
  pre=()
  for req in $(jq -r --arg n "$name" '.meta.sharedExtensionRequires[$n] // [] | .[]' "$PKG/PACKAGE.json"); do
    pre+=(-d "extension=$EXT/$req.so")
  done
  out="$(php ${pre[@]+"${pre[@]}"} -d "$directive=$so" -m 2>&1)"
  if grep -qiE 'warning|unable to load|failed loading|cannot load' <<<"$out"; then
    printf '%s\n' "$out" >&2
    smoke_fail "$name.so does not load"
  fi
  smoke_ok "shared $name loads"
done

# OPcache: zend_extension up to 8.4, built in since 8.5.
if [[ -f "$EXT/opcache.so" ]]; then
  OV="$(php -d "zend_extension=$EXT/opcache.so" -d opcache.enable_cli=1 -v)"
else
  OV="$(php -d opcache.enable_cli=1 -v)"
fi
assert_contains "$OV" "with Zend OPcache" "OPcache active"
if [[ -f "$EXT/xdebug.so" ]]; then
  XV="$(php -d "zend_extension=$EXT/xdebug.so" -v)"
  assert_contains "$XV" "with Xdebug" "Xdebug active"
fi

# --- phpize / php-config are relocatable ---------------------------------------------------
assert_contains "$(clean_env "$PKG/bin/php-config" --extension-dir)" "$PKG/lib/php/extensions" "php-config --extension-dir"
assert_contains "$(clean_env "$PKG/bin/php-config" --include-dir)" "$PKG/include/php" "php-config --include-dir"
[[ -f "$PKG/include/php/main/php.h" ]] || smoke_fail "headers missing"
[[ -f "$PKG/lib/php/build/phpize.m4" ]] || smoke_fail "phpize build files missing"
smoke_ok "phpize support files present"

# --- mini functional tests ----------------------------------------------------------------
R="$(php -r 'echo strlen(openssl_random_pseudo_bytes(32)), "|", OPENSSL_VERSION_TEXT;')"
assert_contains "$R" "32|OpenSSL" "openssl_random_pseudo_bytes"
R="$(php -r '$d = new PDO("sqlite::memory:"); $d->exec("create table t(x)"); $d->exec("insert into t values (42)"); echo $d->query("select x from t")->fetchColumn();')"
assert_contains "$R" "42" "pdo_sqlite"
# mb_ereg_* is deprecated in 8.6 (oniguruma is unmaintained) but still built.
R="$(php -d error_reporting=0 -r 'echo mb_strtoupper("çğış"), "|", mb_ereg_replace("ğ+", "g", "dağğ");')"
assert_contains "$R" "ÇĞIŞ|dag" "mbstring + oniguruma"
R="$(php -r '$x = new DOMDocument(); $x->loadXML("<a><b>ok</b></a>"); echo $x->getElementsByTagName("b")->item(0)->textContent;')"
assert_contains "$R" "ok" "dom/libxml"
R="$(php -r '$f = new NumberFormatter("tr_TR", NumberFormatter::DECIMAL); echo $f->format(1234567.891), "|", INTL_ICU_VERSION;')"
assert_contains "$R" "1.234.567,891|" "intl NumberFormatter tr_TR"
R="$(php -r '$i = imagecreatetruecolor(8, 8); imagefilledrectangle($i, 0, 0, 7, 7, imagecolorallocate($i, 200, 160, 90)); ob_start(); imagepng($i); $p = ob_get_clean(); $g = gd_info(); echo bin2hex(substr($p, 1, 3)), "|", (int)$g["FreeType Support"], (int)$g["JPEG Support"], (int)$g["PNG Support"], (int)$g["WebP Support"];')"
assert_contains "$R" "504e47|1111" "gd PNG + freetype/jpeg/png/webp"
# Mozilla CA bundle, as Burox itself uses (PLAN §3.4). macOS' /etc/ssl/cert.pem
# is incomplete (e.g. lacks the SSL.com 2022 roots that example.com chains to).
curl -fsSL --retry 3 -o "$T/cacert.pem" https://curl.se/ca/cacert.pem || smoke_fail "could not fetch Mozilla CA bundle"
R="$(php -r '$c = curl_init("https://example.com/"); curl_setopt_array($c, [CURLOPT_RETURNTRANSFER => true, CURLOPT_CAINFO => $argv[1], CURLOPT_TIMEOUT => 20]); $b = curl_exec($c); echo curl_getinfo($c, CURLINFO_RESPONSE_CODE), "|", curl_version()["ssl_version"], "|", strlen((string)$b) > 0 ? "body" : curl_error($c);' "$T/cacert.pem")"
assert_contains "$R" "200|OpenSSL" "curl https://example.com with CA bundle"
R="$(php -r '$z = new ZipArchive(); $f = sys_get_temp_dir() . "/burox-smoke-" . getmypid() . ".zip"; $z->open($f, ZipArchive::CREATE); $z->addFromString("a.txt", "zip-ok"); $z->close(); $z->open($f); echo $z->getFromName("a.txt"); unlink($f);')"
assert_contains "$R" "zip-ok" "zip"
R="$(php -r '$k = sodium_crypto_secretbox_keygen(); $n = random_bytes(SODIUM_CRYPTO_SECRETBOX_NONCEBYTES); echo sodium_crypto_secretbox_open(sodium_crypto_secretbox("sodium-ok", $n, $k), $n, $k);')"
assert_contains "$R" "sodium-ok" "sodium"
R="$(php -r '$x = new XSLTProcessor(); $x->importStylesheet(simplexml_load_string("<xsl:stylesheet version=\"1.0\" xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\"><xsl:output method=\"text\"/><xsl:template match=\"/\">xsl-<xsl:value-of select=\"/a\"/></xsl:template></xsl:stylesheet>")); echo $x->transformToXml(simplexml_load_string("<a>ok</a>"));')"
assert_contains "$R" "xsl-ok" "xsl"
R="$(php -r 'echo gmp_strval(gmp_pow(2, 100));')"
assert_contains "$R" "1267650600228229401496703205376" "gmp"
R="$(php -d extension="$EXT/apcu.so" -d apc.enable_cli=1 -r 'apcu_store("k", "apcu-ok"); echo apcu_fetch("k");')"
assert_contains "$R" "apcu-ok" "apcu store/fetch"
R="$(php -d extension="$EXT/igbinary.so" -d extension="$EXT/redis.so" -r 'echo igbinary_unserialize(igbinary_serialize(["igb" => "ok"]))["igb"], "|", defined("Redis::SERIALIZER_IGBINARY") ? "redis-igbinary" : "no", "|", defined("Redis::COMPRESSION_ZSTD") ? "redis-zstd" : "no";')"
assert_contains "$R" "ok|redis-igbinary|redis-zstd" "igbinary + redis (igbinary, zstd)"
R="$(php -d extension="$EXT/igbinary.so" -d extension="$EXT/memcached.so" -r 'echo Memcached::HAVE_IGBINARY ? "mc-igbinary" : "no", "|", Memcached::HAVE_JSON ? "mc-json" : "no";')"
assert_contains "$R" "mc-igbinary|mc-json" "memcached (igbinary, json)"

# --- php-fpm ----------------------------------------------------------------------------
mkdir -p "$T/www"
cat >"$T/www/index.php" <<'PHPEOF'
<?php
header('X-Smoke: fpm');
echo 'fpm-ok ', PHP_SAPI, ' ', PHP_VERSION, ' q=', $_GET['q'] ?? '';
PHPEOF
cat >"$T/fpm.conf" <<EOF
[global]
pid = $T/fpm.pid
error_log = $T/fpm.log
daemonize = yes
[smoke]
listen = $T/fpm.sock
listen.mode = 0600
pm = ondemand
pm.max_children = 2
catch_workers_output = yes
EOF
clean_env "$FPM" -n -t -y "$T/fpm.conf" 2>&1 | tee "$T/t.out" >&2
grep -q "test is successful" "$T/t.out" || smoke_fail "php-fpm -t failed"
smoke_ok "php-fpm -t"

clean_env "$FPM" -n -y "$T/fpm.conf"
for _ in $(seq 1 50); do [[ -S "$T/fpm.sock" ]] && break; sleep 0.1; done
[[ -S "$T/fpm.sock" ]] || { cat "$T/fpm.log" >&2; smoke_fail "php-fpm did not create its socket"; }
RESP="$(php "$HERE/fcgi-client.php" "$T/fpm.sock" "$T/www/index.php" "q=camel")"
assert_contains "$RESP" "X-Smoke: fpm" "FPM response header"
assert_contains "$RESP" "fpm-ok fpm-fcgi $VERSION q=camel" "FPM executes PHP over FastCGI"
kill -QUIT "$(cat "$T/fpm.pid")"
for _ in $(seq 1 50); do [[ -f "$T/fpm.pid" ]] || break; sleep 0.1; done
smoke_ok "php-fpm stopped"
