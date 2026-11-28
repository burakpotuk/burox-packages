#!/usr/bin/env bash
set -euo pipefail
# GNU libintl (gettext extension), static. Only gettext-runtime is built; iconv
# is macOS' /usr/lib/libiconv. libintl uses CoreFoundation on macOS.
cd gettext-runtime
./configure --prefix="$PREFIX" --disable-shared --enable-static \
  --disable-java --disable-csharp --disable-libasprintf --disable-openmp \
  --with-included-gettext --without-emacs --without-git --without-cvs --without-bzip2 --without-xz
make -j"$JOBS" -C intl
make -C intl install DESTDIR="$DESTDIR"
