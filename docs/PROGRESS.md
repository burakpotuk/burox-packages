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
