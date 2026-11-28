#!/usr/bin/env bash
set -euo pipefail
# Zstandard (libzip, redis compression), static library only (CMake build; the
# plain Makefile mangles "-arch arm64" in CFLAGS).
cmake -S build/cmake -B _build -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_INSTALL_LIBDIR=lib \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DZSTD_BUILD_SHARED=OFF -DZSTD_BUILD_STATIC=ON -DZSTD_BUILD_PROGRAMS=OFF \
  -DZSTD_BUILD_TESTS=OFF -DZSTD_BUILD_CONTRIB=OFF -DZSTD_LEGACY_SUPPORT=OFF
cmake --build _build -j"$JOBS"
DESTDIR="$DESTDIR" cmake --install _build
