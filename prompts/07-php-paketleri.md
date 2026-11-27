# 07 — PHP paketleri (7.4 → en yeni)

**Repo:** `burox-packages` · **Önkoşul:** 06 · **Oku:** PLAN.md §3.1, §3.6

## Amaç
Her PHP dalı için taşınabilir, çok sayıda uzantı içeren, Xdebug/OPcache gibi uzantıları **shared** yükleyebilen derlemeler. Projenin teknik olarak en zor parçası; acele etme.

## Yapılacaklar
1. **Önce spike (yaklaşım seçimi):** "Statik bağımlılık + dinamik uzantı" yaklaşımını tek bir sürümle (en yeni 8.x) dene:
   - Seçenek A: static-php-cli'nin kütüphane tariflerini bağımlılıklar için kullanıp PHP'yi `--enable-shared`'siz derleyerek shared uzantıları `phpize` ile ayrıca derlemek.
   - Seçenek B: Bağımlılıkları kendi tariflerimizle `deps/` prefix'ine statik derlemek, PHP'yi bunlara karşı `./configure` ile derlemek.
   Ölçüt: (1) `otool -L` temiz, (2) `zend_extension=opcache.so` ve `xdebug.so` yükleniyor, (3) 8.x ve 7.4 için uygulanabilir. Sonucu ADR olarak yaz, kullanıcıya özetle, onay al.
2. **Bağımlılıklar** (statik, önbellekli): OpenSSL 3 (7.4 ve 8.0 için OpenSSL 1.1.1), ICU, libxml2, libxslt, libzip, oniguruma, libsodium, libpng, libjpeg-turbo, libwebp, freetype, curl, sqlite, gmp, libiconv (gerekirse), libedit veya readline, libmemcached, zstd (opsiyonel).
3. **Derlenen uzantılar** (PHP'ye gömülü): bcmath, bz2, calendar, ctype, curl, dom, exif, fileinfo, filter, ftp, gd (freetype/jpeg/png/webp), gettext, gmp, iconv, intl, mbstring, mysqli, mysqlnd, openssl, pcntl, pdo, pdo_mysql, pdo_sqlite, phar, posix, readline, session, simplexml, soap, sockets, sodium, sqlite3, tokenizer, xml, xmlreader, xmlwriter, xsl, zip, zlib.
4. **Shared uzantılar** (`lib/php/extensions/*.so`): opcache, xdebug (dala uygun sürüm: 7.4 → 3.1.x), redis, igbinary, apcu, memcached. Uygulama bunları aç/kapa yapacak.
5. **Çıktılar:** `bin/php`, `sbin/php-fpm`, `bin/phpize`, `bin/php-config`, `lib/php/extensions/`, `etc-default/php.ini-development`, `etc-default/php.ini-production`, `PACKAGE.json` (gömülü ve shared uzantı listeleri dahil; manifest `meta` alanına taşınır).
6. **Matris:** 7.4, 8.0, 8.1, 8.2, 8.3, 8.4, 8.5 ve varsa daha yenisi; her dalın son yaması (`versions.json`). Her dal ayrı job; biri kırılınca diğerleri devam etsin.
7. **Smoke test** (her dal): `php -v`; `php -m` beklenen listeyle karşılaştırma; her shared uzantının `-d zend_extension=/-d extension=` ile yüklenmesi; `php-fpm -t` geçici config ile; FPM'i unix sokette başlatıp `cgi-fcgi` yerine küçük bir PHP FastCGI istemcisi scriptiyle istek atma; `openssl_random_pseudo_bytes`, `intl` (`NumberFormatter` tr_TR), `gd` (PNG üret), `pdo_sqlite` mini testleri; `curl https://example.com` (CA bundle parametresiyle).
8. Eski sürümler (7.4, 8.0) için PACKAGE.json'a `"eol": true` ve `"securityNote"` alanı; uygulama bunu uyarı olarak gösterecek.

## Kısıtlar
- `otool -L` kuralı istisnasız.
- Derleme süresi uzunsa önbelleği akıllıca kullan; bir job 6 saati geçmemeli.

## Kabul kriterleri
- [ ] Spike ADR'si yazıldı ve kullanıcı onayladı.
- [ ] Tüm dallar Release'lerde, manifest güncel ve imzalı.
- [ ] Her dalda smoke test yeşil, Xdebug ve OPcache shared olarak yükleniyor.
- [ ] Temiz bir Mac'te (Homebrew'suz) `php -m` çalışıyor (kullanıcı doğrular).

## Senin test adımların
1. Spike sonucunu oku, Claude Code'un önerdiği yaklaşımı onayla.
2. Actions'tan "build-php" iş akışını tüm matrisle çalıştır (uzun sürebilir).
3. 8.4 ve 7.4 arşivlerini indir, Terminal'de `./bin/php -v` ve `./bin/php -m` çalıştır.
4. `./bin/php -d zend_extension=$(pwd)/lib/php/extensions/xdebug.so -v` → çıktıda "with Xdebug" görmelisin.
