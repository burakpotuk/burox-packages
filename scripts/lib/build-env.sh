#!/usr/bin/env bash
# shellcheck shell=bash
# Compiler/linker environment shared by every source build (deps and packages).
# Changing this file invalidates every cached dependency build.
#
# Expects DEPS_PREFIX to be set (may point to an empty directory).

: "${DEPS_PREFIX:?DEPS_PREFIX must be set before sourcing build-env.sh}"

export MACOSX_DEPLOYMENT_TARGET="14.0"
export CC="clang"
export CXX="clang++"

# -Werror=unguarded-availability-new: if a configure script detects a libc/API
# function that only exists in a newer macOS than our deployment target
# (e.g. strchrnul from the 15.4 SDK), the real compile fails loudly instead of
# producing a binary that crashes on macOS 14 with "Symbol not found".
BUROX_ARCH_FLAGS="-arch arm64 -mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET}"
export CFLAGS="${BUROX_ARCH_FLAGS} -O2 -Werror=unguarded-availability-new"
export CXXFLAGS="${CFLAGS}"
export CPPFLAGS="-I${DEPS_PREFIX}/include"
export LDFLAGS="${BUROX_ARCH_FLAGS} -L${DEPS_PREFIX}/lib"

# Only ever see our own static deps; never Homebrew/MacPorts/system .pc files.
export PKG_CONFIG_LIBDIR="${DEPS_PREFIX}/lib/pkgconfig:${DEPS_PREFIX}/share/pkgconfig"
export PKG_CONFIG_PATH=""
unset LIBRARY_PATH CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH DYLD_LIBRARY_PATH DYLD_FALLBACK_LIBRARY_PATH

# Keep Homebrew tools (pcre2-config, xml2-config, ...) out of configure's PATH lookups.
BUROX_CLEAN_PATH="${DEPS_PREFIX}/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH="${BUROX_CLEAN_PATH}"

export JOBS="${JOBS:-$( (sysctl -n hw.ncpu 2>/dev/null || echo 4) )}"
