#!/usr/bin/env bash
set -euo pipefail
# ICU (intl), static, with the full locale data compiled into libicudata.a.
cd source
./runConfigureICU MacOSX --prefix="$PREFIX" \
  --enable-static --disable-shared --with-data-packaging=static \
  --disable-samples --disable-tests --disable-extras
make -j"$JOBS"
make install DESTDIR="$DESTDIR"
