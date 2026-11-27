> **Not:** Asıl kopya uygulama reposundadır (`burakpotuk/burox`); değişiklikler orada yapılır, buraya kopyalanır.

# Burox — Ana Plan (Master Spec)

> Bu dosya projenin **tek doğruluk kaynağıdır**. Her prompt bu dosyaya atıf yapar.
> Bir karar değişirse önce bu dosya güncellenir, sonra kod. Karar geçmişi `docs/DECISIONS.md` içinde tutulur.

## 0. Özet

Burox, Apple Silicon Mac'ler için native (SwiftUI) bir yerel PHP geliştirme ortamıdır. MAMP Pro / Laravel Herd / ServBay benzeri:

- Site başına **PHP sürümü** (7.4 → en yeni) ve site başına **web sunucusu** (Nginx veya Apache)
- **MariaDB ve MySQL**, birden fazla sürüm yan yana
- Yerleşik **mini DNS** ile `*.test` domainleri, joker alt alan adları
- Makineye özel, **isim kısıtlı yerel CA** ile uyarısız HTTPS
- Gerçek domain: **lokalde ezme**, **Let's Encrypt (DNS-01)**, **paylaşım tüneli**, **LAN paylaşımı**
- php.ini ve Apache/Nginx conf için **görsel form + doğrulamalı ham editör**
- Mail yakalayıcı, tek tık Xdebug, canlı loglar, ek servisler (Redis, Memcached, Meilisearch, MinIO)
- Proje şablonları, repoda ortam dosyası, CLI
- DB yöneticisi, otomatik yedek + snapshot, site dışa/içe aktarma, yavaş sorgu izleme
- Menü çubuğu paneli, ⌘K komut paleti, Doktor, kaynak grafikleri
- Türkçe + İngilizce arayüz

Hedef kitle: kişi + ekip içi kullanım. Lisans sistemi yok.

## 1. Sabit kararlar

| Konu | Karar |
|---|---|
| Platform | macOS 14 Sonoma ve üzeri, **sadece arm64** |
| UI | SwiftUI (gerektiğinde AppKit köprüsü), Observation (`@Observable`) |
| Proje üretimi | **XcodeGen** (`project.yml`) — `.xcodeproj` elle düzenlenmez, git'e konmaz |
| Dil | Swift 6 dil modu hedeflenir (strict concurrency); kod, yorum ve tanımlayıcılar **İngilizce** |
| UI metinleri | String Catalog (`Localizable.xcstrings`), TR + EN eksiksiz |
| Kalıcı durum | SQLite (GRDB.swift), sahibi Agent |
| Sırlar | macOS Keychain |
| Paketler | İsteğe bağlı indirme; kendi CI'mız derler; Ed25519 imzalı manifest + SHA-256 |
| İmzalama | Geliştirmede Xcode "Personal Team"; dağıtımdan önce Developer ID + notarization |
| Güncelleme | Sparkle 2 (EdDSA imzalı appcast) |
| Marka | Ad: Burox · CLI: `burox` · Logo: **deve** (bkz. §3.13) |
| Geliştirme aracı | Claude Code; her prompt sonunda derlenen, çalışan uygulama |

## 2. Mimari

### 2.1 Bileşenler

```
┌──────────────────────────┐      XPC (Mach)      ┌──────────────────────────────┐
│ Burox.app (UI)     │ ───────────────────▶ │ Agent (kullanıcı, LaunchAgent)│
│ SwiftUI, menü çubuğu      │ ◀─── olay akışı ──── │ supervisor, DNS, config,     │
└──────────────────────────┘                      │ sertifika, paket, yedek       │
┌──────────────────────────┐      XPC (Mach)      │                              │
│ CLI `burox`          │ ───────────────────▶ │                              │
└──────────────────────────┘                      └──────────────┬───────────────┘
                                                                  │ XPC (sadece beyaz liste)
                                                   ┌──────────────▼───────────────┐
                                                   │ Helper (root, LaunchDaemon)   │
                                                   │ resolver, hosts bloğu, pf,    │
                                                   │ DNS önbellek temizleme        │
                                                   └──────────────────────────────┘
Agent'ın başlattığı süreçler (hepsi KULLANICI olarak, hepsi 127.0.0.1):
  Ön Nginx · Apache · PHP-FPM (sürüm başına normal + debug) · MariaDB/MySQL örnekleri ·
  Mailpit · Redis · Memcached · Meilisearch · MinIO · cloudflared · lego
```

| Bileşen | Çalışma kimliği | Görev |
|---|---|---|
| **App** | kullanıcı | Arayüz. Hiçbir sunucu sürecini doğrudan yönetmez; her şeyi Agent'a sorar. Kapatılınca servisler çalışmaya devam eder. |
| **Agent** | kullanıcı, `SMAppService.agent` | Tek durum sahibi. Süreç denetimi, config üretimi, DNS sunucusu, sertifikalar, paket indirme, yedek zamanlayıcı, log/metrik akışı. Mach servisi: `com.potux.burox.agent` |
| **Helper** | root, `SMAppService.daemon` | Sadece root gerektiren, **beyaz listeli** birkaç işlem (bkz. §4.3). Mach servisi: `com.potux.burox.helper` |
| **CLI** | kullanıcı | `burox` komutu; Agent'a XPC ile bağlanır. Ayrıca `php`, `composer`, `wp` shim'leri. |
| **Paket deposu** | GitHub Actions | `burox-packages` reposu: tüm binary'leri derler, test eder, imzalı manifest yayınlar. |

Neden ayrı Agent? UI kapanınca servisler durmasın, CLI ile UI aynı durumu görsün, ve root'a sadece minimum yüzey açılsın.

### 2.2 İstek akışı (bir tarayıcı isteği)

