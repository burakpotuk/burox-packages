# Anahtarlar

- `manifest-public-primary.pem`, `manifest-public-backup.pem` — manifest imzasını doğrulayan
  Ed25519 **public** anahtarlar (uygulamaya da gömülür). `scripts/generate-signing-keys.sh`
  üretir. Özel anahtarlar bu repoya **asla** girmez (`.gitignore` yalnızca `keys/*.pem`'e izin verir;
  özel anahtarlar zaten repo dışında üretilir).
- `upstream/` — kaynak tarball'larının GPG imzalarını doğrulamak için upstream anahtarları
  (bkz. `upstream/README.md`).

## Uygulamaya gömülecek ham public anahtarlar (2026-11-27)

CryptoKit: `Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: ...)!)`

| Anahtar | Ham (32 bayt, base64) |
|---|---|
| birincil (`manifest-public-primary.pem`) | `A8Zx9gZUhvwNuDBLREScD41W5r99hTySJ9FpUdX/Hzg=` |
| yedek (`manifest-public-backup.pem`) | `0aIXtib+nZx3VS7teIxk5ZsQCYyo0dq1bxs2FURFFWs=` |
