# burox-packages

Burox (macOS yerel PHP geliştirme ortamı) için sunucu paketlerini derleyen boru hattı.
Paketler GitHub Actions'ta `darwin-arm64` (macOS 14+) için derlenir, taşınabilirlik
denetiminden ve smoke testten geçer, bu reponun Release'lerinde yayınlanır ve
Ed25519 imzalı bir manifestle listelenir.

- Plan: [`docs/PLAN.md`](docs/PLAN.md) (özellikle §3.1; asıl kopya uygulama reposunda)
- Kurallar: [`CLAUDE.md`](CLAUDE.md) · Kararlar: [`docs/DECISIONS.md`](docs/DECISIONS.md) · İlerleme: [`docs/PROGRESS.md`](docs/PROGRESS.md)

## Manifest

```
https://github.com/burakpotuk/burox-packages/releases/download/manifest/manifest.json
https://github.com/burakpotuk/burox-packages/releases/download/manifest/manifest.json.sig
```

`manifest.json.sig` = manifest dosyasının **baytları** üzerindeki 64 baytlık Ed25519
imzasının tek satır base64 hali. Uygulama `keys/manifest-public-*.pem` içindeki iki
public anahtardan biriyle doğrular; imzasız/hatalı manifest reddedilir.

## Paketler

| Paket | Kaynak | Arşiv içeriği |
|---|---|---|
| `nginx` | nginx.org (GPG) + OpenSSL 3.5 LTS, PCRE2, zlib statik | `sbin/nginx`, `etc-default/` (mime.types, fastcgi_params…), `share/nginx/html` |
| `apache` | httpd 2.4 (GPG + SHA-256) + APR, APR-util, PCRE2, OpenSSL, expat, zlib statik | `sbin/httpd` (event MPM), `bin/` (ab, htpasswd, rotatelogs…), `lib/httpd/modules/*.so`, `etc-default/` |
| `mailpit` | resmi binary (GitHub asset digest) | `bin/mailpit` |
| `cloudflared` | resmi binary (sürüm notlarındaki SHA-256 + Cloudflare Developer ID imzası) — **macOS 15+** | `bin/cloudflared` |
| `lego` | resmi binary (resmi checksums.txt) | `bin/lego` |
| `php` | php.net (GPG) 7.4 → 8.6, 19 statik bağımlılık (OpenSSL, ICU, libxml2, curl, gd kütüphaneleri, …) | `bin/php`, `sbin/php-fpm`, `bin/phpize`, `bin/php-config`, `lib/php/extensions/*.so` (opcache ≤ 8.4, xdebug, igbinary, apcu, redis, memcached), `include/php`, `etc-default/php.ini-*` |

Her arşiv: `<ad>-<sürüm>-darwin-arm64.tar.xz`; kökte `PACKAGE.json` (sürüm, kaynaklar,
checksum'lar, imza anahtarları, statik bağımlılıklar, modül listesi) ve
`share/licenses/<bileşen>/` altında upstream lisansları bulunur.

Çalıştırma (uygulama her zaman açık yol verir; derlemedeki `/opt/burox/...` öneki kullanılmaz):

```sh
sbin/nginx -p <prefix>/ -c <nginx.conf> -e <error.log>
sbin/httpd -d <paket-kökü> -f <httpd.conf>      # LoadModule lib/httpd/modules/mod_x.so
bin/php -c <php.ini> -d extension_dir=<paket-kökü>/lib/php/extensions
sbin/php-fpm -y <fpm.conf> -c <php.ini>
```

PHP: ≥ 8.5'te OPcache yerleşiktir (`opcache.so` yoktur); `redis.so` ve `memcached.so`
`igbinary.so`'dan **sonra** yüklenmelidir (`PACKAGE.json` → `meta.sharedExtensionRequires`).
EOL dallar (`meta.eol`, `meta.securityNote`) ve ön sürüm uzantılar (`meta.prerelease`) işaretlidir.

## Repo düzeni

```
recipes/<paket>/   sources.json (URL şablonu + sabit SHA-256'lar), versions.json (derlenecek sürümler),
                   build.sh, smoke-test.sh, extras/*.json (ör. PHP'nin PECL uzantıları)
deps/<bağımlılık>/ sources.json, build.sh  (statik kütüphaneler, CI'da önbellekli)
scripts/           build-package.sh (her şeyi yapan giriş noktası), fetch-source.sh, build-deps.sh,
                   verify-relocatable.sh, verify-plugin-symbols.sh, package.sh, publish-release.sh, plan-builds.sh,
                   make-manifest.py, sign-manifest.sh, verify-manifest.sh,
                   generate-signing-keys.sh, add-version.sh, check-recipes.sh, selftest.sh
keys/              manifest-public-*.pem (yalnızca public), upstream/*.asc (upstream GPG anahtarları)
.github/workflows/ build-package.yml (ortak), build-<paket>.yml, publish-manifest.yml, lint.yml
```

## Yeni sürüm eklemek

```sh
scripts/add-version.sh nginx 1.30.9 --replace      # indirir, GPG/checksum doğrular, SHA-256'yı sabitler
git commit -am "nginx 1.30.9" && git push           # versions.json değişti -> build-nginx otomatik çalışır
```

`--replace` aynı kanaldaki eski sürümü derleme listesinden çıkarır (yayınlanmış Release'i
silmez). Bağımlılık güncellemek: `scripts/add-version.sh --dep openssl 3.5.10`.
Aynı sürümü yeniden yayınlamak gerekirse `versions.json` içindeki build girdisine
`"revision": 1` ekleyin (yayın adı `1.30.9_1` olur).

## Yerelde derleme

```sh
brew install gnupg openssl@3          # bir kez
scripts/build-package.sh nginx 1.30.8 # -> out/nginx-1.30.8-darwin-arm64.tar.xz (+ .sha256, .package.json)
scripts/selftest.sh                    # imza/tamper/pin/otool öz-testleri
```

## İmza anahtarları (bir kez, kendi Mac'inizde)

1. Terminal'de repo klasöründe: `scripts/generate-signing-keys.sh`
   - Özel anahtarlar `~/burox-manifest-keys/` içine yazılır (repo dışı, yalnızca siz okuyabilirsiniz).
   - Public anahtarlar `keys/manifest-public-primary.pem` ve `keys/manifest-public-backup.pem` olur.
2. Birincil özel anahtarı GitHub'a secret olarak ekleyin. İki yoldan biri:
   - Terminal: `gh secret set MANIFEST_SIGNING_KEY < ~/burox-manifest-keys/manifest-signing-primary.key.pem`
   - Tarayıcı: repo sayfası > **Settings** > soldaki **Secrets and variables** > **Actions** >
     **New repository secret** > Name: `MANIFEST_SIGNING_KEY` > Secret kutusuna
     `manifest-signing-primary.key.pem` dosyasının **tüm** içeriğini (`-----BEGIN PRIVATE KEY-----`
     satırından `-----END PRIVATE KEY-----` satırına kadar) yapıştırın > **Add secret**.
3. İki özel anahtar dosyasının içeriğini parola yöneticinize (ör. 1Password / iCloud Anahtar
   Zinciri "Güvenli Not") ayrı kayıtlar olarak kaydedin, sonra
   `rm -P ~/burox-manifest-keys/*.key.pem` ile diskten silin. Yedek anahtar hiçbir yere yüklenmez;
   birincil anahtar kaybolur/çalınırsa onunla imzalamaya geçilir.
4. `keys/manifest-public-*.pem` dosyalarını commit edin. Betiğin yazdırdığı iki "ham anahtar"
   uygulamaya gömülecek değerlerdir.
