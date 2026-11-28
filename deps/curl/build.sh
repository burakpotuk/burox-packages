#!/usr/bin/env bash
set -euo pipefail
# libcurl (curl extension), static, OpenSSL 3 + zlib. Default CA bundle is
# macOS' /private/etc/ssl/cert.pem; Burox sets curl.cainfo explicitly anyway.
./configure --prefix="$PREFIX" --disable-shared --enable-static \
  --with-openssl="$PREFIX" --with-zlib="$PREFIX" \
  --with-ca-bundle=/private/etc/ssl/cert.pem --without-ca-path \
  --without-libpsl --without-brotli --without-zstd --without-nghttp2 --without-nghttp3 \
  --without-ngtcp2 --without-libidn2 --without-librtmp --without-libssh2 --without-libgsasl \
  --disable-ldap --disable-ldaps --disable-manual --disable-docs
make -j"$JOBS"
make install DESTDIR="$DESTDIR"
