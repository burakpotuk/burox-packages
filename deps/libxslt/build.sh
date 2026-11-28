#!/usr/bin/env bash
set -euo pipefail
# libxslt (xsl extension), static, against our static libxml2.
./configure --prefix="$PREFIX" --disable-shared --enable-static \
  --without-python --without-crypto --without-debug --with-libxml-prefix="$PREFIX"
make -j"$JOBS"
make install DESTDIR="$DESTDIR"
