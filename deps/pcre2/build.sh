#!/usr/bin/env bash
set -euo pipefail
# PCRE2 (8-bit library only), static, with JIT.
./configure --prefix="$PREFIX" \
  --disable-shared --enable-static \
  --enable-pcre2-8 --disable-pcre2-16 --disable-pcre2-32 \
  --enable-jit \
  --disable-pcre2grep-libz --disable-pcre2grep-libbz2 --disable-pcre2test-libedit
make -j"$JOBS"
make install DESTDIR="$DESTDIR"
