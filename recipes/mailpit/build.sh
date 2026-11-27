#!/usr/bin/env bash
set -euo pipefail
# Mailpit: official darwin-arm64 release binary, repackaged.
# Upstream publishes no checksum file or signature; add-version.sh pins the
# SHA-256 only after it matches the digest GitHub reports for the release asset.
mkdir -p "$STAGE_DIR/bin" "$STAGE_DIR/share/licenses/mailpit"
install -m 0755 "$SRC_DIR/mailpit" "$STAGE_DIR/bin/mailpit"
cp "$SRC_DIR/LICENSE" "$STAGE_DIR/share/licenses/mailpit/"
cat >"$WORK_DIR/meta.json" <<JSON
{
  "upstream": "https://github.com/axllent/mailpit",
  "usage": "bin/mailpit --listen 127.0.0.1:8025 --smtp 127.0.0.1:1025 --database <file>"
}
JSON