1. Tarayıcı `https://proje.test` ister.
2. macOS, `/etc/resolver/test` dosyası sayesinde sorguyu Agent'ın DNS sunucusuna (127.0.0.1:15353) yollar → cevap `127.0.0.1`.
3. Bağlantı 127.0.0.1:443'e gider; **pf** kuralı bunu 127.0.0.1:18443'e yönlendirir (root gerekmeden kullanıcı süreci dinleyebilsin diye).
4. **Ön Nginx** TLS'i sonlandırır (yerel CA'dan imzalı sertifika).
5. Site tipi **nginx** ise: Nginx doğrudan dosyaları sunar, `.php` isteklerini sitenin PHP sürümünün **PHP-FPM** unix soketine iletir.
6. Site tipi **apache** ise: Nginx isteği `http://127.0.0.1:18081` adresindeki **Apache**'ye iletir (`X-Forwarded-Proto: https`). Apache `.htaccess` işler ve PHP'yi `mod_proxy_fcgi` ile aynı FPM soketine yollar.
7. Site Xdebug açıksa istek o sürümün **debug FPM** soketine gider (Xdebug yüklü ayrı master). Kapalı sitelerde Xdebug hiç yüklenmez → performans etkisi sıfır.

### 2.3 Dizin düzeni

Kök: `~/Library/Application Support/Burox` → kısa, boşluksuz takma ad: **`~/.burox`** (symlink). Üretilen tüm config'ler takma adın mutlak yolunu kullanır (boşluk sorunu ve 104 karakterlik unix soket yolu sınırı yüzünden).

```
~/.burox/
  packages/<paket>/<sürüm>/        indirilen binary'ler (salt okunur kabul edilir)
  etc/
    nginx/   nginx.conf, sites/<site-id>.conf, custom/<site-id>.conf, shares/
    apache/  httpd.conf, sites/<site-id>.conf, custom/<site-id>.conf
    php/<ver>/ php.ini, conf.d/{10-extensions,20-app-defaults,90-managed,99-user}.ini,
               conf.d-debug/30-xdebug.ini, fpm.conf, fpm-debug.conf, pool.d/*.conf
    mariadb-<ver>/my.cnf (+ 99-user.cnf), mysql-<ver>/my.cnf
    services/<servis>.conf
  data/<servis>-<ver>/             veri klasörleri (DB datadir, redis, meilisearch, minio, mailpit)
  run/                             soketler, pid dosyaları (0700)
  logs/  services/, sites/<domain>.{access,error,php}.log, agent.log
  certs/ ca/ca.crt (sadece public), sites/<domain>.{crt,key}, override/<domain>/, letsencrypt/<domain>/
  backups/ db/<instance>/<db>/..., config-history/<timestamp>/, exports/
  state/ app.sqlite, sites-index.json (shim'ler için hızlı okuma)
  bin/   php, composer, wp, burox  (shim'ler)
  tmp/
```

Varsayılan site klasörü: `~/Sites` (ayarlardan değişir). İzinler: kök 0700, anahtarlar ve soketler 0600.

### 2.4 Port düzeni (hepsi Ayarlar > Gelişmiş'ten değişebilir)

| Servis | Adres | Not |
|---|---|---|
| Ön Nginx HTTP / HTTPS | 127.0.0.1:18080 / 18443 | pf ile 80 → 18080, 443 → 18443 (lo0) |
| Apache arka uç | 127.0.0.1:18081 | sadece ön Nginx'ten |
| Paylaşım geçitleri (tünel) | 127.0.0.1:18090–18099 | aktif paylaşım başına bir port |
| LAN paylaşımı | `<LAN-IP>`:18100–18199 | varsayılan kapalı, süreli |
| DNS | 127.0.0.1:15353 UDP+TCP | 5353 mDNS'tir, kullanılmaz |
| Mailpit SMTP / Web | 127.0.0.1:1025 / 8025 | `https://mail.burox.test` ile de açılır |
| MariaDB / MySQL | 3306, 3307, sonra +1 | her örnek kendi portu ve soketi |
| Redis / Memcached | 6379 / 11211 | |
| Meilisearch | 7700 | master key otomatik üretilir |
| MinIO API / Konsol | 9000 / 9001 | |
| Xdebug istemci portu | 9003 | IDE dinler |

Ayrılmış host adları: `burox.test` (site listesi sayfası), `mail.burox.test`, `db.burox.test`. Kullanıcı bu adları site olarak alamaz.

### 2.5 Kod düzeni (uygulama reposu)

```
project.yml                 XcodeGen tanımı
Makefile                    make bootstrap | build | run | test | install-dev | lint | itest
Apps/App/                   SwiftUI uygulaması (+ DesignSystem/, Features/<Özellik>/)
Apps/Agent/                 LaunchAgent yürütülebiliri
Apps/Helper/                LaunchDaemon yürütülebiliri
Apps/CLI/                   swift-argument-parser
Packages/Core/              yerel SPM paketi (birden fazla target):
  CoreModels                Site, Service, PackageRef, Settings, ... (Codable, Sendable)
  CorePaths                 tüm yolların tek kaynağı
  CoreStore                 GRDB şeması, migration'lar
  CoreXPC                   protokoller, mesaj tipleri, sürüm el sıkışması
  CoreValidation            domain, TLD, port, ini anahtarı, hosts girdisi doğrulayıcıları
  CoreConfigGen             nginx/apache/fpm/my.cnf üreticileri (şablon + tipli model)
  CoreCerts                 CA ve sertifika (swift-certificates)
  CorePackages              manifest, imza doğrulama, indirme, kurulum
  CoreServices              süreç denetimi soyutlamaları (Agent kullanır)
Resources/Templates/        mustache şablonları (nginx, apache, fpm, php, mariadb, mysql, ...)
Tests/                      birim + snapshot (golden file) testleri
docs/                       PLAN.md, PROGRESS.md, DECISIONS.md, SECURITY.md, spike-report.md
prompts/                    bu plandaki sıralı görevler
```

