#!/usr/bin/env bash
set -euo pipefail
# lego (ACME client): official darwin-arm64 release binary, repackaged.
# fetch-source.sh verifies it against upstream's lego_<version>_checksums.txt.
mkdir -p "$STAGE_DIR/bin" "$STAGE_DIR/share/licenses/lego"
install -m 0755 "$SRC_DIR/lego" "$STAGE_DIR/bin/lego"
cp "$SRC_DIR/LICENSE" "$STAGE_DIR/share/licenses/lego/"
cat >"$WORK_DIR/meta.json" <<JSON
{
  "upstream": "https://github.com/go-acme/lego"
}
JSON
