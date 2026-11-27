#!/usr/bin/env bash
set -euo pipefail
# zlib, static only.
./configure --prefix="$PREFIX" --static
make -j"$JOBS" libz.a
make install DESTDIR="$DESTDIR"
