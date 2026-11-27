#!/usr/bin/env bash
set -euo pipefail
# Apache Portable Runtime.
# Built shared+static on purpose: httpd (and apr-util) build their modules with
# the libtool script APR installs, and a static-only APR produces a libtool that
# cannot create .so modules. build-deps.sh deletes the dylibs afterwards and
# marks the .la files static-only, so everything still links APR statically.
./configure --prefix="$PREFIX" --enable-shared --enable-static
make -j"$JOBS"
make install DESTDIR="$DESTDIR"
