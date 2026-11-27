#!/usr/bin/env bash
set -euo pipefail
# APR-util, static only. No database/LDAP/crypto drivers: httpd does not need
# them and they would pull in more shared libraries. iconv comes from
# /usr/lib/libiconv (allowed by the portability rule).
./configure --prefix="$PREFIX" \
  --with-apr="$PREFIX/bin/apr-1-config" \
  --with-expat="$PREFIX" \
  --disable-util-dso \
  --without-ldap --without-pgsql --without-mysql --without-sqlite2 --without-sqlite3 \
  --without-oracle --without-odbc --without-freetds --without-berkeley-db \
  --without-gdbm --without-ndbm --without-crypto --without-openssl --without-nss \
  --without-commoncrypto
make -j"$JOBS"
make install DESTDIR="$DESTDIR"
