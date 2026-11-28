# Karar Kayıtları (ADR)

Her önemli teknik karar için bir kayıt. PLAN.md'deki bir kararı değiştiren kayıt, PLAN.md'yi de günceller.

<!-- Şablon:
## ADR-NNN: Başlık (YYYY-MM-DD, prompt NN)
- Bağlam:
- Seçenekler:
- Karar:
- Sonuçlar / riskler:
-->

## ADR-001: Derleme düzeni ve tek giriş noktası (2026-11-27, prompt 06)
- Bağlam: Aynı adımların hem yerelde hem CI'da birebir çalışması, sürüm eklemenin tek dosya değişikliği olması isteniyor.
- Seçenekler: (a) mantığı workflow YAML'larına yazmak, (b) her şeyi scriptlerde tutup workflow'u ince bırakmak.
- Karar: (b). `scripts/build-package.sh <paket> <sürüm>` indir → doğrula → bağımlılık → derle → `package.sh` (lisans, strip, imza, `verify-relocatable`, `PACKAGE.json`, tar.xz, sidecar) → arşivi **farklı bir dizine açıp** smoke test. `recipes/<paket>/sources.json` URL şablonu + sürüm başına sabit SHA-256, `versions.json` derlenecek sürümler/kanal/bağımlılıklar. Bağımlılıklar `deps/<ad>/` altında ayrı tarifler. `scripts/add-version.sh` yeni sürümü upstream doğrulamasıyla sabitler. `versions.json` değişince ilgili `build-<paket>` workflow'u kendiliğinden çalışır; zaten yayınlanmış sürümler atlanır.
- Sonuçlar / riskler: Scriptler macOS'un bash 3.2'siyle de çalışacak şekilde yazıldı. Bağımlılık önbelleği bağımlılık başına anahtarlı (`tarif dosyaları + build-env.sh + build-deps.sh + prefix yolu + bağımlı olunanların anahtarları`); CI'da `actions/cache` ile saklanır, paketler arasında da paylaşılır.

## ADR-002: Upstream doğrulama zinciri (2026-11-27, prompt 06)
- Bağlam: Kaynaklar sabit SHA-256 ile indirilmeli; upstream imza/checksum varsa doğrulanmalı.
- Karar: SHA-256 sabitlemesi her zaman zorunlu. Ek olarak: GPG imzası (`gpgv`, yalnızca `keys/upstream/<ad>.asc` içindeki, resmi listelerle eşleştirilmiş anahtarlar; anahtar sunucusundan çalışma anında anahtar çekilmez), resmi checksum dosyası (`.sha256`, `checksums.txt`) ve sabitleme anında GitHub'ın release asset `digest` değeri. Mailpit hiçbir imza/checksum yayımlamıyor → yalnızca GitHub digest + sabit SHA. cloudflared: `.tgz` içindeki binary'nin SHA-256'sı resmi sürüm notlarındakiyle karşılaştırılır ve Cloudflare Developer ID imzası (Team `68WVV388M8`) zorunlu tutulur.
- Sonuçlar / riskler: Upstream yeni bir imzacıya geçerse `add-version.sh` bilerek durur; anahtar `keys/upstream/README.md`'deki prosedürle eklenir.

