# 08 — Veritabanı, ek servis ve web aracı paketleri

**Repo:** `burox-packages` · **Önkoşul:** 06 (07 ile paralel olabilir) · **Oku:** PLAN.md §3.1, §3.7, §3.9

## Amaç
MariaDB, MySQL, Redis, Memcached, Meilisearch, MinIO ve PHP web araçlarını (Composer, WP-CLI, Adminer, phpMyAdmin) paketlemek.

## Yapılacaklar
1. **MariaDB** (resmi macOS binary'si yok → kaynaktan, CMake): aktif LTS dalları (`versions.json`). OpenSSL, zlib, pcre2 statik; gereksiz motorlar kapalı (ör. ColumnStore, Mroonga, Spider); InnoDB, Aria, MyISAM açık. Çıktı: `bin/mariadbd`, `bin/mariadb`, `bin/mariadb-dump`, `bin/mariadb-admin`, `bin/mariadb-install-db`, `share/`, `lib/plugin/`. Smoke test: geçici datadir ile install-db, başlat (127.0.0.1, rastgele port), `CREATE DATABASE`, dump al, durdur.
2. **MySQL:** Oracle'ın resmi macOS arm64 tarball'ı. Resmi MD5 + mümkünse GPG imzası doğrulanır, gereksiz dosyalar ayıklanır (test suite, debug binary'leri), yeniden paketlenir. Dallar: 8.0 (eski projeler; EOL notu), 8.4 LTS, güncel. Smoke test MariaDB ile aynı (`--initialize-insecure`). `otool -L` kontrolünde Oracle'ın paketlediği `lib/` dylib'leri `@loader_path` ile çözülüyorsa kabul edilir; bunu ADR'ye yaz.
3. **Redis** (kaynaktan; TLS gerekmiyor) ve **Memcached** (libevent statik). Smoke: başlat, `PING`/`stats`.
4. **Meilisearch:** resmi `meilisearch-macos-apple-silicon` binary'si, checksum doğrulamalı. Smoke: başlat, `/health`.
5. **MinIO:** Topluluk sürümünün dağıtım politikası değişti. Önce güncel durumu araştır (resmi repo ve duyurular), sonra kullanıcıya şu seçenekleri sun: (a) kaynaktan Go ile derleme (lisans: AGPL — ekip içi kullanım için uygun mu, kullanıcıya not düş), (b) S3 uyumlu bir alternatif. Seçimi ADR'ye yaz ve uygula. Smoke: başlat, bucket oluştur.
6. **Composer** (`composer.phar`, resmi SHA-256 doğrulamalı), **WP-CLI** (`wp-cli.phar`, resmi imza/checksum), **Adminer** (tek dosya; mümkünse resmi kaynağın imzası), **phpMyAdmin** (resmi zip, GPG doğrulamalı). Bunlar "noarch" paketler (manifestte `arch: "noarch"`).
7. Manifest'i güncelle ve imzala.

## Kabul kriterleri
- [ ] Tüm paketler Release'lerde, manifest güncel ve doğrulanıyor.
- [ ] MariaDB ve MySQL smoke testleri yeşil; dump/restore çalışıyor.
- [ ] MinIO kararı ADR'de ve kullanıcı onaylı.

## Senin test adımların
1. MinIO seçeneklerini oku ve seç.
2. Actions'tan iş akışlarını çalıştır; Releases'ta paketleri gör.
3. MariaDB arşivini indir; Claude Code'un verdiği 4–5 komutla geçici bir sunucu başlatıp `SELECT VERSION();` çalıştır.
