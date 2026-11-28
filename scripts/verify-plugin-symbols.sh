#!/usr/bin/env bash
set -euo pipefail
# Fail if a loadable module (.so bundle) expects a symbol from its host program
# that nothing in the package actually exports.
#
#   verify-plugin-symbols.sh <dir>
#
# Apache modules and PHP extensions are linked with "-undefined dynamic_lookup":
# symbols such as ap_hook_handler or zend_register_internal_class_ex are found
# at load time in the host (sbin/httpd, bin/php, sbin/php-fpm) or in another
# module loaded earlier (igbinary -> redis, mod_proxy -> mod_proxy_fcgi). If the
# host does not export one, dyld binds it to NULL *without an error* and the
# process crashes only when that code path runs. Newer Apple linkers drop
# unreferenced globals from executables unless -export_dynamic is used, which
# is exactly how such holes appear.
#
# Checked: every "(dynamically looked up)" undefined symbol of every bundle must
# be exported by some executable or bundle in <dir>.

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
require_cmd nm otool file

DIR="${1:?usage: verify-plugin-symbols.sh <dir>}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

EXES=()
BUNDLES=()
while IFS= read -r -d '' f; do
  [[ "$(file -b "$f")" == Mach-O* ]] || continue
  case "$(otool -hv "$f" | awk 'NR == 4 {print $5}')" in
    EXECUTE) EXES+=("$f") ;;
    BUNDLE)  BUNDLES+=("$f") ;;
  esac
done < <(find "$DIR" -type f -print0)

if [[ ${#BUNDLES[@]} -eq 0 ]]; then
  log "verify-plugin-symbols: no loadable modules"
  exit 0
fi

# Everything the package itself can provide at runtime.
for f in ${EXES[@]+"${EXES[@]}"} "${BUNDLES[@]}"; do
  nm -gU "$f" 2>/dev/null | awk '{print $NF}'
done | LC_ALL=C sort -u >"$TMP/exported"

VIOLATIONS=0
for b in "${BUNDLES[@]}"; do
  nm -m -u "$b" 2>/dev/null | awk '/\(dynamically looked up\)/ {print $3}' | LC_ALL=C sort -u >"$TMP/needed"
  LC_ALL=C comm -23 "$TMP/needed" "$TMP/exported" >"$TMP/missing"
  if [[ -s "$TMP/missing" ]]; then
    VIOLATIONS=$((VIOLATIONS + 1))
    rel="${b#"$DIR"/}"
    if in_ci; then
      printf '::error title=verify-plugin-symbols::%s needs symbols nothing in the package exports: %s\n' \
        "$rel" "$(head -n 8 "$TMP/missing" | tr '\n' ' ')" >&2
    else
      printf '  MISSING %s: %s\n' "$rel" "$(head -n 8 "$TMP/missing" | tr '\n' ' ')" >&2
    fi
  fi
done

[[ "$VIOLATIONS" -eq 0 ]] || die "verify-plugin-symbols: $VIOLATIONS module(s) reference symbols that are not exported (link the host with -Wl,-export_dynamic or link the library into the module)"
log "verify-plugin-symbols: ${#BUNDLES[@]} module(s) fully resolvable against ${#EXES[@]} host executable(s)"
