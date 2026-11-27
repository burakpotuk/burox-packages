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

## ADR-006: cloudflared macOS 15 gerektiriyor (2026-11-27, prompt 06) — kullanıcı onayı bekliyor
- Bağlam: Resmi `cloudflared-darwin-arm64` binary'leri en az 2025.11'den beri `LC_BUILD_VERSION minos 15.0`. `verify-relocatable` bunu yakaladı.
- Seçenekler: (a) resmi, Cloudflare imzalı binary'yi koru; pakete `minMacOS: "15.0"` yaz, uygulama macOS 14'te tüneli "macOS 15 gerekir" diye gösterir. (b) cloudflared'i Go ile kaynaktan macOS 14 hedefiyle derle (Cloudflare imzası kaybolur, ad-hoc imza olur; Go toolchain + vendored bağımlılıklar gerekir).
- Karar (geçici): (a). `versions.json` paket başına `minMacOS` alanını yalnızca `"kind": "binary"` paketlerde kabul eder; denetim o değere göre yapılır ve manifest girdisi bunu taşır.
- Sonuçlar / riskler: macOS 14 kullanıcıları paylaşım tünelini kullanamaz. (b) istenirse ayrı bir tarif olarak eklenebilir.

## ADR-007: Manifest imzası ve barındırma (2026-11-27, prompt 06)
- Karar: `manifest.json` + `manifest.json.sig`, sabit adresli `manifest` Release'inde. İmza: manifest baytları üzerinde saf Ed25519 (`openssl pkeyutl -sign -rawin`), dosyada 64 bayt imzanın tek satır base64'ü (Apple CryptoKit `Curve25519.Signing.PublicKey.isValidSignature` ile doğrulandı). İki anahtar: birincil (GitHub Secret `MANIFEST_SIGNING_KEY`) + yedek (yalnızca parola yöneticisinde). `sign-manifest.sh` anahtarı diske yazmaz (pipe), `set +x`, ve secret'ın public yarısı repodaki `keys/manifest-public-*.pem`'lerden biriyle eşleşmezse imzalamayı reddeder. CI her yayında: imzala → doğrula → 1 baytı değiştirilmiş kopyanın **reddedildiğini** doğrula → yükle → istemcinin indirdiğini tekrar indirip doğrula.
- Sonuçlar / riskler: İki dosyanın yüklenmesi atomik değil; kısa bir anda imza uyuşmazlığı görülebilir → uygulama doğrulama hatasında eski önbelleği kullanıp sonra tekrar denemeli. Eski (geri alınmış) bir manifestin tekrar sunulmasına karşı uygulama, önbelleğindekinden daha eski `generatedAt` taşıyan manifesti reddetmeli (uygulama tarafı prompt'una not).
- Gözlem (2026-11-27, ilk CI yayını): `releases/download/manifest/manifest.json` adresi, yeni yüklemeden sonra birkaç dakika **önceki** dosyayı sunabiliyor (benzersiz bir sorgu parametresi, ör. `?v=<zaman>`, taze kopyayı getiriyor). Eski çift kendi içinde tutarlı ve imzalı olduğu için güvenlik sorunu değil. Uygulama için öneri: `manifest.json` ve `.sig`'i **aynı** benzersiz sorgu parametresiyle indir; imza tutmazsa birkaç saniye sonra yeni bir parametreyle bir kez daha dene. CI'daki "Verify what clients download" adımı da aynı yöntemi kullanıyor.
