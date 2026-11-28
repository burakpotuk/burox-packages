#!/usr/bin/env bash
set -euo pipefail
# PHP (CLI + FPM) with statically linked dependencies and *shared* extensions.
#
#  1. ./configure + make against the static libraries in $DEPS_PREFIX
#  2. make install into a staging root (compiled prefix /opt/burox/php is never used
#     at runtime; Burox passes -c / PHPRC / PHP_INI_SCAN_DIR and extension_dir)
#  3. every PECL extension from "extras" is built with *this* PHP's phpize, so
#     the .so files match the binary's API and resolve PHP symbols from it
#  4. phpize/php-config are rewritten to find their prefix at runtime
#
# Layout: bin/php bin/phpize bin/php-config sbin/php-fpm
#         lib/php/extensions/*.so  lib/php/build/  include/php/
#         etc-default/php.ini-{development,production} php-fpm.conf.default php-fpm.d/

COMPILED_PREFIX="/opt/burox/php"
MAJOR_MINOR="$(printf '%s' "$PKG_VERSION" | cut -d. -f1-2)"
ver_ge() { [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" == "$2" ]]; }
SDK="$(xcrun --show-sdk-path)"

# Same C dialect everywhere: newer Xcode defaults to C23, where "f()" means
# "no arguments" and breaks older PHP/PECL code; CI's Xcode 16 uses gnu17.
# C++: ICU >= 75 headers need C++17. Xcode 16's clang defaults to C++14 and
# PHP < 8.1 does not ask for a standard at all.
export CFLAGS="$CFLAGS -std=gnu17"
export CXXFLAGS="$CXXFLAGS -std=gnu++17"

# PHP's configure probes with -Werror-free tests; old branches trip over newer
# clang defaults (implicit declarations / incompatible pointer types are errors).
if ! ver_ge "$MAJOR_MINOR" "8.1"; then
  export CFLAGS="$CFLAGS -Wno-error=implicit-function-declaration -Wno-error=incompatible-function-pointer-types -Wno-error=int-conversion"
  # libxml2 >= 2.14 dropped ATTRIBUTE_UNUSED; PHP < 8.1 still uses it in ext/libxml.
  printf '#ifndef ATTRIBUTE_UNUSED\n#define ATTRIBUTE_UNUSED __attribute__((unused))\n#endif\n' \
    >"$WORK_DIR/burox-compat.h"
  export CFLAGS="$CFLAGS -include $WORK_DIR/burox-compat.h"
fi

# dns_get_record() & co. use res_9_* from /usr/lib/libresolv (allowed); old
# branches' configure checks find dn_expand in libSystem and forget -lresolv.
# GNU libintl (gettext) and libcurl (system proxy settings) use macOS frameworks
# (/System/Library/Frameworks, allowed); PHP's configure drops "-framework X" from
# pkg-config output, so name them here.
export LIBS="${LIBS:-} -lresolv -framework CoreFoundation -framework CoreServices -framework SystemConfiguration"

# readline extension uses macOS' own libedit (/usr/lib/libedit.3.dylib). PHP >= 8.0
# looks it up with pkg-config, so describe the system library in a private .pc.
mkdir -p "$WORK_DIR/pkgconfig"
cat >"$WORK_DIR/pkgconfig/libedit.pc" <<PC
Name: libedit
Description: macOS system libedit
Version: 3.0
Libs: -ledit
Cflags:
PC
export PKG_CONFIG_LIBDIR="$PKG_CONFIG_LIBDIR:$WORK_DIR/pkgconfig"

# ...and PHP 8.1's intl explicitly asks for C++11, which would override it.
if ! ver_ge "$MAJOR_MINOR" "8.2"; then
  sed -i.bak -e 's/-std=c++11/-std=c++17/g' -e 's/-std=gnu++11/-std=gnu++17/g' configure
fi

OPTS=(
  --prefix="$COMPILED_PREFIX"
  --disable-rpath
  --disable-cgi --disable-phpdbg
  --enable-cli --enable-fpm
  --with-openssl
  --with-external-pcre
  --with-zlib
  --with-bz2="$SDK/usr"
  --with-iconv="$SDK/usr"
  --with-curl
  --enable-gd --with-freetype --with-jpeg --with-webp
  --with-gettext="$DEPS_PREFIX"
  --with-gmp="$DEPS_PREFIX"
  --enable-intl
  --enable-mbstring
  --with-sqlite3 --with-pdo-sqlite
  --enable-mysqlnd --with-mysqli --with-pdo-mysql
  --with-libedit
  --with-sodium
  --with-xsl
  --with-zip
  --enable-bcmath --enable-calendar --enable-exif --enable-ftp --enable-pcntl
  --enable-soap --enable-sockets
)
# OPcache: shared zend_extension up to 8.4, always built in since 8.5.
if ! ver_ge "$MAJOR_MINOR" "8.5"; then
  OPTS+=(--enable-opcache)
fi

if ! ./configure "${OPTS[@]}"; then
  echo "---- last lines of config.log ----" >&2
  tail -n 150 config.log >&2
  exit 1
fi
# php/php-fpm are plugin hosts: extensions resolve PHP's API from them at load
# time. Newer Apple linkers drop globals the binary itself never calls unless
# -export_dynamic is given (verify-plugin-symbols.sh guards this).
sed -i.bak 's/^EXTRA_LDFLAGS_PROGRAM = /EXTRA_LDFLAGS_PROGRAM = -Wl,-export_dynamic /' Makefile
make -j"$JOBS"
make install INSTALL_ROOT="$WORK_DIR/install"

INST="$WORK_DIR/install$COMPILED_PREFIX"
# e.g. /opt/burox/php/lib/php/extensions/no-debug-non-zts-20250925 (may not exist yet
# when no extension is shared, as with 8.5+ where OPcache is built in).
EXT_COMPILED="$("$INST/bin/php" -n -r 'echo PHP_EXTENSION_DIR;')"
EXT_SRC_DIR="$INST${EXT_COMPILED#"$COMPILED_PREFIX"}"
mkdir -p "$EXT_SRC_DIR"

# --- PECL extensions via this build's phpize ----------------------------------------
# Temporary phpize/php-config that point at the staging install.
mkdir -p "$WORK_DIR/phpize-tools"
sed "s|$COMPILED_PREFIX|$INST|g" "$INST/bin/php-config" >"$WORK_DIR/phpize-tools/php-config"
sed "s|$COMPILED_PREFIX|$INST|g" "$INST/bin/phpize" >"$WORK_DIR/phpize-tools/phpize"
chmod +x "$WORK_DIR/phpize-tools/"*

# Order matters: igbinary's headers must be installed before redis/memcached
# are configured with igbinary support.
pecl_opts() {
  case "$1" in
    redis) echo "--enable-redis --enable-redis-igbinary --enable-redis-lzf --enable-redis-zstd --with-libzstd=$DEPS_PREFIX" ;;
    memcached) echo "--enable-memcached --with-libmemcached-dir=$DEPS_PREFIX --with-zlib-dir=$DEPS_PREFIX --disable-memcached-sasl --enable-memcached-igbinary --enable-memcached-json --enable-memcached-session" ;;
    *) echo "" ;;
  esac
}
SHARED_EXTS=()
for name in igbinary apcu redis memcached xdebug; do
  extdir="$EXTRAS_DIR/$name"
  [[ -d "$extdir" ]] || continue
  (
    cd "$extdir"
    "$WORK_DIR/phpize-tools/phpize"
    # shellcheck disable=SC2046
    ./configure --with-php-config="$WORK_DIR/phpize-tools/php-config" $(pecl_opts "$name")
    # libmemcached-awesome is C++ and ships libhashkit separately: link both
    # (static) plus the C++ runtime (/usr/lib/libc++) into memcached.so.
    if [[ "$name" == "memcached" ]]; then
      make -j"$JOBS" EXTRA_LDFLAGS="-L$DEPS_PREFIX/lib -lhashkit -lc++"
    else
      make -j"$JOBS"
    fi
    make install   # into the staging install: .so + headers (igbinary.h for later exts)
  )
  # phpize's libtool adds the deps prefix as LC_RPATH; nothing is loaded from it
  # (every dependency is static), so drop it to keep the module relocatable.
  otool -l "$EXT_SRC_DIR/$name.so" | awk '$1 == "cmd" && $2 == "LC_RPATH" {getline; getline; print $2}' \
    | while IFS= read -r rp; do install_name_tool -delete_rpath "$rp" "$EXT_SRC_DIR/$name.so"; done
  SHARED_EXTS+=("$name")
