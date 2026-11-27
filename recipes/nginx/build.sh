#!/usr/bin/env bash
set -euo pipefail
# nginx (stable) with OpenSSL 3, PCRE2 and zlib linked statically.
#
# Relocatability: all compiled-in paths are relative to the prefix, and Burox
# always starts nginx with an explicit prefix, config and startup error log:
#   sbin/nginx -p <runtime-prefix>/ -c <nginx.conf> -e <error.log>
# The compiled-in --prefix below is never expected to exist.

COMPILED_PREFIX="/opt/burox/nginx"
MODULES=(
  --with-http_ssl_module
  --with-http_v2_module
  --with-http_realip_module
  --with-http_sub_module
  --with-http_auth_request_module
  --with-http_stub_status_module
)

./configure \
  --prefix="$COMPILED_PREFIX" \
  --sbin-path=sbin/nginx \
  --conf-path=conf/nginx.conf \
  --error-log-path=logs/error.log \
  --http-log-path=logs/access.log \
  --pid-path=logs/nginx.pid \
  --lock-path=logs/nginx.lock \
  --http-client-body-temp-path=temp/client_body \
  --http-proxy-temp-path=temp/proxy \
  --http-fastcgi-temp-path=temp/fastcgi \
  --http-uwsgi-temp-path=temp/uwsgi \
  --http-scgi-temp-path=temp/scgi \
  --with-cc-opt="$CPPFLAGS" \
  --with-ld-opt="$LDFLAGS" \
  --with-threads \
  --with-pcre --with-pcre-jit \
  "${MODULES[@]}"

make -j"$JOBS"
make install DESTDIR="$WORK_DIR/install"

INST="$WORK_DIR/install$COMPILED_PREFIX"
mkdir -p "$STAGE_DIR/sbin" "$STAGE_DIR/etc-default" "$STAGE_DIR/share/nginx/html" \
         "$STAGE_DIR/share/licenses/nginx"
cp "$INST/sbin/nginx" "$STAGE_DIR/sbin/nginx"
for f in nginx.conf mime.types fastcgi.conf fastcgi_params scgi_params uwsgi_params; do
  cp "$INST/conf/$f" "$STAGE_DIR/etc-default/$f"
done
cp "$INST/html/"*.html "$STAGE_DIR/share/nginx/html/"
cp LICENSE "$STAGE_DIR/share/licenses/nginx/"

# Module list for PACKAGE.json / manifest meta: "--with-http_ssl_module" -> "http_ssl".
MODS_JSON="$(printf '%s\n' "${MODULES[@]}" | sed -e 's/^--with-//' -e 's/_module$//' \
            | awk 'BEGIN{printf "["} {printf "%s\"%s\"", (NR>1?",":""), $0} END{printf "]"}')"
OPENSSL_VERSION="$(sed -n 's/^#[[:space:]]*define OPENSSL_FULL_VERSION_STR "\(.*\)"/\1/p' \
                   "$DEPS_PREFIX/include/openssl/opensslv.h")"
cat >"$WORK_DIR/meta.json" <<EOF
{
  "modules": $MODS_JSON,
  "openssl": "$OPENSSL_VERSION",
  "usage": "sbin/nginx -p <prefix>/ -c <nginx.conf> -e <error.log>"
}
EOF
