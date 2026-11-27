# cloudflared

Cloudflare'in resmi `cloudflared-darwin-arm64.tgz` binary'si, değiştirilmeden
(Cloudflare Developer ID imzası korunarak) yeniden paketlenir.

**macOS 15 gerekir.** Upstream darwin binary'leri `LC_BUILD_VERSION minos 15.0`
ile derleniyor (en az 2025.11'den beri), bu yüzden `versions.json` içinde
`"minMacOS": "15.0"` var ve manifestteki giriş de bunu taşır. Uygulama macOS
14'te paylaşım tünelini "macOS 15 gerekir" olarak göstermelidir.
Bkz. `docs/DECISIONS.md` (ADR-006).
