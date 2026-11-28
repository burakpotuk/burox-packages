#!/usr/bin/env bash
set -euo pipefail
# libjpeg-turbo (gd), static, libjpeg API only.
cmake -S . -B _build -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_INSTALL_LIBDIR=lib \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DWITH_TURBOJPEG=OFF -DWITH_TOOLS=OFF -DWITH_TESTS=OFF
cmake --build _build -j"$JOBS"
DESTDIR="$DESTDIR" cmake --install _build
