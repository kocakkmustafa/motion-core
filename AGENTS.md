# YULAlab — yerel Codex girişi

Önce [ortak bağlam girişini](../../../AGENTS.md), ardından [bu reponun tek yerel ürün/güvenlik kaynağını](CLAUDE.md) oku. CLAUDE.md içindeki yerel bilgiler Codex ve Claude için aynıdır; teknik yöntemi model seçer, dosya işlem yetkisi üretmez.

Bu dosya Codex ve diğer kod ajanları içindir. Kısa tutulur; ayrıntı `CLAUDE.md`, `docs/` ve paket README'lerindedir.

## Yığın
- Dart ^3.9 (saf paketler) / ^3.11 (Flutter paketleri), Flutter stable · çok paketli depo `packages/*` · Supabase edge function'ları Deno · durum yönetimi: yok; ChangeNotifier/ValueNotifier
- Saf Dart paketleri (`motion_core`, `motion_content`, `motion_media`): paket klasöründe `dart pub get` · `dart analyze` · `dart test` (`package:test`)
- Flutter paketleri (`motion_camera`, `motion_feedback`, `motion_audio`, `motion_store`, `motion_entitlements`, `motion_account`, `motion_platform_signals`, `motion_telemetry`): paket klasöründe `flutter pub get` · `flutter analyze` · `flutter test` (`flutter_test`)
- Ek CI kapıları (`.github/workflows/ci.yml`): `python3 tools/scan_app_specific_words.py` (paketlerde app-özgü kelime yok) · `deno fmt --check supabase/functions` · `deno check supabase/functions/motion-*/index.ts` · `deno test` (`supabase/functions` testleri)

## Kurallar
- **Minimal diff:** yalnız istenen dosyalara dokun; biçimlendirme/yeniden adlandırma turu yapma.
- Core enstrüman/beceri-bağımsızdır: `packages/*/lib` altına app'e özgü kelime, kural ya da içerik ekleme; Core değişikliği beş tüketiciyi etkiler.
- Yerelleştirme: ARB/`gen-l10n` yok. `motion_account` metinleri Dart içinde `MotionAccountLocalizations.of(context).text(MotionAccountString.<anahtar>)`; yeni anahtara her desteklenen dilin metni birlikte eklenir. UI'sız paketler metni çağırandan alır.
- Testler: paket başına `packages/<paket>/test/*_test.dart`; yeni davranışa test ekle; mevcut testi silme ya da atlatma.
- Sürüm: semver + paket `CHANGELOG.md`; breaking değişiklik beş tüketicinin kaynak/pin kanıtıyla izlenir.
- Bitirmeden: ilgili paketin analiz ve testi temiz olmalı; çıktının son 5 satırını rapora koy.

## Dokunulmaz
- Sır dosyaları (`.env*`, anahtarlar, `~/.secrets`), imzalama yapılandırması, fiyat/abonelik kimlikleri, Supabase göçleri (`supabase/migrations/`) ve edge function dağıtımı — yalnız açık talimatla.
- Tüketici pinleri bu depoda değişmez; Core PR'ı normal merge commit ile girer, squash yasak.
- Core'un kamera bayrağı `motionCameraCoachingAvailable` (`packages/motion_account/lib/src/motion_release_policy.dart`) açılmaz.
- Burun Farkı ve Iron Bank'a dokunulmaz.
