#!/usr/bin/env bash
set -euo pipefail
# libwebp (gd), static, libraries only.
./configure --prefix="$PREFIX" --disable-shared --enable-static \
  --disable-gl --disable-sdl --disable-png --disable-jpeg --disable-tiff --disable-gif --disable-wic
make -j"$JOBS"
make install DESTDIR="$DESTDIR"
