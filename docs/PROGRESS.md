# İlerleme

Her prompt sonunda Claude Code buraya bir bölüm ekler.

<!-- Şablon:
## NN — Başlık (YYYY-MM-DD)
- Yapılanlar:
- Bilinen eksikler:
- Sonraki prompta notlar:
-->

## 06 — Paket reposu altyapısı, imzalı manifest, Nginx, Apache, hazır binary'ler (2026-11-27)
- Yapılanlar:
  - Ortak boru hattı: `scripts/build-package.sh` (indir + SHA-256/GPG/checksum doğrula → statik bağımlılıklar (önbellekli) → derle → lisanslar → strip + ad-hoc imza → `verify-relocatable.sh` (otool -L, LC_RPATH, minos ≤ 14.0, imza) → `PACKAGE.json` → `tar.xz` → arşivi ayrı dizine açıp smoke test).
  - Bağımlılık tarifleri: OpenSSL 3.5.9 LTS, PCRE2 10.49, zlib 1.4, expat 2.11.0, APR 1.7.6, APR-util 1.6.6 — hepsi upstream GPG imzası (ve varsa resmi checksum) ile sabitlendi. Upstream anahtarları `keys/upstream/` altında, resmi kaynakları README'de.
  - Paketler (hepsi yerelde derlendi, denetimden ve smoke testten geçti): nginx 1.30.8 (2,5 MB), apache 2.4.71 (89 modül .so, 3,5 MB), mailpit 1.34.0, cloudflared 2026.11.2 (macOS 15+, ADR-006), lego 5.8.0.
  - Smoke testler: nginx (-t, HTTP, HTTPS+HTTP/2, stub_status, sub_filter, realip, auth_request, PCRE2, unix soket fastcgi_pass, durdurma); apache (tüm modüller yüklenir, -t, rewrite + .htaccess, headers, remoteip, setenvif, expires, deflate, proxy, unix soket proxy_fcgi, htpasswd); mailpit (SMTP ile mail gönderip REST API'den okuma); cloudflared/lego (--version, imza).
  - Manifest: `make-manifest.py` (Release sidecar'larından, boyut + GitHub digest çapraz kontrolü), `sign-manifest.sh`/`verify-manifest.sh` (Ed25519, base64 imza; CryptoKit ile uyumu doğrulandı), `generate-signing-keys.sh`, `publish-manifest.yml` (imzala → doğrula → 1 bayt tamper reddi → yükle → indirip tekrar doğrula).
  - Workflow'lar: `build-package.yml` (reusable: plan → macos-15 matris → yayın → manifest), `build-{nginx,apache,mailpit,cloudflared,lego}.yml` (elle, `versions.json` değişince otomatik, PR'da yalnızca derle+test), `publish-manifest.yml`, `lint.yml` (shellcheck, actionlint, JSON, tarif tutarlılığı, öz-testler Linux+macOS). Üçüncü parti action'lar commit SHA'sıyla sabitli.
  - `scripts/selftest.sh`: 17 kontrol (imza turu, 1 bayt tamper reddi, yabancı anahtar reddi, yedek anahtar, yanlış SHA reddi, otool ihlali ve minos ihlali yakalama).
  - İmza anahtarları üretildi (birincil + yedek; public'ler `keys/`, ham değerler `keys/README.md`), birincil anahtar `MANIFEST_SIGNING_KEY` secret'ına eklendi.
  - CI doğrulaması: push ile 5 build + lint yeşil (macos-15, Xcode 16.4, SDK 15.5, `minos 14.0`); 5 Release ve imzalı `manifest` Release'i yayında. Elle `workflow_dispatch`: `publish-manifest` yeşil, `build-nginx` "already published, skipping" ile yeşil. Genel adresten indirilen manifest doğrulandı, 1 bayt değişmiş kopya reddedildi; her arşiv manifestteki SHA-256 ile eşleşti ve CI'da derlenen binary'ler yerelde tüm smoke testleri geçti.
- Bilinen eksikler:
  - macOS 14 runner'ı kalmadığı için CI gerçek macOS 14'te test edemiyor (ADR-003).
  - cloudflared için macOS 14 desteği kullanıcı kararına bağlı (ADR-006).
  - Özel anahtar dosyaları hâlâ `~/burox-manifest-keys/` içinde; kullanıcı parola yöneticisine kaydedip silmeli.
  - Atlanan (skipped) matris işinin adı Actions arayüzünde `${{ inputs.package }} ${{ matrix.published }}` diye ham görünüyor (yalnızca görsel).
- Sonraki prompta notlar:
  - 07 (PHP): `deps/openssl` hazır; 7.4/8.0 için ayrı `deps/openssl-1.1` eklenmeli (versions.json'da build başına `"deps"` desteklenir). APR'deki "paylaşımlı derle, dylib sil, .la'yı statik işaretle" yöntemi (`build-deps.sh`) libtool kullanan diğer bağımlılıklarda da işe yarar. phpize için `include/` gerekirse `package.sh`'deki izinli kök listesi güncellenmeli (şu an yalnızca bin/sbin/lib/share/etc-default). `scripts/lib/fcgi_echo.py` FastCGI testlerinde yeniden kullanılabilir.
  - Uygulama (CorePackages): manifest URL'si ve imza biçimi ADR-007'de; `generatedAt` geri gitmesin; `minMacOS` filtrelemesi; nginx'i `-p/-c/-e`, httpd'yi `-d/-f` ile başlat; nginx `temp/` yollarını config'te ayarla.

## 07 — PHP paketleri 7.4 → 8.6 (2026-11-28)
- Yapılanlar:
  - Spike (ADR-008): static-php-cli 7.4/8.0'ı desteklemediği için elendi; kendi tariflerimizle 8.6.0 ve 7.4.33'te OPcache + Xdebug paylaşımlı yüklendi, FPM çalıştı, `phpize` taşınabilir. Karar: B.
  - 15 yeni statik bağımlılık (ICU 79.1, libxslt, libzip, zstd, libsodium, libpng, libjpeg-turbo, libwebp, FreeType, curl 8.23.0, curl-legacy 8.17.0 (OpenSSL 1.1.1 için), GMP, gettext/libintl, libmemcached-awesome, SQLite, oniguruma, libxml2, OpenSSL 1.1.1w); 12'si GPG veya resmi checksum ile doğrulandı. Upstream anahtarlarına php, curl, icu, gettext, gmp, freetype, webp, zstd, libsodium eklendi.
  - `recipes/php`: 8 dal (7.4.33, 8.0.30, 8.1.34, 8.2.36, 8.3.37, 8.4.28, 8.5.13, 8.6.0), prompt'taki gömülü uzantıların tamamı, paylaşımlı opcache (≤ 8.4) / xdebug / igbinary / apcu / redis / memcached, `PACKAGE.json` → `meta.extensions`, `sharedExtensions`, `sharedExtensionRequires`, `eol`, `securityNote`, `prerelease`.
  - Smoke test (31 kontrol): `php -v`, beklenen 48 uzantı, her paylaşımlı uzantının yüklenmesi, OPcache/Xdebug etkin, phpize/php-config taşınabilir, openssl, pdo_sqlite, mbstring, dom, intl (`NumberFormatter` tr_TR), gd (PNG + freetype/jpeg/png/webp), Mozilla CA paketiyle `curl https://example.com`, zip, sodium, xsl, gmp, apcu, igbinary+redis (zstd), memcached, `php-fpm -t` ve unix soket üzerinden PHP FastCGI istemcisiyle (`recipes/php/fcgi-client.php`) istek.
  - Yeni genel denetim `scripts/verify-plugin-symbols.sh`: her `.so` modülün programdan beklediği semboller gerçekten dışa aktarılıyor mu (Xcode 27 bağlayıcısının attığı semboller NULL'a bağlanıp çöktürüyordu → `-Wl,-export_dynamic`). Apache de bu denetimden geçiyor.
  - xz 128 MiB sözlük: `php` ve `php-fpm` birbirinin kopyası olduğu için PHP arşivleri ~35 MB yerine ~19 MB.
  - `build-php.yml` (8 dallı matris), ortak iş akışı autoconf/pkgconf/cmake/xz'yi gerekirse kurar.
  - Yerelde (Xcode 27) tam smoke testten geçenler: 8.6.0, 8.4.28, 8.3.37, 8.2.36, 8.1.34. 8.5.13 (igbinary 3.2.17RC1) ve 8.0.30/7.4.33 (curl-legacy'de `pipe2` düzeltmesi) son düzeltmelerden sonra CI'da doğrulanacak.
- Bilinen eksikler:
  - PHP 8.6 için Xdebug/igbinary/apcu/memcached/redis kararlı sürüm değil (upstream henüz yayımlamadı); `meta.prerelease` ile işaretli.
  - libpng, libmemcached ve PECL kaynakları upstream imza yayımlamadığı için ilk indirmede sabitlendi.
  - Kullanıcı doğrulaması (temiz bir Mac'te `php -m`) bekliyor.
- Sonraki prompta notlar:
  - Uygulama: `extension_dir` = `<paket>/lib/php/extensions`; ≥ 8.5'te `opcache.so` yok (yerleşik); redis/memcached'den önce `extension=igbinary.so`; `curl.cainfo`/`openssl.cafile` her zaman Burox'un Mozilla tabanlı `cacert.pem`'i (macOS'un `/etc/ssl/cert.pem`'i eksik); `meta.eol`/`securityNote`/`prerelease` arayüzde gösterilmeli.
  - 08 (MariaDB/MySQL): `deps/` altındaki OpenSSL/zlib/pcre2 hazır; CMake bağımlılıkları için `libzip`/`zstd` tarifleri örnek.
