#!/usr/bin/env bash
set -euo pipefail
# libxml2, static. iconv comes from /usr/lib/libiconv (allowed).
./configure --prefix="$PREFIX" \
  --disable-shared --enable-static \
  --with-zlib="$PREFIX" --without-lzma --without-python --without-icu \
  --without-readline --without-history --without-debug
make -j"$JOBS"
make install DESTDIR="$DESTDIR"
