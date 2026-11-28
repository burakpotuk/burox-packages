# Upstream imza anahtarları

`scripts/fetch-source.sh`, kaynak tarball'larının upstream GPG imzalarını yalnızca
bu dosyalardaki anahtarlarla doğrular (`gpgv`, geçici anahtarlık). Her dosya
`gpg --export --export-options export-minimal` ile, aşağıdaki resmi kaynaktan
alınan anahtarlardan üretildi (2026-11-27).

| Dosya | Anahtar (birincil parmak izi) | Sahibi | Resmi kaynak |
|---|---|---|---|
| `nginx.asc` | `D6786CE303D9A9022998DC6CC8464D549AF75C0A` | Sergey Kandaurov | https://nginx.org/en/pgp_keys.html |
| | `43387825DDB1BB97EC36BA5D007C8D7C15D87369` | Roman Arutyunyan | 〃 |
| | `AC50DD4E7CD5D51FD00D1F4C4DB15B66AA75322B` | Sai Krishna Kumar Reddy Yadamakanti | 〃 |
| | `13C82A63B603576156E30A4EA0EA981B66B0D967` | Konstantin Pavlov | 〃 |
| | `7338973069ED3F443F4D37DFA64FD5B17ADB39A8` | Sergey Budnevitch | 〃 |
| `apache.asc` | `65B2D44FE74BD5E3DE3AC3F082781DE46D5954FA` | Eric Covener | https://downloads.apache.org/httpd/KEYS , https://downloads.apache.org/apr/KEYS |
| | `CBA1525BAA7A47BE28FF23DDD3B13FCA2CE60BED` | Graham Leggett | https://downloads.apache.org/apr/KEYS |
| `openssl.asc` | `B146647E45A7B33947AB226B2A2C87D161692D40` | OpenSSL <openssl@openssl.org> (3.x) | `packaging/common/openssl-release-keys.asc` (openssl/packages reposu) ve `doc/fingerprints.txt` |
| | `BA5473A2B0587B07FB27CF2D216094DFD0CB81EF` | OpenSSL (eski anahtar) | 〃 |
| | `EFC0A467D613CB83C7ED6D30D894E2CE8B3D79F5` | OpenSSL OMC / security team (1.1.1w) | `packaging/common/openssl-release-keys.asc` |
| `pcre2.asc` | `A95536204A3BB489715231282A98E77EB6F24CA8` | Nicholas Wilson | `SECURITY.md` (pcre2 reposu) |
| `zlib.asc` | `5ED46A6721D365587791E2AA783FCD8E58BCAFBA` | Mark Adler | https://madler.net/madler/pgp.html |
| `expat.asc` | `3176EF7DB2367F1FCA4F306B1F9B0E909AF37285` | Sebastian Pipping | libexpat sürüm imzaları |
| `php.asc` | 20 anahtar (PHP sürüm yöneticileri) | php.net | https://www.php.net/distributions/php-keyring.gpg (resmi anahtarlık). `39B641343D8C104B2B146DC3F9C39DC0B9698544` (Ben Ramsey, 8.0/8.1) için süresi 2027-01-02'ye uzatılmış öz-imza keys.openpgp.org'dan eklendi; php.net'teki kopya 2025-11-24'te bitmiş görünüyor. |

## Yeni bir imzacı gelirse

Upstream yeni bir sürümü buradaki anahtarlardan biriyle imzalamadıysa
`scripts/add-version.sh` "GPG signature verification FAILED" ile durur. Bu
kasıtlıdır: yeni anahtarı **resmi kaynaktan** alın, parmak izini yukarıdaki
gibi bir resmi listeyle karşılaştırın, ilgili `.asc` dosyasına ekleyin ve bu
tabloyu güncelleyin.
