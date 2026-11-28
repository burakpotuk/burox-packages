#!/usr/bin/env bash
set -euo pipefail
# libsodium (sodium extension), static.
./configure --prefix="$PREFIX" --disable-shared --enable-static
make -j"$JOBS"
make install DESTDIR="$DESTDIR"
