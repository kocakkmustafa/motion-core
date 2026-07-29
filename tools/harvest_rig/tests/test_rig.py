#!/usr/bin/env python
"""Hasat rig'i birim testleri — sentetik videolarla, ağ erişimsiz.

Koşum:
    ../fixture_pipeline/.venv/bin/python tests/test_rig.py
"""
from __future__ import annotations

import os
import sys
import tempfile

import cv2
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from harvest import hamming, perceptual_signature  # noqa: E402
from manifest import HarvestManifest  # noqa: E402
from triage import TriageThresholds, triage  # noqa: E402

FAILURES: list[str] = []


def check(cond: bool, msg: str) -> None:
    print(("  ✅ " if cond else "  ❌ ") + msg)
    if not cond:
        FAILURES.append(msg)


def write_video(path: str, *, seconds: float, size: tuple[int, int],
                fps: float = 24.0, scene_flip_every: float = 0.0,
                textured: bool = True, seed: int = 7) -> None:
    """Sentetik test videosu. scene_flip_every>0 -> sert kesmeli kurgu."""
    rng = np.random.default_rng(seed)
    w, h = size
    vw = cv2.VideoWriter(path, cv2.VideoWriter_fourcc(*"mp4v"), fps, (w, h))
    n = int(seconds * fps)
    scene_a = rng.integers(0, 255, (h, w, 3), dtype=np.uint8)
    scene_b = np.zeros((h, w, 3), dtype=np.uint8)
    scene_b[:, :, 2] = 220  # bambaşka renk dünyası — kesme sinyali
    flat = np.full((h, w, 3), 128, dtype=np.uint8)
    for i in range(n):
        t = i / fps
        if not textured:
            frame = flat.copy()
        elif scene_flip_every > 0 and int(t / scene_flip_every) % 2 == 1:
            frame = scene_b.copy()
        else:
            frame = scene_a.copy()
        # küçük hareket — tamamen statik encode köşe durumlarına düşmesin
        cv2.circle(frame, (int(w / 2 + 20 * np.sin(t)), h // 2), 6,
                   (255, 255, 255), -1)
        if not textured:
            # odak-dışı kaynak simülasyonu: keskin kenar bırakma
            frame = cv2.GaussianBlur(frame, (31, 31), 12)
        vw.write(frame)
    vw.release()


def check_triage_profile() -> None:
    """M-F-27: CLI profil yolu — eşikler gerçekten uygulanıyor mu.

    Lissom katkısında (L-046) eşik eklenmiş ama CLI'ya bağlanmamıştı: özellik
    vardı, erişilemiyordu ve hiçbir test bunu söylemiyordu.
    """
    import json as _json
    import tempfile
    from pathlib import Path
    from harvest import load_triage_profile

    check(load_triage_profile(None).min_full_body_ratio == 0.0,
          "profilsiz çağrı rig varsayılanlarını verir")

    with tempfile.TemporaryDirectory() as d:
        good = Path(d) / "profile.json"
        good.write_text(_json.dumps(
            {"thresholds": {"min_full_body_ratio": 0.6, "min_duration_s": 120.0}}),
            encoding="utf-8")
        th = load_triage_profile(str(good))
        check(th.min_full_body_ratio == 0.6, "profil eşiği okunuyor")
        check(th.min_duration_s == 120.0, "profil birden çok eşiği ezebiliyor")
        check(th.min_sharpness == 40.0, "verilmeyen eşik varsayılanda kalıyor")

        bad = Path(d) / "bad.json"
        bad.write_text(_json.dumps({"thresholds": {"min_ful_body_ratio": 0.6}}),
                       encoding="utf-8")
        try:
            load_triage_profile(str(bad))
            check(False, "yazım hatası olan eşik REDDEDİLMELİ")
        except SystemExit:
            check(True, "bilinmeyen eşik anahtarı sessizce yutulmuyor")


def check_per_movement() -> None:
    """L-080: kadraj şartı harekete göre değişir ve triyaja GERÇEKTEN ulaşır.

    İki ayrı şey doğrulanıyor, çünkü ikisi ayrı ayrı kırıldı:
    profil okunuyor mu (L-062: eşik vardı, CLI'ya bağlı değildi) ve okunan
    değer `_body_presence`'a kadar gidiyor mu (L-050: entegrasyon yolu hiç
    koşulmamıştı). Sonda ayrıca POZİTİF yönden sınanıyor — daima 0.0 dönen
    bozuk bir sonda yalnız red testlerini geçerdi.
    """
    import json as _json
    import os
    import tempfile
    from pathlib import Path

    import triage as triage_mod
    from harvest import load_triage_profile

    prof = {"thresholds": {"min_full_body_ratio": 0.6},
            "perMovement": {"overhead_reach": [23, 24], "deep_squat": [23, 27]}}
    with tempfile.TemporaryDirectory() as d:
        f = Path(d) / "p.json"
        f.write_text(_json.dumps(prof), encoding="utf-8")

        th = load_triage_profile(str(f), "overhead_reach")
        check(th.lower_body_ids == (23, 24),
              "harekete özel landmark kümesi profilden okunuyor")
        check(load_triage_profile(str(f), "deep_squat").lower_body_ids == (23, 27),
              "farklı hareket farklı küme alıyor")

        for movement, why in ((None, "--movement verilmeyince"),
                              ("yoktur", "tanımsız hareket verilince")):
            try:
                load_triage_profile(str(f), movement)
                check(False, f"{why} SESSİZCE geçilmemeli")
            except SystemExit:
                check(True, f"{why} sert hata")

    # Eşik gerçekten sondaya ulaşıyor mu (L-050: isim hatası yüzünden hiç
    # ulaşmıyordu ve kavramsal doğrulama bunu görmemişti).
    seen: dict = {}
    real = triage_mod._body_presence

    def spy(path, duration_s, n_frames, model_path, lower_ids=(23, 24, 27, 28)):
        seen["ids"] = lower_ids
        return 1.0, 1.0

    triage_mod._body_presence = spy
    try:
        with tempfile.TemporaryDirectory() as td:
            vid = os.path.join(td, "clip.mp4")
            write_video(vid, seconds=5.0, size=(640, 360))
            r = triage_mod.triage(
                vid,
                thresholds=triage_mod.TriageThresholds(
                    min_full_body_ratio=0.6, lower_body_ids=(23, 24),
                    min_duration_s=4.0),
                pose_model=Path("dummy.task"),
            )
    finally:
        triage_mod._body_presence = real
    check(seen.get("ids") == (23, 24),
          "profildeki küme _body_presence'a KADAR gidiyor")
    check(r is not None and r.full_body_ratio == 1.0,
          "sonda pozitif yönde de ölçülüyor (daima-0 sonda burada kalır)")


def check_usable_window() -> None:
    """L-085: oran düşse de kesintisiz pencere yeterliyse klip kabul edilir.

    Fixture bir temiz TEKRAR ister, temiz bir VİDEO değil. Ölçüldü: reddedilen
    6 overhead_reach klibinin 6'sında da kullanılabilir pencere vardı; biri
    114 sn kusursuz görünürlük taşırken genel oranı 0,47 olduğu için elenmişti.
    """
    import os
    import tempfile
    from pathlib import Path

    import triage as triage_mod

    real_body, real_win = triage_mod._body_presence, triage_mod._usable_window
    triage_mod._body_presence = lambda p, d, n, m, lower_ids=(): (0.92, 0.30)
    try:
        with tempfile.TemporaryDirectory() as td:
            vid = os.path.join(td, "c.mp4")
            write_video(vid, seconds=5.0, size=(640, 360))
            base = dict(min_full_body_ratio=0.6, min_duration_s=4.0)

            # Pencere kapalıyken (varsayılan) davranış eskisiyle aynı olmalı.
            r = triage_mod.triage(vid, thresholds=triage_mod.TriageThresholds(**base),
                                  pose_model=Path("d.task"))
            check(not r.accepted and r.usable_window_s is None,
                  "pencere kapalıyken eski davranış birebir korunuyor")

            triage_mod._usable_window = lambda *a, **k: 12.0
            r = triage_mod.triage(
                vid, thresholds=triage_mod.TriageThresholds(
                    **base, min_usable_window_s=6.0), pose_model=Path("d.task"))
            check(r.accepted and r.usable_window_s == 12.0,
                  "oran düşük ama pencere yeterli -> KABUL")

            # L-090/L-091: kurtarma ÜST-gövde reddine de uygulanmalı ve sonda
            # iki kümenin BİRLEŞİMİNİ görmeli (kullanılabilir pencere = her
            # gerekli landmark AYNI ANDA görünür).
            triage_mod._body_presence = lambda p, d, n, m, lower_ids=(): (0.50, 0.95)
            seen_ids: dict = {}

            def win_spy(path, dur, model, need, step, cap):
                seen_ids["need"] = need
                return 20.0

            triage_mod._usable_window = win_spy
            r = triage_mod.triage(
                vid, thresholds=triage_mod.TriageThresholds(
                    **base, min_usable_window_s=6.0, lower_body_ids=(23, 24)),
                pose_model=Path("d.task"))
            check(r.accepted, "üst-gövde oranı düşük ama pencere yeterli -> KABUL")
            check(seen_ids.get("need") == (0, 11, 12, 23, 24),
                  "pencere sondası üst+alt kümelerin BİRLEŞİMİNİ alıyor")

            triage_mod._body_presence = lambda p, d, n, m, lower_ids=(): (0.92, 0.30)
            triage_mod._usable_window = lambda *a, **k: 3.0
            r = triage_mod.triage(
                vid, thresholds=triage_mod.TriageThresholds(
                    **base, min_usable_window_s=6.0), pose_model=Path("d.task"))
            check(not r.accepted and any("pencere" in x for x in r.rejects),
                  "pencere de yetersizse red ve gerekçe pencereyi söylüyor")
    finally:
        triage_mod._body_presence, triage_mod._usable_window = real_body, real_win


def check_rom_mode() -> None:
    """M-F-43: kaynak-uygunluk sınıflandırması ve FAIL-CLOSED davranışı."""
    from manifest import HarvestManifest
    from rom_mode import ACTIVE, PASSIVE, UNKNOWN, classify

    check(classify(title="Active Range of Motion: Shoulder").mode == ACTIVE,
          "yalnız aktif işaret -> active")
    check(classify(title="Manual Resistance- Shoulder flexion").mode == PASSIVE,
          "pasif işaret -> passive")
    # Karışık kaynak: hangi tekrarın hangi modda olduğu metinden bilinemez.
    mixed = classify(title="Shoulder ROM: Active, Passive and Resisted")
    check(mixed.mode == PASSIVE and not mixed.reference_eligible,
          "karışık kaynak (aktif VE pasif işaret) -> passive, referansa GİREMEZ")
    # Fail-closed: işaretsiz kaynak sessizce aktif sayılamaz.
    bland = classify(title="Full Shoulder Objective Examination")
    check(bland.mode == UNKNOWN and not bland.reference_eligible,
          "işaretsiz kaynak -> unknown ve referansa GİREMEZ (fail-closed)")
    check("TRANSKRİPT YOK" in bland.reason,
          "transkript kullanılmadıysa kanıtın zayıflığı gerekçede yazıyor")
    # Transkript başlığın göremediğini yakalar.
    spoken = classify(title="Shoulder Assessment",
                      transcript="okay just relax your arm, I'll move it for you")
    check(spoken.mode == PASSIVE,
          "transkript başlıkta görünmeyen pasif ifadeyi yakalıyor")

    # M-F-45: pasif icra imkânsızsa unknown referansa GİREBİLİR.
    squat = classify(title="Deep Squat Assessment",
                     passive_execution_possible=False)
    check(squat.mode == UNKNOWN and squat.reference_eligible,
          "pasif icra imkânsız + unknown -> referansa GİREBİLİR (M-F-45)")
    check(not classify(title="Deep Squat Assessment").reference_eligible,
          "aynı başlık, pasif icra mümkünse -> fail-closed sürer")
    # Pasif işaret, muafiyetten BAĞIMSIZ olarak her zaman dışarıda.
    pas = classify(title="Passive Squat Mobilization",
                   passive_execution_possible=False)
    check(pas.mode == PASSIVE and not pas.reference_eligible,
          "pasif işaret muafiyete rağmen HER ZAMAN dışarıda")
    # Alan sırası tuzağı: konumsal çağrıda `sources` bool slotuna kayıyordu.
    check(isinstance(squat.sources_seen, list)
          and isinstance(squat.passive_execution_possible, bool),
          "RomVerdict alanları doğru slotlarda (konumsal kayma yok)")

    # Sınıflandırma FIXTURE'a akıyor mu — manifestte kalırsa kural uygulanmaz.
    m = HarvestManifest.start(app="lissom", video_id="x", source_url="u")
    m.rom_mode, m.reference_eligible = PASSIVE, False
    blk = m.provenance_block()
    check(blk.get("romMode") == PASSIVE and blk.get("referenceEligible") is False,
          "romMode provenance bloğuna akıyor (fixture onu görebilir)")


def main() -> int:
    fast = TriageThresholds(min_duration_s=4.0)
    with tempfile.TemporaryDirectory() as td:
        long_ok = os.path.join(td, "ok.mp4")
        short = os.path.join(td, "short.mp4")
        vertical = os.path.join(td, "vertical.mp4")
        cutty = os.path.join(td, "cutty.mp4")
        blurry = os.path.join(td, "flat.mp4")

        write_video(long_ok, seconds=6, size=(320, 180))
        write_video(short, seconds=2, size=(320, 180))
        write_video(vertical, seconds=6, size=(180, 320))
        write_video(cutty, seconds=6, size=(320, 180), scene_flip_every=0.5)
        write_video(blurry, seconds=6, size=(320, 180), textured=False)

        print("[1] triyaj filtreleri (M-O-02)")
        check(triage(long_ok, thresholds=fast).accepted,
              "uzun+yatay+net+tek-sahne video KABUL")
        r = triage(short, thresholds=fast)
        check(not r.accepted and any("süre" in x for x in r.rejects),
              "kısa video süreden RET")
        r = triage(short)  # varsayılan eşikler
        check(any("90s" in x for x in r.rejects),
              "varsayılan eşik 90 sn (shorts eleme)")
        r = triage(vertical, thresholds=fast)
        check(any("dikey" in x for x in r.rejects), "dikey format RET")
        r = triage(cutty, thresholds=fast)
        check(any("kesme" in x for x in r.rejects),
              f"hızlı kurgu RET (ölçülen {r.cuts_per_min:.0f}/dk)")
        r = triage(blurry, thresholds=fast)
        check(any("netlik" in x for x in r.rejects), "dokusuz/bulanık kaynak RET")

        print("[1b] tam-gövde eşiği entegrasyonu (L-046; sonda stub'lı)")
        # Poz sondasını stub'la: entegrasyon YOLU gerçek koşulsun (8ef2d09'un
        # iki NameError/AttributeError'ı tam bu yolda saklanıyordu).
        import triage as triage_mod
        real_probe = triage_mod._body_presence
        triage_mod._body_presence = lambda p, d, n, m, lower_ids=(): (0.92, 0.50)
        try:
            full_th = TriageThresholds(min_duration_s=4.0,
                                       min_full_body_ratio=0.6)
            r = triage(long_ok, thresholds=full_th,
                       pose_model=__import__("pathlib").Path("stub.task"))
            check(not r.accepted and any("tam-gövde" in x for x in r.rejects),
                  "üst-gövde 0.92 geçse de tam-gövde 0.50 < 0.6 → RET")
            check(r.upper_body_ratio == 0.92 and r.full_body_ratio == 0.50,
                  "iki oran da rapora yazılıyor (tek sonda geçişi)")
            off_th = TriageThresholds(min_duration_s=4.0)  # varsayılan: kapalı
            r = triage(long_ok, thresholds=off_th,
                       pose_model=__import__("pathlib").Path("stub.task"))
            check(r.accepted and r.full_body_ratio is None,
                  "eşik kapalıyken tam-gövde reddi yok (geriye uyum)")
        finally:
            triage_mod._body_presence = real_probe

        print("[2] algısal imza / dedup")
        sig_a = perceptual_signature(long_ok)
        sig_a2 = perceptual_signature(long_ok)
        sig_b = perceptual_signature(cutty)
        check(hamming(sig_a, sig_a2) == 0, "aynı dosya aynı imza")
        check(hamming(sig_a, sig_b) > 64,
              f"farklı içerik uzak imza (hamming={hamming(sig_a, sig_b)})")

        print("[3] manifest provenance")
        m = HarvestManifest.start(app="jablab", video_id="abc123",
                                  source_url="https://youtu.be/abc123")
        m.absorb_info_json({"channel": "Precision Striking",
                            "uploader": "PS", "upload_date": "20240110"})
        check(m.license == "standard-youtube",
              "lisans alanı boşsa 'standard-youtube' varsayılır (C-017)")
        m.record("triage", "ok", durationS=120)
        p = os.path.join(td, "m.json")
        m.save(p)
        back = HarvestManifest.load(p)
        check(back.channel == "Precision Striking" and
              back.stages[0].stage == "triage",
              "manifest gidiş-dönüşü kayıpsız")
        blk = back.provenance_block()
        check(all(k in blk for k in ("sourceUrl", "license", "retrievedAt",
                                     "toolVersions")),
              "provenance bloku fixture v2 alanlarını taşıyor")

    print("[4] triyaj profili (CLI yolu)")
    check_triage_profile()

    print("[5] harekete özel landmark şartı")
    check_per_movement()

    print("[6] kullanılabilir pencere (L-085)")
    check_usable_window()

    print("[7] kaynak-uygunluk / romMode (M-F-43)")
    check_rom_mode()

    # Hüküm EN SONDA verilir. Önceki sürümde bu blok [4]'ün ÇAĞRISINDAN önce
    # geliyordu: blok [4] kırılsa bile betik "Hepsi geçti" deyip 0 dönüyordu,
    # yani yazılmış ama hükme bağlanmamış bir testti (L-063 sınıfı).
    if FAILURES:
        print(f"\n{len(FAILURES)} HATA")
        for f in FAILURES:
            print(f"  ❌ {f}")
        return 1
    print("\nHepsi geçti.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
