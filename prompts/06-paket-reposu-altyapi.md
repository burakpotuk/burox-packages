# 06 — Paket reposu: altyapı, imzalı manifest, Nginx, Apache ve hazır binary'ler

**Repo:** `burox-packages` · **Önkoşul:** 00 (bu repo, `CLAUDE.md` ve `docs/PLAN.md` hazır) · **Oku:** PLAN.md §3.1, bu reponun CLAUDE.md'si

## Amaç
Tüm paketlerin derlenip test edilip imzalı manifestle yayınlandığı boru hattını kurmak ve ilk paketleri çıkarmak.

## Yapılacaklar
1. **Repo düzeni:**
   ```
   recipes/<paket>/{sources.json, build.sh, smoke-test.sh, versions.json}
   scripts/{fetch-source.sh, verify-relocatable.sh, package.sh, make-manifest.(py|swift), sign-manifest.sh, verify-manifest.sh}
   .github/workflows/{build-package.yml (reusable), build-<paket>.yml, publish-manifest.yml}
   keys/manifest-public-*.pem   (sadece public anahtarlar)
   docs/{PLAN.md, PROGRESS.md, DECISIONS.md}
   ```
2. **Ortak build iş akışı** (reusable workflow): kaynak indir + SHA-256 doğrula → bağımlılıkları önbellekten al veya derle → derle → `verify-relocatable.sh` → ad-hoc imza → smoke test → `tar.xz` → GitHub Release'e yükle (tag: `<paket>-<sürüm>`).
3. **Manifest:** `publish-manifest.yml` tüm Release varlıklarından `manifest.json` üretir (PLAN.md §3.1 şeması), `MANIFEST_SIGNING_KEY` ile Ed25519 imzalar (`openssl pkeyutl -sign -rawin`), `manifest.json` + `manifest.json.sig` dosyalarını sabit adresli `manifest` Release'ine (veya GitHub Pages'e) koyar. `verify-manifest.sh` public anahtarla doğrular. CI'da doğrulama adımı var.
4. **Anahtar üretimi talimatı:** Kullanıcıya kendi Mac'inde iki Ed25519 anahtar çifti (birincil + yedek) üretmeyi, özel anahtarı GitHub Secret'a eklemeyi, yedeği güvenli bir yere (ör. parola yöneticisi) koymayı adım adım anlat. Public anahtarlar repoya ve uygulamaya gömülecek.
5. **Nginx** (güncel stable): OpenSSL 3, PCRE2, zlib statik; modüller PLAN.md §3.1. Smoke test: geçici prefix ile `nginx -t`, 127.0.0.1'de başlat, `curl` ile 200, durdur.
6. **Apache httpd 2.4** (güncel): APR, APR-util, PCRE2, OpenSSL, expat statik; event MPM; modüller PLAN.md §3.1 ve `.so` olarak. Smoke test: `httpd -t`, başlat, `curl`, `mod_rewrite` ile bir yönlendirme kontrolü.
7. **Hazır binary'ler** (resmi sürüm sayfasından indir, resmi checksum ile doğrula, yeniden paketle): Mailpit, cloudflared, lego. Smoke test: `--version`.
8. `versions.json` her paket için hangi sürümlerin derleneceğini tutar. Bir sürüm eklemek = bu dosyayı değiştirmek.

## Kısıtlar
- Özel anahtar asla repoya, loga veya artifact'e girmez.
- `otool -L` kontrolü kırılırsa yayınlama yok.

## Kabul kriterleri
- [ ] `workflow_dispatch` ile Nginx, Apache, Mailpit, cloudflared, lego paketleri Release'lerde.
- [ ] İmzalı manifest yayında; `verify-manifest.sh` geçiyor; manifest dosyasında 1 bayt değişince doğrulama **başarısız**.
- [ ] Bir Mac'te paketi indirip `tar xf` ile açınca `nginx -V` ve `httpd -V` çalışıyor (Homebrew olmayan bir ortamda bile).

## Senin test adımların
1. GitHub > repo > Settings > Secrets and variables > Actions > `MANIFEST_SIGNING_KEY` ekle (Claude Code anahtarı nasıl üreteceğini anlatacak).
2. Actions sekmesi > "build-nginx" > Run workflow. Bitince Releases'ta dosyayı gör.
3. "publish-manifest" çalıştır, `manifest.json` adresini tarayıcıda aç.
4. Bir arşivi indirip Terminal'de aç ve `./sbin/nginx -V` çalıştır.