SPM bağımlılıkları (yalnızca bunlar; yenisi gerekirse `DECISIONS.md`'ye gerekçe yazılır): GRDB.swift, swift-certificates, swift-crypto, swift-asn1, swift-argument-parser, Sparkle, swift-mustache (hummingbird-project).

## 3. Özellik spesifikasyonu

### 3.1 Paket sistemi

- Ayrı repo: `burakpotuk/burox-packages` (önerilen: public; içerik açık kaynak yazılımların derlemeleri, her paketin LICENSE dosyası içinde).
- CI, `macos-15` (arm64) runner'larda derler (`macos-14` runner'ları 2026-11-02'de kaldırıldı; ADR-003). `MACOSX_DEPLOYMENT_TARGET=14.0`.
- **Taşınabilirlik kuralı:** Her binary ve `.so` dosyası sadece `/usr/lib/` ve `/System/` altındaki kütüphanelere bağlanabilir. Diğer tüm bağımlılıklar statik linklenir. CI `otool -L` ile doğrular, ihlalde build kırılır.
- Kaynak tarball'ları sabitlenmiş SHA-256 ile indirilir; upstream GPG/imza varsa doğrulanır.
- Her paket CI'da smoke test'ten geçer (`php -v`, `php -m` beklenen liste, `nginx -t`, `httpd -t`, DB başlat/sorgula/durdur).
- Arşiv: `<ad>-<sürüm>-darwin-arm64.tar.xz`, GitHub Releases'a yüklenir.
- **Manifest** (`manifest.json` + `manifest.json.sig`):
  ```json
  { "schemaVersion": 1, "generatedAt": "2026-11-27T10:00:00Z",
    "packages": [ { "name": "php", "channel": "8.4", "version": "8.4.x", "arch": "arm64",
      "url": "https://github.com/.../php-8.4.x-darwin-arm64.tar.xz",
      "sha256": "…", "size": 41234567, "minMacOS": "14.0",
      "meta": { "extensions": ["intl", "gd", "..."], "sharedExtensions": ["xdebug", "opcache", "redis", "..."] } } ] }
  ```
  İmza: manifest baytları üzerinde Ed25519; `manifest.json.sig` = 64 baytlık imzanın tek satır base64'ü. Uygulamada 2 public key gömülü (anahtar rotasyonu için). İmzasız veya hatalı imzalı manifest **reddedilir**. Adres: `https://github.com/burakpotuk/burox-packages/releases/download/manifest/manifest.json` (+ `.sig`). Paket girdisindeki `minMacOS` 14.0'dan büyükse (ör. cloudflared: 15.0, ADR-006) uygulama o paketi eski macOS'ta sunmaz.
- Uygulama: indir → SHA-256 doğrula → `tmp/` içine aç → atomik `rename` ile `packages/<ad>/<sürüm>/`. Kullanımdaki sürüm silinemez (hangi sitelerin kullandığı gösterilir).
- Paket listesi:

| Paket | Kaynak | Sürümler |
|---|---|---|
| PHP (+ shared: opcache, xdebug, redis, igbinary, apcu, memcached) | kaynaktan derleme | 7.4, 8.0, 8.1, 8.2, 8.3, 8.4, 8.5 ve sonrası (her dalın son yaması) |
| Nginx (ssl, http_v2, realip, sub, auth_request, stub_status) | kaynaktan | güncel stable |
| Apache httpd (event MPM; rewrite, headers, proxy, proxy_fcgi, remoteip, setenvif, expires, deflate) | kaynaktan | güncel 2.4.x |
| MariaDB | kaynaktan (resmi macOS binary'si yok) | aktif LTS dalları |
| MySQL | Oracle'ın resmi macOS arm64 tarball'ı, yeniden paketlenir | 8.0 (eski projeler için), 8.4 LTS, güncel |
| Mailpit, cloudflared, lego, Meilisearch | resmi sürüm binary'leri, checksum doğrulanarak yeniden paketlenir (cloudflared upstream gereği macOS 15+) | güncel |
| Redis, Memcached | kaynaktan | güncel |
| MinIO | dağıtım politikası değişti; kaynaktan derleme veya alternatif — prompt 08'de karar | — |
| Composer, WP-CLI, Adminer, phpMyAdmin | resmi dosyalar, imza/checksum doğrulanarak | güncel |

### 3.2 Servis denetimi (Agent)

- Her servis bir `ManagedService`: komut, argümanlar, ortam, çalışma dizini, log dosyaları, sağlık kontrolü, reload sinyali.
- Başlatma `posix_spawn` (Foundation `Process`) ile, argüman dizisiyle; **asla** shell string birleştirme yok.
- Yeniden başlatma politikası: üstel bekleme; 60 sn içinde 5 çöküşte "hatalı" durumuna geçer, kullanıcıya bildirir.
- Durdurma: uygun sinyal (nginx: QUIT, apache: graceful-stop, fpm: QUIT, DB: mysqladmin shutdown veya TERM), zaman aşımında KILL.
- Reload: nginx HUP, apache USR1 (graceful), fpm USR2.
- Agent açılışta pid dosyalarındaki eski süreçleri temizler; **sinyal göndermeden önce sürecin yürütülebilir yolunun `packages/` altında olduğunu doğrular**.
- Uyku/uyanma ve ağ değişikliğinde: pf kuralları, resolver, DNS ve servis sağlığı yeniden kontrol edilir.
- "Son durumu hatırla": her servisin istenen durumu SQLite'ta tutulur; Agent açılışta geri yükler.
- Metrikler: 2 sn'de bir süreç ağacı CPU/RAM (`libproc`), 30 dk halka tampon, UI'ya akış.

### 3.3 Domain ve DNS

- Varsayılan yerel uzantı `.test`. Seçenekler: `.test`, `.internal`, `.localhost` veya IANA listesinde olmayan özel bir uzantı. `.dev`, `.app`, `.local` ve gerçek TLD'ler **engellenir** (HSTS ve mDNS sorunları).
- Agent içinde küçük bir DNS sunucusu (Network framework, UDP+TCP 127.0.0.1:15353): yerel uzantıdaki her ad ve alt ad için `A 127.0.0.1` döner. AAAA için boş cevap. Diğer sorgulara `REFUSED`.
- Helper `/etc/resolver/<tld>` dosyasını yazar: `nameserver 127.0.0.1` + `port 15353`.
- Joker alt alan: site ayarında açıksa `*.proje.test` de o siteye gider (sertifikada `*.proje.test` SAN'ı).

### 3.4 SSL

- **Yerel CA:** İlk açılışta makineye özel üretilir. ECDSA P-256, 5 yıl. Adı: `Burox Local CA (<kullanıcı>@<makine>)`.
- **Name Constraints** (kritik uzantı): izin verilen DNS alt ağaçları = seçili yerel uzantı(lar) + `localhost`; izin verilen IP = `127.0.0.0/8`, `::1`. CA anahtarı çalınsa bile gerçek siteler için sertifika üretilemez.
- CA özel anahtarı Keychain'de (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). Diske sadece public sertifika yazılır.
- Güven: Security framework ile **kullanıcı alanında** güvenilir kök (`SecTrustSettingsSetTrustSettings`, user domain). macOS bir kez şifre sorar. Root yetkisi gerekmez.
- Yerel uzantı değişirse CA yeniden üretilir (eski CA güvenden çıkarılır, silinir).
- **Site sertifikası:** ECDSA P-256, 397 gün, SAN: domain + takma adlar (+ joker). Bitime 30 gün kala otomatik yenilenir. Anahtar dosyası 0600.
- **CA paketi:** Mozilla kök paketi + yerel CA birleştirilip `certs/cacert.pem` yazılır. PHP'de `curl.cainfo` ve `openssl.cafile` buna ayarlanır. Böylece bir site diğerine `https://` ile curl atabilir. CLI shim'leri `NODE_EXTRA_CA_CERTS` ve `SSL_CERT_FILE` için ipucu gösterir.
- Firefox: Doktor, Firefox'un sistem köklerini kullanıp kullanmadığını kontrol eder ve rehberlik eder.

### 3.5 Web sunucuları

**Ön Nginx** (her zaman çalışır):
- 18080: HTTP → HTTPS yönlendirme (site başına kapatılabilir).
- 18443: HTTP/2, her site için `server` bloğu.
- Bilinmeyen host → şık bir 404 sayfası: "Bu domain tanımlı değil" + `burox://new-site?domain=<ad>` bağlantısı (uygulamada yeni site sihirbazını açar).
- `burox.test` → tüm sitelerin listesi.
- `client_max_body_size` site başına **otomatik**: sitenin etkin `post_max_size` ve `upload_max_filesize` değerlerinin büyüğü. Klasik "413 Request Entity Too Large" hatası yaşanmaz.

**Nginx tipi site** şablonları: `generic-php`, `laravel`, `wordpress`, `symfony`, `static`. Klasör eklenirken framework otomatik algılanır (`composer.json` içinde `laravel/framework`, `symfony/framework-bundle`; `wp-load.php`; sadece `index.html`).

**Apache tipi site:** Ön Nginx `proxy_pass http://127.0.0.1:18081` (Host, X-Forwarded-For/Proto, websocket upgrade başlıkları). Apache vhost: `AllowOverride All`, `mod_rewrite`, `SetEnvIf X-Forwarded-Proto https HTTPS=on`, `RemoteIPHeader X-Forwarded-For`, PHP için `SetHandler "proxy:unix:<soket>|fcgi://localhost"`. FPM ile `.htaccess` içindeki `php_value` çalışmaz; arayüz bunu açıklar ve `.user.ini` önerir.

**Config motoru** (tüm config dosyaları için ortak):
1. Tipli modelden (Site, Settings) mustache şablonu ile üret. Tüm kullanıcı girdileri doğrulanır ve kaçış uygulanır.
2. Geçici dizine yaz → `nginx -t -p … -c …` / `httpd -t -f …` / `php-fpm -t -y …` ile test et.
3. Başarılıysa: mevcut hali `backups/config-history/<zaman>/` altına kopyala (son 50), yeni dosyaları atomik taşı, reload sinyali gönder.
4. Başarısızsa: hiçbir şey değişmez; hata satırı kullanıcının özel bloğuna eşlenir ve gösterilir.

**Özel blok:** Site başına `custom/<site-id>.conf` (nginx için `server` bloğu içine, apache için `VirtualHost` içine include edilir). Arayüzde renkli editörde düzenlenir. "Geçmiş" sekmesi: sürümler, fark görünümü, tek tıkla geri yükleme.

### 3.6 PHP

- Sürüm başına iki FPM master:
  - **normal**: `fpm.conf`, Xdebug yok.
  - **debug**: `fpm-debug.conf`, ek ini dizini `conf.d-debug` ile Xdebug yüklü. Sadece en az bir Xdebug'lı site o sürümü kullanıyorsa çalışır.
- Havuzlar: sürümün varsayılan havuzu (`pm = ondemand`, boşta 30 sn) + **ezmesi olan her site için** ayrı ondemand havuz (`php_admin_value[...]`).
- Her site, her istekte kendi PHP `error_log` dosyasını belirler (nginx `fastcgi_param PHP_VALUE`, apache `ProxyFCGISetEnvIf`). Her site her istekte değeri set ettiği için FPM işçileri arasında sızıntı olmaz.
- ini yığını ve öncelik (düşükten yükseğe): `php.ini` (php.ini-development tabanlı) → `10-extensions.ini` (uzantı aç/kapa) → `20-app-defaults.ini` (cacert, sendmail_path=Mailpit, timezone=sistem, error_log) → `90-managed.ini` (görsel form) → `99-user.ini` (ham editör) → site havuzu ezmeleri.
- **Görsel form alanları:** memory_limit, max_execution_time, max_input_time, max_input_vars, upload_max_filesize, post_max_size, display_errors, error_reporting (ön ayarlar), date.timezone, opcache.enable, opcache.validate_timestamps, opcache.revalidate_freq, short_open_tag, session.gc_maxlifetime, realpath_cache_size. Ayrıca uzantı listesi (açma/kapama anahtarları).
- **Etkin değer görünümü:** Her ayar için gerçek değer ve kaynağı ("PHP 8.4 geneli", "site ezmesi", "varsayılan"). Değerler aynı ini yığınıyla `php -r 'echo json_encode(ini_get_all(null,false));'` çalıştırılarak hesaplanır.
- **Kaydetmeden önce doğrulama:** geçici yığınla `php -r 1` çalıştırılır; "Unknown/Invalid" uyarıları varsa kaydedilmez, satır gösterilir.

### 3.7 Veritabanları

- Her kurulu sürüm bir **örnek**: kendi datadir, port, soket, `my.cnf` (+ `99-user.cnf`), loglar.
- İlk başlatma: MariaDB `mariadb-install-db`, MySQL `mysqld --initialize-insecure`, ardından root şifresi rastgele üretilir ve Keychain'e yazılır. Sadece `bind-address=127.0.0.1`.
- Arayüz: örnek durumu, port, root şifresini kopyala, veritabanları ve kullanıcılar (oluştur/sil/şifre sıfırla), `my.cnf` form + ham editör (php.ini ile aynı desen).
- Site ile ilişki: sitenin veritabanları ve **siteye özel DB kullanıcısı** (rastgele şifre). Yavaş sorguların hangi siteden geldiği bu kullanıcıdan anlaşılır.
- **Yedek:** veritabanı başına zamanlama (günlük HH:mm, son N), `mariadb-dump/mysqldump --single-transaction --routines --triggers --events | gzip`. Mac uyuyorken kaçan yedek uyanınca alınır.
- **Snapshot:** anlık, isimli dump; geri yükleme = DB'yi düşür, yeniden oluştur, içe aktar (ilerleme çubuğuyla). Geri yüklemeden önce otomatik "geri yükleme öncesi" snapshot alınır. CLI: `burox db snapshot <db> --name before-migration`.
- **Yavaş sorgu:** `slow_query_log` açık, `long_query_time` ayarlanabilir (varsayılan 1 sn). Agent logu ayrıştırır, sorguları parmak izine göre gruplar (literaller `?` olur). Tablo: sayı, ortalama/maks süre, site, örnek sorgu. "EXPLAIN" düğmesi örneği aynı DB'de çalıştırır.
- **DB yöneticisi:** Adminer ve phpMyAdmin, uygulamanın iç PHP havuzuyla `https://db.burox.test` altında. Otomatik giriş tek kullanımlık token ile (Adminer eklentisi / phpMyAdmin `signon`). Tünel ve LAN geçitlerinden **asla** erişilemez.

### 3.8 Gerçek domain

- **Lokalde ezme:** Kullanıcı bir siteye `musteri.com`, `www.musteri.com` ekler → Helper `/etc/hosts` içindeki işaretli bloğa `127.0.0.1` ve `::1` satırları yazar ve DNS önbelleğini temizler.
  - Sertifika: Let's Encrypt sertifikası varsa o; yoksa **o domaine özel, isim kısıtlı küçük bir "ezme CA'sı"** üretilir, güvenilir yapılır. Ezme kapatılınca güvenden çıkarılır ve anahtarı silinir.
  - Menü çubuğunda turuncu rozet: "Ezme aktif: musteri.com". Opsiyonel otomatik bitiş (1 sa / 8 sa / kalıcı).
  - Doktor, tarayıcıların "güvenli DNS" (DoH) ayarının ezmeyi atlayabileceği durumları kontrol eder ve rehberlik eder.
- **Let's Encrypt:** `lego` ile DNS-01 doğrulama (joker dahil). Cloudflare arayüzde birinci sınıf; diğer sağlayıcılar lego'nun ortam değişkenleriyle. API token'ı Keychain'de, sadece lego sürecinin ortamına verilir. Staging anahtarı (rate limit'e takılmamak için). Bitime 30 gün kala yenileme.
- **Paylaşım tüneli:** `cloudflared`.
  - *Hızlı tünel* (hesapsız, rastgele `*.trycloudflare.com` adresi) ve *adlandırılmış tünel* (kullanıcının Cloudflare hesabı ve kendi domaini).
  - Her aktif paylaşım için ön Nginx'te ayrı geçit (127.0.0.1:1809x): **varsayılan olarak Basic Auth zorunlu** (kullanıcı adı/şifre otomatik üretilir), DB araçları ve uygulama alt alanları kapalı, erişim logu tutulur.
  - Süre: 15 dk / 1 sa / 4 sa / elle durdurana kadar. Telefon için QR kod.
  - "URL yeniden yazma" seçeneği (`sub_filter`): yanıtlardaki `https://proje.test` adresini genel adresle değiştirir (WordPress gibi mutlak URL kullanan sistemler için).
- **LAN paylaşımı:** Varsayılan kapalı. Site başına port (18100+), `listen <LAN-IP>:<port>`, sadece HTTP (ekip arkadaşları yerel CA'ya güvenmez; CA **asla** paylaşılmaz). Sadece özel IP aralıkları (`10/8`, `172.16/12`, `192.168/16`), opsiyonel Basic Auth, süre sınırı, QR kod. IP değişince dinleyiciler güncellenir. Veritabanı LAN'a açılmaz.

### 3.9 Geliştirici araçları

- **Mail yakalayıcı (Mailpit):** PHP `sendmail_path` Mailpit'e gider. SMTP 127.0.0.1:1025 (framework `.env` şablonlarına yazılır). Arayüz: Mailpit REST API ile native liste + HTML önizleme için WKWebView; yeni mailde macOS bildirimi (konu + site).
- **Xdebug:** Site başına anahtar. Açıkken o sitenin istekleri debug FPM'e gider. Mod: `trigger` (varsayılan) veya "her istekte". VS Code `launch.json` ve PhpStorm sunucu ayarı **onayla** üretilir (`PHP_IDE_CONFIG=serverName=<domain>`). PHP 7.4 için Xdebug 3.1 dalı.
- **Canlı log izleyici:** Kaynaklar: site access/error/php logları, servis logları, DB error/slow, Agent. Kaynak ve seviye filtreleri, arama, takip/duraklat. PHP hata satırlarında `dosya:satır` ayrıştırılır → tıklayınca seçili editörde açılır (VS Code, Cursor, PhpStorm, Zed, Sublime). Log döndürme: 10 MB × 5.
- **Ek servisler:** Redis, Memcached, Meilisearch, MinIO. Tek tıkla indir/başlat, port, veri klasörü, log. Meilisearch master key ve MinIO kimlik bilgileri rastgele üretilir, Keychain'de tutulur, kopyala düğmesi vardır.

### 3.10 Proje ve ekip

- **Proje şablonları:** Laravel, WordPress, Symfony, Boş PHP. Hepsi tek akışta klasör + domain + sertifika + DB ve kullanıcı + `.env`/`wp-config.php` + tarayıcıda açma yapar. Composer, sitenin PHP sürümüyle çalışır. WordPress, wordpress.org'dan checksum doğrulamasıyla iner, WP-CLI ile kurulur (yönetici şifresi bir kez gösterilir ve Keychain'e yazılır). İlerleme ekranında canlı çıktı görünür.
- **Repoda ortam dosyası:** `.burox.json` (JSON Schema ile editörde otomatik tamamlama):
  ```json
  { "version": 1, "domain": "proje", "aliases": ["api.proje"],
    "server": "nginx", "php": "8.3", "public": "public", "framework": "laravel",
    "php_ini": { "memory_limit": "512M" }, "extensions": ["intl", "gd"],
    "databases": [ { "engine": "mariadb", "version": "11.4", "name": "proje" } ],
    "services": ["redis"], "xdebug": false }
  ```
  - **Sadece bildirimsel**, beyaz listeli anahtarlar. Komut çalıştırma yok, özel sunucu direktifi yok.
  - Algılandığında veya değiştiğinde (FSEvents) **fark ekranı + onay**; asla otomatik uygulanmaz.
  - CLI: `burox init` (mevcut siteden dosya üretir), `burox up` (onayla uygular).
- **CLI:** `status`, `start|stop|restart [servis]`, `sites`, `link [domain]`, `unlink`, `open`, `php use <sürüm> [--site]`, `php ini get|set`, `db list|create|drop|shell|snapshot|restore|dump`, `share [--lan] [--minutes N]`, `logs [site] -f`, `xdebug on|off`, `mail`, `doctor`, `init`, `up`, `which php`. Her komutta `--json` seçeneği.
- **Shim'ler:** `php` (cwd'den yukarı doğru site köküne veya `.burox.json`'a bakar, yoksa global sürüm; `sites-index.json`'dan okur, Agent'a sormaz → hızlı), `composer`, `wp`. Shell entegrasyonu `~/.zshrc` içine işaretli bir blok ekler; eklenecek satır önce gösterilir, onay istenir.

### 3.11 Site dışa/içe aktarma

- Paket: `.buroxsite` (zip): `manifest.json` (site ayarları, **sırlar hariç**), `files/` (site klasörü; varsayılan hariç: `vendor`, `node_modules`, `.git`, log/önbellek klasörleri — boyut tahmini gösterilir), `db/*.sql.gz`.
- İçe aktarma: önizleme → hedef klasör ve domain seçimi (çakışma çözümü) → yeni DB ve kullanıcı → `.env` / `wp-config.php` DB bilgilerinin güncellenmesi (onayla) → domain değiştiyse WordPress için `wp search-replace`. Paketteki özel direktifler **onaysız uygulanmaz**.

### 3.12 Deneyim

- **Pencere düzeni (Sistem Ayarları tarzı):** solda kenar çubuğu, sağda detay.
  Kenar çubuğu: Genel Bakış · Siteler · PHP · Veritabanları · Servisler · Mail · Loglar · Paylaşım · Paketler · Doktor · Ayarlar.
  Site detay sekmeleri: Genel · PHP · Sunucu ve Conf · Domain ve SSL · Veritabanı · Paylaş · Loglar.
- **Genel Bakış:** servis kartları (durum + mini grafik), uyarılar (ezme aktif, tünel açık, sertifika bitiyor, Doktor bulguları), hızlı eylemler.
- **Menü çubuğu paneli** (`MenuBarExtra`, window stili): servis durum noktaları, tümünü başlat/durdur, site listesi (aç, klasörü göster, terminalde aç), global PHP sürümü, aktif ezme/tünel uyarıları ve geri sayım, mini kaynak grafiği.
- **Komut paleti (⌘K):** siteler, ekranlar ve eylemler içinde bulanık arama (`proje php.ini`, `mariadb yeniden başlat`, `yeni laravel`).
- **İlk kurulum sihirbazı:** 1) Ne olacak, hangi izinler neden 2) Yardımcı servis onayı (Sistem Ayarları > Giriş Öğeleri'ne yönlendirir, durumu canlı izler) 3) Yerel uzantı seçimi 4) Sertifika güveni 5) Paket seçimi (PHP sürümleri, DB, iki web sunucusu) ve indirme 6) Çakışma taraması 7) Shell entegrasyonu (opsiyonel) 8) İlk site.
- **Doktor:** her kontrol için durum, açıklama ve "Düzelt" eylemi. Kontroller: pf kuralları aktif mi, resolver dosyası, DNS cevap veriyor mu, CA güvenilir mi, sertifika bitişleri, port çakışmaları, çakışan yazılımlar (MAMP, Homebrew servisleri, Valet/Herd dnsmasq, macOS'un yerleşik httpd'si), config testleri, disk alanı, paket bütünlüğü (checksum'u yeniden doğrulama), Helper sürüm uyumu, Firefox güveni, tarayıcı DoH ile ezme uyarısı, shell PATH sırası (`which php` başka bir PHP'yi mi gösteriyor?).
- **Kaynak grafikleri:** Swift Charts; servis başına CPU/RAM, toplam; 5 dk / 30 dk görünüm.
- **Bildirimler:** servis çöktü, yedek başarısız, yeni mail, tünel bitti, sertifika yenilendi.
- **Erişilebilirlik:** her kontrolde VoiceOver etiketi, tam klavye navigasyonu, renk tek başına anlam taşımaz (ikon + metin).
- **Hata gösterimi:** satır içi banner: insan dilinde açıklama + "Ayrıntılar" (ham çıktı) + "Doktor'da aç".
- **Açılış:** Uygulama giriş öğesi olarak menü çubuğunda başlar. Servisler son durumlarına döner. Ana pencere açılmaz (ilk kurulum hariç).

### 3.13 Marka ve logo

- **Logo: deve.** Sade, özgün, düz (flat) bir deve silueti; yan profil, tek hörgüç veya iki hörgüç tasarımcının seçimine kalır ama her yerde aynı form kullanılır. Hazır stok/ünlü bir logodan türetilmez.
- **Kaynak dosyalar:** `Design/logo/` klasöründe. Kullanıcı kendi logosunu (`camel.svg`) buraya koyarsa o kullanılır. Yoksa Claude Code özgün bir SVG deve çizer ve **geçici logo** olarak işaretler (`Design/logo/PLACEHOLDER` dosyası).
- **Türetilen varlıklar:**
  - *Uygulama ikonu:* macOS ikon ızgarasına uygun yuvarlatılmış kare zemin + deve. Tüm boyutlar (16–1024) `AppIcon` setine üretilir (`make icons` hedefi, SVG'den `rsvg-convert` veya `sips` ile).
  - *Menü çubuğu ikonu:* tek renkli **template image** deve silueti (18 pt, @1x/@2x). Durumlar: normal; durmuş (soluk); hata (ünlem rozeti); uyarı (ezme/paylaşım aktif: nokta rozeti). Renk tek başına anlam taşımaz.
  - *Yerel sayfalar:* `burox.test` site listesi, "domain tanımlı değil" sayfası ve boş durum ekranlarında deve (inline SVG, açık/koyu tema uyumlu).
  - *İlk kurulum sihirbazı:* karşılama ekranında logo + "Burox'a hoş geldin".
  - *DMG:* arka planda deve ve "Applications'a sürükle" oku.
  - *CLI:* `burox --version` çıktısında küçük, tek satırlık ASCII deve (TTY değilse yazılmaz).
- **Renk:** Logo kum/deve tüyü tonlarında (ör. sıcak bej–karamel). Arayüzün geri kalanı sistem renklerini kullanır; marka rengi sadece `AccentColor` olarak ve ölçülü kullanılır.

## 4. Güvenlik modeli

Ayrıntılı tehdit modeli `docs/SECURITY.md` dosyasında (prompt 30'da güncellenir). Temel ilkeler:

### 4.1 İlkeler

1. **En az yetki:** Hiçbir sunucu süreci root çalışmaz. Root sadece Helper'da ve sadece §4.3'teki işlemler için.
2. **Varsayılan kapalı:** Her şey 127.0.0.1'de. LAN, tünel ve ezme opt-in, süreli ve arayüzde sürekli görünür.
3. **Doğrula, sonra uygula:** Her config testten geçmeden uygulanmaz. Her değişiklik geri alınabilir.
4. **Sırlar Keychain'de:** DB root şifreleri, CA anahtarları, API token'ları, tünel şifreleri. Loglara ve dışa aktarmalara sır yazılmaz.
5. **Güvenilmeyen girdi:** Repo ortam dosyası, içe aktarılan site paketi, indirilen paketler ve kullanıcı metin alanları güvenilmeyen girdi kabul edilir.

### 4.2 Kontroller

| Tehdit | Önlem |
|---|---|
| Kullanıcı hesabındaki zararlı yazılımın Helper'ı kötüye kullanması | XPC istemci kod imzası şartı (`setCodeSigningRequirement`); beyaz listeli işlemler; katı parametre doğrulama; hosts'a sadece 127.0.0.1/::1 yazılabilir → saldırgan bir domaini başka IP'ye yönlendiremez |
| CA anahtarının çalınması | Name Constraints; Keychain; makineye özel; ezme CA'ları domain başına ve kullanılmayınca imha |
| Ağdaki saldırgan | Tüm dinleyiciler 127.0.0.1; LAN paylaşımında özel aralık filtresi + süre + opsiyonel auth; DB asla LAN'da değil |
| Tünelle dışarı açılan site | Varsayılan Basic Auth, süre sınırı, DB araçları ve uygulama alt alanları kapalı, erişim logu |
| Tedarik zinciri (paketler) | Kendi CI; sabitlenmiş kaynak checksum'ları + upstream imza doğrulama; Ed25519 imzalı manifest; SHA-256 |
| Zararlı repo ortam dosyası | Bildirimsel beyaz liste, fark + onay, komut ve direktif yok |
| Config enjeksiyonu (ör. domain alanına `;` yazmak) | Doğrulayıcılar + şablonda kaçış + düşmanca girdilerle snapshot testleri |
| Yanlış sürece sinyal gönderme | Sinyal öncesi yürütülebilir yol doğrulaması |
| Güncelleme kanalının ele geçirilmesi | Sparkle EdDSA imzası, HTTPS |
| phpinfo / DB yöneticisinin açığa çıkması | Sadece uygulama alt alanlarında, sadece localhost, tek kullanımlık giriş token'ı |

### 4.3 Helper beyaz listesi (tamamı bu)

| İşlem | Parametreler ve doğrulama |
|---|---|
| `setResolver(tld, port)` | tld: `^[a-z][a-z0-9-]{1,30}$`, engelli liste dışında; port 1024–65535. Sadece `/etc/resolver/<tld>` yazar. |
| `removeResolver(tld)` | aynı doğrulama; sadece bizim yazdığımız dosyayı siler (içerikte imza yorumu aranır) |
| `setHostsBlock(entries)` | her girdi: geçerli hostname (RFC 1123, ≤253), IP **sadece** `127.0.0.1` veya `::1`; en fazla 500 girdi. `# BEGIN Burox` / `# END Burox` bloğunu atomik değiştirir, bloğun dışına dokunmaz. |
| `applyPortForwarding(http, https)` | hedef portlar 1024–65535; sabit şablondan `com.apple/burox` pf anchor'ına yükler; pf'yi etkinleştirir. |
| `removePortForwarding()` | anchor'ı boşaltır |
| `flushDNSCache()` | `dscacheutil -flushcache` + `killall -HUP mDNSResponder` |
| `version()` / `uninstallAll()` | sürüm el sıkışması; kaldırırken yukarıdakilerin hepsini geri alır |

Helper başka hiçbir işlem yapmaz; shell çağırmaz (`/sbin/pfctl` gibi sabit yollu araçları argüman dizisiyle çağırır). Her işlemi `/Library/Logs/Burox/helper.log` dosyasına yazar. Açılışta (RunAtLoad) pf ve resolver durumunu son bilinen yapılandırmaya göre geri yükler.

## 5. Test stratejisi

- **Birim testleri:** doğrulayıcılar (düşmanca girdiler dahil), ini ayrıştırıcı/yazıcı gidiş-dönüş, manifest imza doğrulama, slow log ayrıştırıcı, ortam dosyası ayrıştırıcı, CLI argümanları.
- **Snapshot (golden file) testleri:** örnek sitelerden üretilen nginx/apache/fpm/my.cnf çıktıları `Tests/Golden/` ile karşılaştırılır.
- **Entegrasyon:** `make itest` — paketler kuruluyken servisleri başlatır, örnek site oluşturur, `curl https://itest.test` ile doğrular, temizler.
- **Manuel kontrol listesi:** Her prompt sonunda "Senin test adımların" bölümü.
- **CI:** uygulama reposu için GitHub Actions: `xcodegen` + `xcodebuild build test` (imzasız).

## 6. Bilinen riskler ve kararlar

| Risk | Plan |
|---|---|
| `SMAppService.daemon` ücretsiz Personal Team imzasıyla sorunsuz çalışmayabilir | Prompt 05'te doğrulanır; olmazsa geliştirmede yedek yol: tek seferlik yönetici onayıyla (`osascript … with administrator privileges`) kurulan statik LaunchDaemon. Kod iki yolu aynı protokolle soyutlar. |
| pf yönlendirmesi bazı VPN/güvenlik yazılımlarıyla çakışabilir | Doktor kontrol eder ve yeniden uygular. Yedek mod: ön Nginx'i Helper root olarak başlatır, işçileri kullanıcıya düşürür (sadece pf kullanılamazsa; `DECISIONS.md`'ye yazılır). |
| PHP 7.4/8.0 modern OpenSSL ile derlenmez | O dallar için OpenSSL 1.1.1 statik derlenir; güvenlik uyarısı arayüzde gösterilir. |
| Xdebug ve diğer PECL uzantılarının shared yüklenmesi | Prompt 07'de, "statik bağımlılık + dinamik uzantı" yaklaşımı doğrulanır. |
| MinIO dağıtım politikası | Prompt 08'de güncel durum kontrol edilir; gerekirse Go ile kaynaktan derlenir veya alternatif seçilir. |
| Redis lisansı | Ekip içi kullanım için sorun değil; istenirse Valkey alternatifi eklenebilir. |
| Tarayıcıların güvenli DNS (DoH) ayarı gerçek domain ezmesini atlayabilir | Doktor uyarır; rehber gösterilir. |

## 7. Sonraki sürüm fikirleri (v1 dışında)

Sürükle-bırak site ekleme · Node/Vite dev sunucusu için "proxy site" tipi (HMR websockets dahil) · PostgreSQL · canlıdan DB çekme + anonimleştirme (SSH) · HTTP istek denetçisi · SPX profiler entegrasyonu · ekipçe paylaşılan ön ayar paketleri · Valkey.
