#!/usr/bin/env bash
set -euo pipefail
# GMP (gmp extension), static.
./configure --prefix="$PREFIX" --disable-shared --enable-static --with-pic
make -j"$JOBS"
make install DESTDIR="$DESTDIR"
