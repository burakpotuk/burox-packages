# CLAUDE.md — burox-packages (paket derleme reposu)

Bu repo, Burox uygulamasının indirdiği tüm sunucu binary'lerini (PHP, Nginx, Apache, MariaDB, MySQL, Mailpit, ...) **GitHub Actions'ta** derler, test eder, paketler ve **imzalı manifest** yayınlar. Ana plan: `docs/PLAN.md` (özellikle §3.1).

## Kullanıcı hakkında
Kullanıcı Swift/Xcode/derleme deneyimi olmayan bir geliştiricidir. Onunla **Türkçe** konuş. GitHub ayarlarında elle yapması gerekenleri (secret ekleme, Actions izinleri, Release oluşturma) tıklama tıklama anlat.

## Kurallar
- Hedef: `darwin-arm64`, `MACOSX_DEPLOYMENT_TARGET=14.0`, runner `macos-14` veya daha yenisi (arm64).
- **Taşınabilirlik:** Çıktıdaki her Mach-O dosyası (binary, `.dylib`, `.so`) yalnızca `/usr/lib/` ve `/System/` altına bağlanabilir. Diğer her şey statik. `scripts/verify-relocatable.sh` bunu `otool -L` ile denetler; ihlalde build **kırılır**.
- Kaynak tarball'ları `recipes/<paket>/sources.json` içinde sabitlenmiş SHA-256 ile indirilir. Upstream GPG imzası veya resmi checksum varsa doğrulanır.
- Her paket `recipes/<paket>/build.sh` + `recipes/<paket>/smoke-test.sh` içerir. Smoke test geçmeden paket yayınlanmaz.
- Her pakete upstream `LICENSE`/`COPYING` dosyaları eklenir.
- Arşiv adı: `<ad>-<sürüm>-darwin-arm64.tar.xz`. Arşiv kökünde `bin/`, `sbin/`, `lib/`, `share/`, `etc-default/` ve `PACKAGE.json` (ad, sürüm, build tarihi, kaynak checksum'ları, uzantı listesi gibi meta) bulunur.
- Arm64 binary'ler en az ad-hoc imzalı olmalı (`codesign -s - --force`). Developer ID ile imzalama ileride eklenecek (prompt 31).
- Manifest imzası Ed25519. Özel anahtar sadece GitHub Secret `MANIFEST_SIGNING_KEY` içinde. Asla repoya, loga veya artifact'e yazılmaz.
- Shell scriptleri `set -euo pipefail` ile başlar ve `shellcheck` temizdir.
- CI önbelleği: bağımlılık derlemeleri (OpenSSL, ICU, libxml2, ...) tarif dosyalarının hash'iyle önbelleklenir.

## Bitirirken
1. Workflow'lar `act` ile değil, gerçek bir `workflow_dispatch` çalıştırmasıyla test edilir. Kullanıcıya nasıl tetikleyeceğini anlat.
2. `docs/PROGRESS.md`'ye ekle; kararları `docs/DECISIONS.md`'ye yaz.
3. Kullanıcıya Türkçe özet + test adımları ver; onaydan sonra commit at.
