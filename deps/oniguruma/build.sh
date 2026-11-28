#!/usr/bin/env bash
set -euo pipefail
# Oniguruma (mbstring's regex engine), static.
./configure --prefix="$PREFIX" --disable-shared --enable-static
make -j"$JOBS"
make install DESTDIR="$DESTDIR"
