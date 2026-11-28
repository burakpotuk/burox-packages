#!/usr/bin/env bash
set -euo pipefail
# FreeType (gd), static, zlib only (no png/bzip2/brotli/harfbuzz).
./configure --prefix="$PREFIX" --disable-shared --enable-static \
  --with-zlib=yes --without-png --without-bzip2 --without-brotli --without-harfbuzz
make -j"$JOBS"
make install DESTDIR="$DESTDIR"
