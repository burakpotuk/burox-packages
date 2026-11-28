#!/usr/bin/env bash
set -euo pipefail
# libcurl for PHP 7.4/8.0: the last curl release that supports OpenSSL 1.1.1
# (support was removed in curl 8.18.0). Otherwise identical to deps/curl.
# pipe2() exists only on macOS 27+; newer SDKs declare it and this older curl
# would use it unguarded (caught by -Werror=unguarded-availability-new).
export ac_cv_func_pipe2=no
./configure --prefix="$PREFIX" --disable-shared --enable-static \
  --with-openssl="$PREFIX" --with-zlib="$PREFIX" \
  --with-ca-bundle=/private/etc/ssl/cert.pem --without-ca-path \
  --without-libpsl --without-brotli --without-zstd --without-nghttp2 --without-nghttp3 \
  --without-ngtcp2 --without-libidn2 --without-librtmp --without-libssh2 --without-libgsasl \
  --disable-ldap --disable-ldaps --disable-manual --disable-docs
make -j"$JOBS"
make install DESTDIR="$DESTDIR"
