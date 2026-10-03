# CLAUDE.md — Motion Core

Ortak şirket/ürün/servis/durum bağlamı için önce [YULAlab ortak girişini](../../../AGENTS.md) oku. Teknik yöntemi model seçer; bu dosya işlem yetkisi üretmez. Yerel ürün ve güvenlik bilgileri aşağıdadır.

Beş uygulamanın (Gravita, Lissom, JabLab, Ostinato, Choreia) ortak altyapısı; ayrı mağaza ürünü değildir.

## Mevcut ürün sözleşmesi

- [Aile mimarisi](docs/00-AILE-MIMARISI.md) mevcut ortak ürün/API sözleşmesi kaynağıdır; tarihsel dört-app satırları güncel beş tüketici yerine geçmez.
- Core enstrüman/beceri-bağımsız altyapı taşır; app'e özgü kural/progresyon/içerik app reposundadır. Ortak hesap, app-specific entitlement ve güvenlik/erişim sınırları korunur.
- Mevcut sürümleme semver + CHANGELOG ve pinli tüketimdir. Breaking değişiklik beş tüketicinin kaynak/pin ve kabul kanıtıyla izlenir; kullanıcı yetkisi dosyadaki geçmişten çıkarılmaz.
- Modüllerin ve beş tüketicinin gerçek kabulü birbirinden ayrılır; teknik doğrulama yöntemi modele aittir.
- Eski ilk-app/kod kilidi tarihsel başlangıç koşuludur; yeni iş güncel kullanıcı kapsamı ve ortak PROJECTS'ten başlar.
