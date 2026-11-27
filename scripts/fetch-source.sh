#!/usr/bin/env bash
set -euo pipefail
# Download one upstream source described by a sources.json file, verify it and
# (optionally) extract it.
#
#   fetch-source.sh [--record FILE] <sources.json> <version> [<extract-dir>]
#   fetch-source.sh --pin <sources.json> <version>
#
# Normal mode: the SHA-256 pinned in sources.json ("versions": {"<ver>": "<sha256>"})
# is mandatory. Upstream GPG signatures ("signature" + "keyring") and official
# checksum files ("checksumFile") are verified in addition when configured.
#
# --pin mode is used by add-version.sh: there is no pinned hash yet, so at least
# one upstream verification (GPG signature, official checksum file or the GitHub
# release asset digest) must succeed. Prints the SHA-256 on stdout.
#
# sources.json fields:
#   name          short name (used for records/licenses)
#   url           URL template; {version} and {version_underscored} are substituted
#   mirrors       optional list of fallback URL templates (tried in order)
#   signature     optional detached signature URL template; {url} = resolved url
#   keyring       name of keys/upstream/<keyring>.asc (required with signature)
#   checksumFile  optional official checksum file URL template ({url}, {version})
#   strip         --strip-components for extraction (default 1)
#   versions      { "<version>": "<sha256>" }

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

PIN=0
RECORD=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pin) PIN=1; shift ;;
    --record) RECORD="$2"; shift 2 ;;
    -*) die "unknown option: $1" ;;
    *) break ;;
  esac
