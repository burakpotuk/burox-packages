#!/usr/bin/env bash
set -euo pipefail
# OpenSSL 1.1.1 (end of life upstream) — only for PHP 7.4 and 8.0, which do not
# build against OpenSSL 3. Static only. Packages using it are marked EOL.
./Configure darwin64-arm64-cc \
  --prefix="$PREFIX" --libdir=lib \
  --openssldir=/private/etc/ssl \
  no-shared no-tests \
  "-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"
make -j"$JOBS" build_libs
make install_dev DESTDIR="$DESTDIR"
