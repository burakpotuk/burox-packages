#!/usr/bin/env bash
set -euo pipefail
# Apache httpd 2.4: event MPM built in, modules as shared objects (.so).
# APR, APR-util, PCRE2, OpenSSL, expat and zlib are linked statically.
#
# APR and APR-util are force-loaded *completely* into the httpd executable so
# that every APR symbol a module might need is exported from httpd; modules are
# linked with "-undefined dynamic_lookup" and resolve them at load time.
# Modules that need OpenSSL (mod_ssl) or zlib (mod_deflate) carry their own
# static copy.
#
# Burox always starts httpd with an explicit server root and config:
#   sbin/httpd -d <package-root> -f <httpd.conf>
# Modules live in lib/httpd/modules/ (LoadModule paths relative to ServerRoot).

COMPILED_PREFIX="/opt/burox/apache"

# Modules required by Burox (PLAN.md §3.1) — the build fails if one is missing.
REQUIRED_MODULES=(rewrite headers proxy proxy_fcgi remoteip setenvif expires deflate)

export HTTPD_LDFLAGS="-Wl,-force_load,$DEPS_PREFIX/lib/libapr-1.a -Wl,-force_load,$DEPS_PREFIX/lib/libaprutil-1.a"

./configure \
  --prefix="$COMPILED_PREFIX" \
  --with-apr="$DEPS_PREFIX/bin/apr-1-config" \
  --with-apr-util="$DEPS_PREFIX/bin/apu-1-config" \
  --with-pcre="$DEPS_PREFIX/bin/pcre2-config" \
  --with-ssl="$DEPS_PREFIX" \
  --with-z="$DEPS_PREFIX" \
  --with-mpm=event \
  --enable-so \
  --enable-mods-shared=most \
  --enable-ssl --enable-rewrite --enable-headers --enable-proxy --enable-proxy-fcgi \
  --enable-remoteip --enable-setenvif --enable-expires --enable-deflate \
  --disable-lua --disable-proxy-html --disable-xml2enc --disable-md \
  --disable-http2 --disable-proxy-http2 --disable-brotli \
  --disable-authnz-ldap --disable-ldap --disable-session-crypto --disable-socache-dc

make -j"$JOBS"
make install DESTDIR="$WORK_DIR/install"

INST="$WORK_DIR/install$COMPILED_PREFIX"
mkdir -p "$STAGE_DIR/sbin" "$STAGE_DIR/bin" "$STAGE_DIR/lib/httpd/modules" \
         "$STAGE_DIR/etc-default" "$STAGE_DIR/share/httpd" "$STAGE_DIR/share/licenses/apache"

cp "$INST/bin/httpd" "$STAGE_DIR/sbin/httpd"
# Standalone helpers only; apachectl/apxs/envvars are shell/perl scripts with
# hard-coded build paths and are not shipped.
for t in ab htpasswd htdigest htdbm rotatelogs logresolve httxt2dbm htcacheclean; do
  [[ -f "$INST/bin/$t" ]] && cp "$INST/bin/$t" "$STAGE_DIR/bin/$t"
done
cp "$INST/modules/"*.so "$STAGE_DIR/lib/httpd/modules/"

# Reference configuration. Module paths rewritten to the package layout.
sed -e "s|modules/|lib/httpd/modules/|g" "$INST/conf/httpd.conf" >"$STAGE_DIR/etc-default/httpd.conf"
cp "$INST/conf/mime.types" "$INST/conf/magic" "$STAGE_DIR/etc-default/"
cp -R "$INST/conf/extra" "$STAGE_DIR/etc-default/extra"
cp -R "$INST/error" "$INST/icons" "$STAGE_DIR/share/httpd/"
cp LICENSE NOTICE "$STAGE_DIR/share/licenses/apache/"

for m in "${REQUIRED_MODULES[@]}"; do
  [[ -f "$STAGE_DIR/lib/httpd/modules/mod_$m.so" ]] || { echo "required module mod_$m.so was not built" >&2; exit 1; }
done

MODS_JSON="$(find "$STAGE_DIR/lib/httpd/modules" -name 'mod_*.so' -exec basename {} \; \
            | sed -e 's/^mod_//' -e 's/\.so$//' | LC_ALL=C sort \
            | awk 'BEGIN{printf "["} {printf "%s\"%s\"", (NR>1?",":""), $0} END{printf "]"}')"
OPENSSL_VERSION="$(sed -n 's/^#[[:space:]]*define OPENSSL_FULL_VERSION_STR "\(.*\)"/\1/p' \
                   "$DEPS_PREFIX/include/openssl/opensslv.h")"
cat >"$WORK_DIR/meta.json" <<EOF
{
  "mpm": "event",
  "modules": $MODS_JSON,
  "modulesDir": "lib/httpd/modules",
  "openssl": "$OPENSSL_VERSION",
  "usage": "sbin/httpd -d <package-root> -f <httpd.conf>"
}
EOF