## ADR-003: Runner macos-15, hedef macOS 14.0 (2026-11-27, prompt 06)
- Bağlam: PLAN `macos-14` runner diyordu; GitHub macOS 14 arm64 runner'larını 2026-11-02'de kaldırdı.
- Karar: `macos-15` (arm64) üzerinde `MACOSX_DEPLOYMENT_TARGET=14.0` ile derleme. Yeni SDK'nın macOS 14'te olmayan fonksiyonları (ör. 15.4 SDK'daki `strchrnul`) sessizce kullanmasını engellemek için `CFLAGS` içinde `-Werror=unguarded-availability-new`; `verify-relocatable.sh` her Mach-O dosyasının `minos` değerinin ≤ 14.0 olduğunu denetler. Manifest yayını (Linux araçları yeterli) `ubuntu-latest` üzerinde.
- Sonuçlar / riskler: CI artık gerçek bir macOS 14 üzerinde smoke test yapamıyor; tam garanti için ara sıra bir macOS 14 makinesinde elle `php -v`/`nginx -V` denemesi önerilir. PLAN.md §3.1 güncellendi.

## ADR-004: Statik bağlama ayrıntıları (2026-11-27, prompt 06)
- Bağlam: Her Mach-O yalnızca `/usr/lib` ve `/System` altına bağlanabilir.
- Karar:
  - OpenSSL **3.5 LTS** (4.x değil; nginx/httpd/PHP uyumluluğu ve 2030'a kadar destek). `no-shared no-module` (sağlayıcılar libcrypto içinde), `OPENSSLDIR=/private/etc/ssl` (macOS'un kendi CA paketi varsayılan güven deposu olur; Burox yine de CA yollarını açıkça verir).
  - zlib 1.4 (1.3.2'deki güvenlik açıklarını kapatıyor).
  - APR, httpd'nin modül derlemek için kullandığı libtool'u kurduğu için **paylaşımlı+statik** derlenir; `build-deps.sh` dylib'leri siler ve `.la` dosyalarını "yalnızca statik" işaretler. httpd, APR/APR-util'i `-force_load` ile tamamen içine alır; modüller (`-undefined dynamic_lookup`) bu sembolleri httpd'den çözer. `mod_ssl`/`mod_deflate` kendi statik OpenSSL/zlib kopyalarını taşır.
  - Binary'ler `strip -x` (global semboller kalır, modüller için gerekli) + ad-hoc imza. Hazır upstream binary'lerin geçerli imzası korunur.
- Sonuçlar / riskler: OpenSSL'in derlemeye gömülü `MODULESDIR` yolu CI derleme dizinini gösterir; `no-module` olduğu için kullanılmaz. `/usr/lib/libiconv` (APR-util) kurala uygundur.

## ADR-005: Arşiv düzeni ve sürümleme (2026-11-27, prompt 06)
- Karar: Paket adları `nginx`, `apache` (httpd değil; uygulamadaki site tipiyle aynı), `mailpit`, `cloudflared`, `lego`. Kökte yalnızca `bin/ sbin/ lib/ share/ etc-default/ PACKAGE.json` olabilir (`package.sh` zorlar; `.a/.la` yasak). Derlemeye gömülü önekler (`/opt/burox/nginx`, `/opt/burox/apache`) hiç var olmayacak yollardır; uygulama her zaman `-p/-c/-e` (nginx) veya `-d/-f` (httpd) verir. nginx temp yolları öneke göredir (`temp/...`): uygulama config'te bunları ayarlamalı veya `temp/` klasörünü oluşturmalı. apachectl/apxs gömülü yollar içerdiği için paketlenmez.
- Release: tag `<paket>-<sürüm>`, önce taslak olarak oluşturulup doldurulur, sonra yayınlanır ("latest" işaretlenmez). Varlıklar: `.tar.xz`, `.tar.xz.sha256`, `.package.json` (manifest girdisi). Smoke test geçmediyse (`out/*.smoke-passed` yok) yayınlanmaz. Aynı sürümün yeniden yayını için `versions.json`'da `"revision": N` → yayın sürümü `X.Y.Z_N`. `force` girdisi yalnızca acil durum içindir.

## ADR-006: cloudflared macOS 15 gerektiriyor (2026-11-27, prompt 06)
- Bağlam: Resmi `cloudflared-darwin-arm64` binary'leri en az 2025.11'den beri `LC_BUILD_VERSION minos 15.0`. `verify-relocatable` bunu yakaladı.
- Seçenekler: (a) resmi, Cloudflare imzalı binary'yi koru; pakete `minMacOS: "15.0"` yaz, uygulama macOS 14'te tüneli "macOS 15 gerekir" diye gösterir. (b) cloudflared'i Go ile kaynaktan macOS 14 hedefiyle derle (Cloudflare imzası kaybolur, ad-hoc imza olur; Go toolchain + vendored bağımlılıklar gerekir).
- Karar: (a) (2026-11-28, kullanıcı kararı Claude'a bıraktı). `versions.json` paket başına `minMacOS` alanını yalnızca `"kind": "binary"` paketlerde kabul eder; denetim o değere göre yapılır ve manifest girdisi bunu taşır.
- Sonuçlar / riskler: macOS 14 kullanıcıları paylaşım tünelini kullanamaz. (b) istenirse ayrı bir tarif olarak eklenebilir.

## ADR-007: Manifest imzası ve barındırma (2026-11-27, prompt 06)
- Karar: `manifest.json` + `manifest.json.sig`, sabit adresli `manifest` Release'inde. İmza: manifest baytları üzerinde saf Ed25519 (`openssl pkeyutl -sign -rawin`), dosyada 64 bayt imzanın tek satır base64'ü (Apple CryptoKit `Curve25519.Signing.PublicKey.isValidSignature` ile doğrulandı). İki anahtar: birincil (GitHub Secret `MANIFEST_SIGNING_KEY`) + yedek (yalnızca parola yöneticisinde). `sign-manifest.sh` anahtarı diske yazmaz (pipe), `set +x`, ve secret'ın public yarısı repodaki `keys/manifest-public-*.pem`'lerden biriyle eşleşmezse imzalamayı reddeder. CI her yayında: imzala → doğrula → 1 baytı değiştirilmiş kopyanın **reddedildiğini** doğrula → yükle → istemcinin indirdiğini tekrar indirip doğrula.
- Sonuçlar / riskler: İki dosyanın yüklenmesi atomik değil; kısa bir anda imza uyuşmazlığı görülebilir → uygulama doğrulama hatasında eski önbelleği kullanıp sonra tekrar denemeli. Eski (geri alınmış) bir manifestin tekrar sunulmasına karşı uygulama, önbelleğindekinden daha eski `generatedAt` taşıyan manifesti reddetmeli (uygulama tarafı prompt'una not).
- Gözlem (2026-11-27, ilk CI yayını): `releases/download/manifest/manifest.json` adresi, yeni yüklemeden sonra birkaç dakika **önceki** dosyayı sunabiliyor (benzersiz bir sorgu parametresi, ör. `?v=<zaman>`, taze kopyayı getiriyor). Eski çift kendi içinde tutarlı ve imzalı olduğu için güvenlik sorunu değil. Uygulama için öneri: `manifest.json` ve `.sig`'i **aynı** benzersiz sorgu parametresiyle indir; imza tutmazsa birkaç saniye sonra yeni bir parametreyle bir kez daha dene. CI'daki "Verify what clients download" adımı da aynı yöntemi kullanıyor.

## ADR-008: PHP derleme yaklaşımı — statik bağımlılık + paylaşımlı uzantı (2026-11-28, prompt 07 spike)
- Bağlam: Her PHP dalı (7.4 → 8.6) taşınabilir olmalı ve Xdebug/OPcache gibi uzantıları **paylaşımlı** (.so) yükleyebilmeli. Ölçütler: (1) `otool -L` temiz, (2) `zend_extension=opcache.so` ve `xdebug.so` yükleniyor, (3) hem 8.x hem 7.4 için uygulanabilir.
- Seçenekler:
  - **A — static-php-cli** (2.8.5): macOS'ta `--build-shared=xdebug` ile paylaşımlı uzantı üretebiliyor, ancak **yalnızca PHP 8.1–8.6**'yı destekliyor → 7.4 ve 8.0 için ölçüt 3 sağlanamıyor. Ayrıca kaynakları kendi indirme hattıyla çekiyor (bizim sabit SHA-256 + GPG zincirimizin dışında kalır) ve ikinci bir tarif sistemi bakımı getirir.
  - **B — kendi tariflerimiz**: bağımlılıklar `deps/` ile statik derlenir (prompt 06 altyapısı), PHP bunlara karşı `./configure` ile, PECL uzantıları aynı derlemenin `phpize`'ıyla derlenir.
- Spike sonucu (B, yerelde, CI ile aynı scriptler):

  | | PHP 8.6.0 | PHP 7.4.33 |
  |---|---|---|
  | Bağımlılıklar | OpenSSL 3.5.9, PCRE2 10.49, zlib 1.4, libxml2 2.15.4, SQLite 3.54.1, oniguruma 6.9.10 | aynı, OpenSSL yerine 1.1.1w |
  | `verify-relocatable` | 3 Mach-O, yalnızca `/usr/lib` | 4 Mach-O, yalnızca `/usr/lib` |
  | OPcache | yerleşik (8.5+'da ayrı .so yok), "with Zend OPcache" | `opcache.so` paylaşımlı, yükleniyor |
  | Xdebug | 3.6.0alpha1 `.so`, "with Xdebug" | 3.1.6 `.so`, "with Xdebug" |
  | php-fpm | `-t` + unix soket üzerinden FastCGI isteği | aynı |
  | phpize/php-config | açıldığı dizini gösteriyor; açılmış paketle uzantı derlenip yüklendi | aynı |
  | Arşiv / süre | 8,4 MB / ~1,5 dk | 5,4 MB / ~1,5 dk |
- Karar: **B** (2026-11-28; kullanıcı kararı Claude'a bıraktı).
- Sonuçlar / riskler (spike'ta bulunan ve çözülenler):
  - **OPcache 8.5'ten itibaren PHP'ye gömülü**; uygulama ≥ 8.5 için `zend_extension=opcache.so` yazmamalı. `PACKAGE.json` → `meta.zendExtensions` / `meta.sharedExtensions` bunu söyler.
  - **Xdebug, PHP 8.6'yı yalnızca 3.6 dalında destekliyor ve o an için yalnızca `3.6.0alpha1` var** (PECL'de yok, GitHub etiket arşivinden). Karar: alpha ile yayınlanır, manifestte `meta.prerelease` ile işaretlenir (bkz. ADR-009).
  - 7.4/8.0 için: OpenSSL 1.1.1w (upstream EOL; imza anahtarının süresi sonradan dolmuş, imza öncesinde atılmış → kabul edilir), libxml2 ≥ 2.14'te kalkan `ATTRIBUTE_UNUSED` için zorunlu-include uyumluluk başlığı, modern clang hataları için `-Wno-error=...`.
  - Tüm dallar: `-std=gnu17` (yeni Xcode varsayılanı C23 eski PECL kodunu bozuyor), açıkça `-lresolv`, `--disable-rpath`, **harici PCRE2 10.49** (7.4'ün gömülü PCRE2'si Apple Silicon'da JIT belleği ayıramıyor; harici sürüm tüm dallara güncel regex motoru da veriyor).
  - PHP 8.6'da `mb_ereg_*` "deprecated" (oniguruma upstream'de bakımsız); yine de derleniyor.
  - Paket düzenine `include/` eklendi (phpize için başlıklar). Uzantılar `lib/php/extensions/` altında düz durur; uygulama `extension_dir`'i buna ayarlar. `phpize`/`php-config` ön eki çalışma anında kendi konumundan hesaplar.
  - PECL ve xdebug.org imza/checksum yayımlamıyor → bu kaynaklar ilk indirmede sabitlenir (`noUpstreamVerification` gerekçesiyle), sonraki her derleme o SHA-256'ya bağlıdır. SQLite yalnızca SHA3-256 yayımlıyor → sabitleme anında doğrulanır.
  - Derleme araçları: `phpize` için autoconf ve statik bağlama için pkg-config (`--static` sarmalayıcı) runner'daki Homebrew'dan özel bir araç dizini üzerinden görünür; kütüphaneleri görünmez.
  - `include/php/main/build-defs.h` derleme yollarını içerir (yalnızca `phpinfo()` "Configure Command" görüntüsü; işlevsel etkisi yok).

## ADR-009: PHP paketlerinin tam tarifi (2026-11-28, prompt 07)
- Dallar ve uzantı sürümleri (`recipes/php/versions.json`):

  | Dal | PHP | OpenSSL / curl | Xdebug | igbinary / apcu / redis / memcached | Durum |
  |---|---|---|---|---|---|
  | 7.4 | 7.4.33 | 1.1.1w / 8.17.0 | 3.1.6 | 3.2.16 / 5.1.28 / 6.3.0 / 3.4.0 | EOL |
  | 8.0 | 8.0.30 | 1.1.1w / 8.17.0 | 3.5.3 | aynı | EOL |
  | 8.1 | 8.1.34 | 3.5.9 / 8.23.0 | 3.5.3 | aynı | EOL (2025-12-31) |
  | 8.2–8.5 | 8.2.36, 8.3.37, 8.4.28, 8.5.13 | 3.5.9 / 8.23.0 | 3.5.3 | aynı | 8.2 güvenlik desteği 2026-12-31'de biter |
  | 8.6 | 8.6.0 | 3.5.9 / 8.23.0 | **3.6.0alpha1** | **upstream master** / **master** / **6.4.0RC1** / **master** | `meta.prerelease` |
- PHP 8.6 bir haftalık olduğu için PECL eklentilerinin kararlı sürümleri derlenmiyor (kaldırılan `zval_dtor`, `XtOffsetOf`, `php_smart_string.h`). 8.6'da, upstream'in 8.6'yı CI'da test ettiği commit'ler sabitlenir ve `PACKAGE.json` → `meta.prerelease` hangi uzantının ön sürüm olduğunu söyler; uygulama bunu kullanıcıya gösterebilir. Kararlı sürümler çıkınca `add-version.sh` + `"revision"` ile yeniden yayınlanır.
- Gömülü uzantılar: prompt 07'deki listenin tamamı (bcmath … zlib), ek olarak PHP'nin varsayılanları. Paylaşımlı: `opcache` (≤ 8.4), `xdebug`, `igbinary`, `apcu`, `redis` (igbinary + zstd + lzf), `memcached` (igbinary, json, session). `meta.sharedExtensionRequires`: redis ve memcached'den **önce** igbinary yüklenmeli.
- Statik bağımlılıklar (19): OpenSSL, PCRE2, zlib, libxml2, libxslt, SQLite, oniguruma, ICU 79.1, libzip, zstd, libsodium, libpng, libjpeg-turbo, libwebp, FreeType, curl, GMP, gettext (libintl), libmemcached-awesome. Sistemden (`/usr/lib`, kurala uygun): libiconv, libbz2, libedit (readline), libresolv, libc++; çerçeveler: CoreFoundation, CoreServices, SystemConfiguration.
- **Eklenti sembol denetimi** (`scripts/verify-plugin-symbols.sh`, her pakette): Yerel Xcode 27 bağlayıcısı, programın kendisinin çağırmadığı global fonksiyonları (ör. `zend_eval_string`) çıktıdan atıyordu; `-undefined dynamic_lookup` ile bağlanan uzantılarda bu semboller hata vermeden **NULL**'a bağlanıp ilk çağrıda çöküyordu (igbinary'nin MINIT'inde segfault). Çözüm: `php`/`php-fpm` `-Wl,-export_dynamic` ile bağlanır; denetim her `.so`'nun "dynamically looked up" sembollerinin paketteki bir program veya modül tarafından gerçekten dışa aktarıldığını doğrular. Apache (hem yerel hem CI derlemesi) bu denetimden geçiyor. Aynı denetim memcached'in `libhashkit` eksiğini de yakaladı.
- **CA deposu**: macOS'un `/private/etc/ssl/cert.pem` dosyası eksik (ör. example.com'un zincirlendiği SSL.com 2022 kökleri yok). OpenSSL/curl'ün varsayılan deposu bu dosya olsa da, Burox her zaman kendi Mozilla tabanlı `certs/cacert.pem`'ini `curl.cainfo` ve `openssl.cafile` ile vermeli (PLAN §3.4 zaten böyle). Smoke test de curl.se'nin Mozilla paketini kullanır.
- Boyut: ICU verisi (~30 MB) hem `php` hem `php-fpm` içinde statik olduğundan arşivler ~35 MB (xz). Paylaşılan bir `.dat` dosyası boyutu düşürürdü ama çalışma anında `ICU_DATA` yolu gerektirir; şimdilik tercih edilmedi.
- Lisans notu: libintl (LGPL-2.1+) ve GMP (LGPLv3/GPLv2) statik bağlanır. LGPL'nin "yeniden bağlayabilme" şartı, PHP kaynağının ve bu reponun derleme tariflerinin açık olmasıyla karşılanır; lisans metinleri `share/licenses/` altında, kaynak adresleri ve SHA-256'ları `PACKAGE.json` içindedir.
- Diğer: `include/` artık izinli kök dizin (phpize). PHP derlemeleri `-std=gnu17`, açıkça `-lresolv` ve sistem çerçeveleri, `--disable-rpath`, PECL modüllerinden kalan `LC_RPATH`'ler silinir, `php-config`'ten derleme yolları temizlenir; `libedit` için sistem kütüphanesini tarif eden özel bir `.pc` kullanılır. ICU ≥ 75 C++17 istediği için 8.2 öncesinin configure'ında `-std=c++11` → `-std=c++17`. Upstream anahtar notları: php.net anahtarlığındaki Ben Ramsey anahtarının uzatılmış öz-imzası keys.openpgp.org'dan eklendi (8.1.34 imzası için); libjpeg-turbo'nun imza anahtarı hiçbir resmi kaynakta bulunamadığı için GitHub release digest'iyle, libpng/libmemcached/PECL ise imza yayımlamadıkları için ilk indirmede sabitlenir.
