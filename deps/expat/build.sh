#!/usr/bin/env bash
set -euo pipefail
# Expat XML parser (used by APR-util), static only.
./configure --prefix="$PREFIX" \
  --disable-shared --enable-static \
  --without-docbook --without-examples --without-tests --without-xmlwf
make -j"$JOBS"
make install DESTDIR="$DESTDIR"
