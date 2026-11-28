#!/usr/bin/env bash
set -euo pipefail
# SQLite amalgamation, static. Column metadata is needed by pdo_sqlite.
# SQLite is public domain and ships no license file; its dedication (the head of
# sqlite3.h) is saved as PUBLIC-DOMAIN.txt and shipped like a license.
sed -n '1,/^\*\*\*\*\*\*\*\*/p' sqlite3.h >PUBLIC-DOMAIN.txt
export CFLAGS="$CFLAGS -DSQLITE_ENABLE_COLUMN_METADATA=1 -DSQLITE_ENABLE_FTS5=1 -DSQLITE_ENABLE_RTREE=1 -DSQLITE_ENABLE_MATH_FUNCTIONS=1"
./configure --prefix="$PREFIX" --disable-shared --enable-static --disable-readline
make -j"$JOBS"
make install DESTDIR="$DESTDIR"