done
[[ $# -ge 2 ]] || die "usage: fetch-source.sh [--pin] [--record FILE] <sources.json> <version> [<extract-dir>]"

SOURCES_JSON="$1"
VERSION="$2"
EXTRACT_DIR="${3:-}"
require_cmd jq curl tar
[[ -f "$SOURCES_JSON" ]] || die "not found: $SOURCES_JSON"

field() { jq -r --arg f "$1" '.[$f] // empty' "$SOURCES_JSON"; }
expand() {
  # Expand {version}, {version_underscored} and {url} placeholders.
  local t="$1"
  t="${t//\{version_underscored\}/${VERSION//./_}}"
  t="${t//\{version\}/$VERSION}"
  t="${t//\{url\}/${URL:-}}"
  printf '%s' "$t"
}

NAME="$(field name)"
[[ -n "$NAME" ]] || die "$SOURCES_JSON: missing 'name'"
[[ -n "$(field url)" ]] || die "$SOURCES_JSON: missing 'url'"
KEYRING="$(field keyring)"
STRIP="$(jq -r '.strip // 1' "$SOURCES_JSON")"
PINNED="$(jq -r --arg v "$VERSION" '.versions[$v] // empty' "$SOURCES_JSON")"

if [[ "$PIN" == "0" && -z "$PINNED" ]]; then
  die "$SOURCES_JSON has no pinned sha256 for version $VERSION (run scripts/add-version.sh)"
fi
if [[ -n "$(field signature)" && -z "$KEYRING" ]]; then
  die "$SOURCES_JSON: 'signature' requires 'keyring'"
fi

DL_DIR="$BUILD_ROOT/downloads"
mkdir -p "$DL_DIR"

try_download() {
  # try_download <url> <dest>  -> 0 on success
  local url="$1" dest="$2" tmp
  tmp="$(mktemp "$DL_DIR/.part.XXXXXX")"
  if curl -fsSL --retry 4 --retry-delay 3 --retry-all-errors --connect-timeout 30 \
        -o "$tmp" "$url"; then
    mv -f "$tmp" "$dest"
    return 0
  fi
  rm -f "$tmp"
  return 1
}
download() { try_download "$1" "$2" || die "download failed: $1"; }

url_key() { printf '%s' "$1" | sha256_stdin | cut -c1-16; }

CANDIDATES=("$(expand "$(field url)")")
while IFS= read -r m; do
  [[ -n "$m" ]] && CANDIDATES+=("$(expand "$m")")
done < <(jq -r '.mirrors[]?' "$SOURCES_JSON")

URL=""
for cand in "${CANDIDATES[@]}"; do
  ARCHIVE="$DL_DIR/$(url_key "$cand")-$(basename "$cand")"
  if [[ -n "$PINNED" && -f "$ARCHIVE" && "$(sha256_file "$ARCHIVE")" == "$PINNED" ]]; then
    log "$NAME $VERSION: using cached download of $cand"
    URL="$cand"; break
  fi
  log "$NAME $VERSION: downloading $cand"
  if try_download "$cand" "$ARCHIVE"; then URL="$cand"; break; fi
  warn "$NAME $VERSION: download failed: $cand"
done
[[ -n "$URL" ]] || die "$NAME $VERSION: all download URLs failed"

# Signature / checksum templates may refer to the URL that actually worked.
SIG_URL=""; [[ -z "$(field signature)" ]] || SIG_URL="$(expand "$(field signature)")"
SUM_URL=""; [[ -z "$(field checksumFile)" ]] || SUM_URL="$(expand "$(field checksumFile)")"

ACTUAL="$(sha256_file "$ARCHIVE")"

if [[ -n "$PINNED" ]]; then
  if [[ "$ACTUAL" != "$PINNED" ]]; then
    rm -f "$ARCHIVE"
    die "$NAME $VERSION: SHA-256 mismatch for $URL
  expected (pinned): $PINNED
  actual:            $ACTUAL"
  fi
  log "$NAME $VERSION: SHA-256 matches pinned value"
fi

VERIFIED=()
SIGNER=""

# --- Upstream GPG signature ---------------------------------------------------
if [[ -n "$SIG_URL" ]]; then
  require_cmd gpgv gpg
  KEYFILE="$ROOT_DIR/keys/upstream/$KEYRING.asc"
  [[ -f "$KEYFILE" ]] || die "missing upstream keyring: keys/upstream/$KEYRING.asc"
  SIG_FILE="$ARCHIVE.sig"
  download "$SIG_URL" "$SIG_FILE"
  # Short path: gpg refuses socket paths longer than ~104 bytes.
  GPG_TMP="$(mktemp -d /tmp/burox-gpg.XXXXXX)"
  chmod 700 "$GPG_TMP"
  GNUPGHOME="$GPG_TMP" gpg --batch --quiet --dearmor <"$KEYFILE" >"$GPG_TMP/ring.gpg"
  STATUS="$(GNUPGHOME="$GPG_TMP" gpgv --keyring "$GPG_TMP/ring.gpg" --status-fd 1 \
              "$SIG_FILE" "$ARCHIVE" 2>/dev/null || true)"
  rm -rf "$GPG_TMP"
  if ! grep -q '^\[GNUPG:\] GOODSIG ' <<<"$STATUS"; then
    die "$NAME $VERSION: GPG signature verification FAILED ($SIG_URL, keyring $KEYRING)"
  fi
  # VALIDSIG <sig-fpr> ... <primary-key-fpr>
  SIGNER="$(awk '$2 == "VALIDSIG" {print $NF}' <<<"$STATUS" | head -n1)"
  log "$NAME $VERSION: GPG signature OK (key $SIGNER)"
  VERIFIED+=("gpg")
fi

# --- Official checksum file -----------------------------------------------------
if [[ -n "$SUM_URL" ]]; then
  SUM_FILE="$ARCHIVE.checksums"
  download "$SUM_URL" "$SUM_FILE"
  BASE="$(basename "$URL")"
  # Prefer the line that names our file ("<hash>  <file>", "<hash> *<file>" or
  # "SHA256(<file>)= <hash>"); fall back to a file containing a single hash.
  hashes_in() { awk '{ for (i = 1; i <= NF; i++) if (length($i) == 64 && $i ~ /^[0-9a-fA-F]+$/) print $i }'; }
  EXPECTED="$(awk -v f="$BASE" '{ n = $NF; sub(/^\*/, "", n); if (n == f || index($0, "(" f ")") > 0) print }' "$SUM_FILE" \
              | hashes_in | head -n1)"
  if [[ -z "$EXPECTED" && "$(hashes_in <"$SUM_FILE" | wc -l | tr -d ' ')" == "1" ]]; then
    EXPECTED="$(hashes_in <"$SUM_FILE")"
  fi
  [[ -n "$EXPECTED" ]] || die "$NAME $VERSION: no SHA-256 for $BASE in $SUM_URL"
  EXPECTED="$(tr 'A-F' 'a-f' <<<"$EXPECTED")"
  if [[ "$EXPECTED" != "$ACTUAL" ]]; then
    die "$NAME $VERSION: official checksum mismatch ($SUM_URL)
  official: $EXPECTED
  actual:   $ACTUAL"
  fi
  log "$NAME $VERSION: official checksum file matches"
  VERIFIED+=("checksum-file")
fi

# --- GitHub release asset digest (pin mode only) ----------------------------------
if [[ "$PIN" == "1" && "$URL" =~ ^https://github\.com/([^/]+)/([^/]+)/releases/download/([^/]+)/([^/]+)$ ]]; then
  GH_OWNER="${BASH_REMATCH[1]}"; GH_REPO="${BASH_REMATCH[2]}"
  GH_TAG="${BASH_REMATCH[3]}";   GH_ASSET="${BASH_REMATCH[4]}"
  if command -v gh >/dev/null 2>&1; then
    DIGEST="$(gh api "repos/$GH_OWNER/$GH_REPO/releases/tags/$GH_TAG" \
                --jq ".assets[] | select(.name == \"$GH_ASSET\") | .digest" 2>/dev/null || true)"
    if [[ "$DIGEST" == sha256:* ]]; then
      if [[ "${DIGEST#sha256:}" != "$ACTUAL" ]]; then
        die "$NAME $VERSION: GitHub release digest mismatch ($DIGEST vs sha256:$ACTUAL)"
      fi
      log "$NAME $VERSION: GitHub release asset digest matches"
      VERIFIED+=("github-digest")
    else
      warn "$NAME $VERSION: GitHub did not report an asset digest"
    fi
  else
    warn "gh CLI not found; skipping GitHub release digest check"
  fi
fi

if [[ "$PIN" == "1" ]]; then
  [[ ${#VERIFIED[@]} -gt 0 ]] || die "$NAME $VERSION: no upstream verification available; refusing to pin"
  log "$NAME $VERSION: verified via ${VERIFIED[*]}"
  printf '%s\n' "$ACTUAL"
  exit 0
fi

# --- Record + extract -------------------------------------------------------------
if [[ -n "$RECORD" ]]; then
  mkdir -p "$(dirname "$RECORD")"
  jq -n --arg name "$NAME" --arg version "$VERSION" --arg url "$URL" --arg sha256 "$ACTUAL" \
        --arg sig "$SIG_URL" --arg signer "$SIGNER" --arg sums "$SUM_URL" \
        '{name: $name, version: $version, url: $url, sha256: $sha256}
         + (if $sig != "" then {signature: {url: $sig, signer: $signer}} else {} end)
         + (if $sums != "" then {checksumFile: $sums} else {} end)' >"$RECORD"
fi

if [[ -n "$EXTRACT_DIR" ]]; then
  rm -rf "$EXTRACT_DIR"
  mkdir -p "$EXTRACT_DIR"
  tar -xf "$ARCHIVE" -C "$EXTRACT_DIR" --strip-components="$STRIP"
  log "$NAME $VERSION: extracted to $EXTRACT_DIR"
fi
