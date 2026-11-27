#!/usr/bin/env bash
set -euo pipefail
# OpenSSL 3 LTS, static libraries only.
#  - no-module: providers (incl. legacy) are built into libcrypto, so nothing
#    is dlopen()ed from a compiled-in path at runtime.
#  - openssldir=/private/etc/ssl: macOS' own CA bundle (cert.pem) becomes the
#    default trust store; Burox normally sets CA paths explicitly anyway.
./Configure darwin64-arm64-cc \
  --prefix="$PREFIX" --libdir=lib \
  --openssldir=/private/etc/ssl \
  no-shared no-module no-tests \
  "-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"
make -j"$JOBS" build_libs
make install_dev DESTDIR="$DESTDIR"
