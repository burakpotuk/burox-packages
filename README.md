# burox-packages

Burox (macOS yerel PHP geliştirme ortamı) için sunucu paketlerini derleyen boru hattı.
PHP, Nginx, Apache, MariaDB, MySQL ve diğer paketler GitHub Actions'ta `darwin-arm64` için derlenir,
smoke testten geçer ve Ed25519 imzalı bir manifestle bu reponun Release'lerinde yayınlanır.

- Plan: [`docs/PLAN.md`](docs/PLAN.md) (özellikle §3.1; asıl kopya uygulama reposunda)
- Kurallar: [`CLAUDE.md`](CLAUDE.md)
- Görevler: [`prompts/`](prompts/) (06 → 07 → 08)

Her paket, upstream lisans dosyalarını arşivin içinde taşır.
