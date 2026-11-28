#!/usr/bin/env bash
set -euo pipefail
# libpng (gd), static.
./configure --prefix="$PREFIX" --disable-shared --enable-static --with-zlib-prefix="$PREFIX" --disable-tools
make -j"$JOBS"
make install DESTDIR="$DESTDIR"