done

# --- stage ----------------------------------------------------------------------------
mkdir -p "$STAGE_DIR/bin" "$STAGE_DIR/sbin" "$STAGE_DIR/lib/php/extensions" "$STAGE_DIR/include" \
         "$STAGE_DIR/etc-default/php-fpm.d" "$STAGE_DIR/share/licenses/php"
cp "$INST/bin/php" "$STAGE_DIR/bin/php"
cp "$INST/sbin/php-fpm" "$STAGE_DIR/sbin/php-fpm"
cp "$EXT_SRC_DIR"/*.so "$STAGE_DIR/lib/php/extensions/" 2>/dev/null || true
cp -R "$INST/lib/php/build" "$STAGE_DIR/lib/php/build"
cp -R "$INST/include/php" "$STAGE_DIR/include/php"

# Relocatable phpize/php-config: prefix = <dir of script>/.., extension dir flattened.
EXT_API_DIR="${EXT_SRC_DIR#"$INST"/}"
for tool in php-config phpize; do
  sed -e "s|$COMPILED_PREFIX/$EXT_API_DIR|$COMPILED_PREFIX/lib/php/extensions|g" \
      -e "s|-L$DEPS_PREFIX/lib||g" -e "s|-I$DEPS_PREFIX/include||g" \
      -e "s|^prefix=.*|prefix=\"\$(cd \"\$(dirname \"\$0\")/..\" \&\& pwd)\"|" \
      -e "s|$COMPILED_PREFIX|\${prefix}|g" \
      -e "/\${prefix}/ s/='\(.*\)'\$/=\"\1\"/" \
      "$INST/bin/$tool" >"$STAGE_DIR/bin/$tool"
  chmod 0755 "$STAGE_DIR/bin/$tool"
done

cp php.ini-development php.ini-production "$STAGE_DIR/etc-default/"
cp "$INST/etc/php-fpm.conf.default" "$STAGE_DIR/etc-default/"
cp "$INST/etc/php-fpm.d/www.conf.default" "$STAGE_DIR/etc-default/php-fpm.d/"
cp LICENSE "$STAGE_DIR/share/licenses/php/" 2>/dev/null || cp LICENSE* "$STAGE_DIR/share/licenses/php/"
for name in ${SHARED_EXTS[@]+"${SHARED_EXTS[@]}"}; do
  extdir="$EXTRAS_DIR/$name"
  mkdir -p "$STAGE_DIR/share/licenses/$name"
  cp "$extdir"/LICENSE* "$STAGE_DIR/share/licenses/$name/" 2>/dev/null \
    || cp "$extdir"/COPYING* "$STAGE_DIR/share/licenses/$name/"
done

# --- metadata (package.sh adds "eol"/"securityNote" from versions.json) --------------
PHP="$STAGE_DIR/bin/php"
BUILTIN_JSON="$("$PHP" -n -r 'echo json_encode(array_values(array_map("strtolower", get_loaded_extensions())));')"
ZEND_JSON="$("$PHP" -n -r 'echo json_encode(array_values(array_map("strtolower", get_loaded_extensions(true))));')"
SHARED_LIST=()
for so in "$STAGE_DIR"/lib/php/extensions/*.so; do
  [[ -e "$so" ]] && SHARED_LIST+=("$(basename "$so" .so)")
done
SHARED_JSON="$(printf '%s\n' ${SHARED_LIST[@]+"${SHARED_LIST[@]}"} | awk 'NF' | LC_ALL=C sort \
               | awk 'BEGIN{printf "["} {printf "%s\"%s\"", (NR>1?",":""), $0} END{printf "]"}')"
API="$("$PHP" -n -r 'echo PHP_EXTENSION_DIR;' | sed 's|.*/||')"
cat >"$WORK_DIR/meta.json" <<EOF
{
  "branch": "$MAJOR_MINOR",
  "extensions": $BUILTIN_JSON,
  "zendExtensions": $ZEND_JSON,
  "sharedExtensions": $SHARED_JSON,
  "extensionsDir": "lib/php/extensions",
  "extensionApi": "$API",
  "sharedExtensionRequires": {"redis": ["igbinary"], "memcached": ["igbinary"]}
}
EOF
