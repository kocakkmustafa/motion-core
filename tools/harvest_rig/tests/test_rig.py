#!/usr/bin/env python
"""Hasat rig'i birim testleri — sentetik videolarla, ağ erişimsiz.

Koşum:
    ../fixture_pipeline/.venv/bin/python tests/test_rig.py
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import cv2
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import hold_isolator  # noqa: E402
import presence_isolator  # noqa: E402
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



def check_rig_version_gate() -> None:
    """`rig_version()` KOPYA senaryolarını gerçekten yakalıyor mu?

    Hiç ateşlenmemiş bir kapıya güvenmek bu ailenin defalarca avladığı
    desendir (G-037/G-052) — bu yüzden iki kopya senaryosu KASITLI kurulup
    damganın gürültü yaptığı kanıtlanıyor:
      (a) git deposu DIŞINA kopya,
      (b) BAŞKA bir git deposuna kopyalanıp orada commit — bu senaryo `sha`
          döndürüp `vendored: false` diyebilirdi, yani İNANDIRICI AMA YANLIŞ
          damga (ölçüldü, kimlik kontrolü eklenmeden önce gerçekten oluyordu).
    """
    import shutil
    src = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    def stamp_from(path: str) -> dict:
        code = (
            "import sys, types, json;"
            "sys.modules.setdefault('cv2', types.ModuleType('cv2'));"
            f"sys.path.insert(0, {path!r});"
            "from manifest import rig_version;"
            "print(json.dumps(rig_version()))"
        )
        out = subprocess.run([sys.executable, "-c", code],
                             capture_output=True, text=True, timeout=60)
        return json.loads(out.stdout.strip().splitlines()[-1])

    with tempfile.TemporaryDirectory() as td:
        # (a) git DIŞI kopya
        plain = os.path.join(td, "plain", "harvest_rig")
        shutil.copytree(src, plain, ignore=shutil.ignore_patterns(
            "tests", "__pycache__"))
        v = stamp_from(plain)
        check(v.get("vendored") is True and v.get("sha") is None,
              "git dışı rig kopyası `vendored` olarak damgalanıyor")

        # (b) BAŞKA git deposunda TAKİPLİ kopya
        other = os.path.join(td, "other")
        inner = os.path.join(other, "sub", "harvest_rig")
        shutil.copytree(src, inner, ignore=shutil.ignore_patterns(
            "tests", "__pycache__"))
        for args in (["init", "-q", "."], ["add", "-A"],
                     ["-c", "user.email=t@t", "-c", "user.name=t",
                      "commit", "-q", "-m", "copy"]):
            subprocess.run(["git", "-C", other, *args],
                           capture_output=True, timeout=60)
        v = stamp_from(inner)
        check(v.get("vendored") is True and v.get("sha") is None,
              "BAŞKA depoya kopyalanmış rig, o deponun SHA'sını KENDİ "
              "sürümü gibi damgalamıyor (inandırıcı-ama-yanlış damga kapalı)")



def check_second_person_probe() -> None:
    """İkinci-kişi sondasının SÖZLEŞMESİ (M-F-141 koruma 1(i)).

    mediapipe gerektirmez: burada sınanan şey çıkarım değil, RAPORUN
    matematiği ve dürüstlük sözleşmesi — ham oranın doğru bölünmesi, ikinci
    pozun birinciyle KIYASLANABİLİR olması (kıyas tabanı olmadan "ikinci
    kişi oranı" olduğundan yüksek okunur) ve örneksiz klipte çökmemesi.

    Sonda SALT RAPOR: eşik yok, klip reddetmez. Bu test bunu da sabitler —
    ileride biri sondaya sessizce eşik koyarsa görünür olsun.
    """
    import second_person as sp  # noqa: PLC0415

    r = sp.SecondPersonReport(
        videoId="x", sampledFrames=24, framesWithAnyPose=20,
        framesWithTwoPoses=5,
        secondPoseCoreVisibility=[0.2, 0.25, 0.18, 0.9, 0.3],
        firstPoseCoreVisibility=[0.95] * 20)
    s = r.summary()
    check(abs(s["twoPoseShare"] - 0.25) < 1e-9,
          "ham oran POZLU kare sayısına bölünür (5/20), örneklenen kareye değil")
    check(s["secondPoseCoreVisibility"]["median"]
          < s["firstPoseCoreVisibility"]["median"],
          "ikinci poz birinciyle KIYASLANABİLİR raporlanıyor (kıyas tabanı var)")

    z = sp.SecondPersonReport(videoId="y").summary()
    check(z["twoPoseShare"] == 0.0 and z["secondPoseCoreVisibility"] is None,
          "hiç poz bulunamayan klipte sonda çökmez, sıfır/None döner")

    src = (Path(__file__).resolve().parent.parent / "second_person.py").read_text(
        encoding="utf-8")
    check("num_poses=2" in src,
          "sonda num_poses=2 kullanır (üretim 1 kullanıyor — kör nokta budur)")
    check("SALT RAPOR" in src and "EŞİK YOK" in src.upper(),
          "sonda salt-rapor olduğunu BEYAN eder (eşik icadına karşı nöbetçi)")



def check_mirror_discriminator() -> None:
    """Ayna ayırıcısı GERÇEKTEN ayırt ediyor mu? (M-F-171/2)

    Neden gerekli: koordinatörün "ikinci poz görünürlük paritesinde → gerçek
    kişi" okuması AYNA sınıfında ÇÜRÜDÜ (Gravita G-087) — ayna yansıması
    landmark görünürlüğü bakımından gerçek insandan ayırt edilemez. Ayrım
    başka bir imzada: yansıma AYNALANMIŞ ve EŞZAMANLIdır.

    ⚠️ Bu testin ilk sürümü ÖLÇÜMLE düzeltildi, iki kez:
      1. Benzerlik formülü `max(0, 1-mesafe)` idi; RMS-normalize uzayda
         uyuşmayan şekillerin mesafesi ~1,1 olduğu için HER vakada 0'a
         kırpılıyordu — ölü ölçü. Artık HAM mesafe raporlanıyor.
      2. Sentetik vakam sol/sağı düzgün kaydırıyordu; o şekil hâlâ
         ayna-simetrikti, yani test ölçtüğü şeyi ayırt edemiyordu. Artık
         GERÇEKTEN asimetrik duruş (sol kol yukarı, sağ aşağı) kullanılıyor.
    """
    class _P:
        def __init__(self, x, y):
            self.x, self.y, self.visibility = x, y, 0.95

    import second_person as sp  # noqa: PLC0415

    def body(cx, *, mirrored=False, symmetric=False):
        pts = [_P(cx, 0.0) for _ in range(33)]
        if symmetric:
            conf = {11: (-0.10, 0.20), 12: (0.10, 0.20), 13: (-0.15, 0.38),
                    14: (0.15, 0.38), 15: (-0.18, 0.55), 16: (0.18, 0.55)}
        else:  # sol kol YUKARI, sağ kol AŞAĞI = gerçekten asimetrik
            conf = {11: (-0.10, 0.20), 13: (-0.14, 0.02), 15: (-0.16, -0.16),
                    12: (0.10, 0.20), 14: (0.15, 0.38), 16: (0.18, 0.55)}
        conf.update({23: (-0.07, 0.55), 24: (0.07, 0.55), 25: (-0.08, 0.78),
                     26: (0.08, 0.78), 27: (-0.09, 1.0), 28: (0.09, 1.0)})
        if mirrored:
            conf = {sp.MIRROR_SWAP.get(i, i): (-dx, dy)
                    for i, (dx, dy) in conf.items()}
        for i, (dx, dy) in conf.items():
            pts[i] = _P(cx + dx, dy)
        return pts

    def reading(a, b):
        p2 = sp._normalized_shape(b)
        mir = sp._shape_dist(sp._normalized_shape(a, mirror=True), p2)
        dir_ = sp._shape_dist(sp._normalized_shape(a), p2)
        dm = dir_ - mir
        return "AYNA" if dm > 0.10 else ("KISI" if dm < -0.10 else "AYRIM_YOK")

    check(reading(body(0.3), body(0.7, mirrored=True)) == "AYNA",
          "yansıma AYNA olarak okunuyor (aynalanmış mesafe belirgin küçük)")
    check(reading(body(0.3), body(0.7)) == "KISI",
          "paralel hareket eden ayrı kişi AYNA sanılmıyor")
    check(reading(body(0.3, symmetric=True),
                  body(0.7, symmetric=True)) == "AYRIM_YOK",
          "SİMETRİK duruşta ayrım YAPILMIYOR ve bu SÖYLENİYOR — ayna ile "
          "paralel simetrik gövdede gerçekten ayırt edilemez (kusur değil sınır)")

    src = (Path(__file__).resolve().parent.parent / "second_person.py").read_text(
        encoding="utf-8")
    check("max(0.0, 1.0 - d)" not in src,
          "ölü `1-mesafe` benzerlik formülü geri gelmemiş (ölçümle elendi)")


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

    def spy(path, duration_s, n_frames, model_path, lower_ids=(23, 24, 27, 28),
            trunk_band=None):
        seen["ids"] = lower_ids
        return 1.0, 1.0, 1.0

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
    triage_mod._body_presence = lambda p, d, n, m, lower_ids=(), trunk_band=None: (0.92, 0.30, 1.0)
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
            triage_mod._body_presence = lambda p, d, n, m, lower_ids=(), trunk_band=None: (0.50, 0.95, 1.0)
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

            triage_mod._body_presence = lambda p, d, n, m, lower_ids=(), trunk_band=None: (0.92, 0.30, 1.0)
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

    # L-122: ZAYIF işaret tek başına pasif SAYILMAZ. Bu ayrım olmadan
    # deep_squat'ın 4 kaynağından 2'si yanlışlıkla elenmişti.
    for txt, why in (
        ("level one is the deep squat with an assist using something",
         "kendi tutunuyor"),
        ("with more resistance or with more body weight", "yük"),
        ("mobilization and soft-tissue pliability techniques", "öğretilen konu"),
    ):
        v = classify(title="Squat", transcript=txt,
                     passive_execution_possible=False)
        check(v.mode != PASSIVE and v.reference_eligible,
              f"zayıf işaret tek başına elemez ({why})")
    # Güçlü işaret aynen eler — ayrım hiçbir doğru tespiti kaybetmemeli.
    for txt in ("okay just relax your arm, let me move it",
                "this is passive range of motion",
                "the therapist applies over pressure"):
        v = classify(title="Squat", transcript=txt,
                     passive_execution_possible=False)
        check(v.mode == PASSIVE and not v.reference_eligible,
              f"güçlü işaret aynen eliyor ({txt[:28]}...)")

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

    # M-F-104 (J-058, JabLab): birinci-şahıs GÖSTERİM dili — eğitmen kendi
    # hareketini birinci şahısla anlatır. Frolov'un jab transkripti bu sınıf
    # eklenene dek `unknown`da kalıyordu; sınıf ekli hâliyle isimli test.
    frolov = classify(
        title="Boxing: quick 1-2-3 with a lead hand",
        transcript=(
            "Look, my stance is not too narrow. If it's too narrow, I won't "
            "be able to swing my body. When in this body swing, here is the "
            "first punch. I'm not going forward yet. I punch while I'm "
            "still in the air. I throw the fist away from me."
        ),
    )
    check(frolov.mode == ACTIVE and frolov.reference_eligible,
          "birinci-şahıs gösterim dili (frolov, J-058) -> active")

    # ---- HAREKET-YÖNERGESİ sınıfı (J-065/M-F-137) ----------------------
    # M-O-54, şartlı-kalıp ailesini ikinci-şahısa sıkarken bedelini isimle
    # kaydetti: "keep your hands up, chin down" (umI6jNMVG-s) gibi GERÇEK
    # yönergeler elendi. Aşağıdaki iki vaka o fedanın geri-kazanımıdır ve
    # HARD BLOCK yediği için jab referansının yeniden kurulmasını
    # imkânsızlaştırmışlardı (J-064).
    precision = classify(
        title="How To Get A POWERFUL Jab In Boxing",
        transcript=(
            "A good powerful jab can do so much for you if you know how to "
            "throw it. In the meantime, keep your hands up, chin down, eyes "
            "on the prize."
        ),
    )
    check(precision.mode == ACTIVE and precision.reference_eligible,
          "ikinci-şahıs emir kipi (precision_striking, J-064) -> active")

    weldon = classify(
        title="Teaching the boxing stance",
        transcript=(
            "Mike, now tuck your chin, let your arms hang down. You can drop "
            "your hands. Put your hands down, there you go. Then throw your "
            "punches and stay relaxed."
        ),
    )
    check(weldon.mode == ACTIVE and weldon.reference_eligible,
          "ikinci-şahıs emir kipi (kennyweldon, J-064) -> active")

    # NEGATİF KORPUS — üçü de M-O-54 süpürmesinin ADIYLA kaydettiği tuzaklar.
    third = classify(transcript=(
        "He walks in with his chin down and he keeps his hands up the whole "
        "time. She drops her hands when she gets tired."))
    check(third.mode == UNKNOWN and not third.reference_eligible,
          "ÜÇÜNCÜ-ŞAHIS anlatım (his/her) yönerge SAYILMAZ -> unknown")

    first_person_posture = classify(transcript=(
        "I've got nice control with my feet flat on the floor."))
    check(first_person_posture.mode == UNKNOWN,
          "birinci-şahıs duruşu hareket-yönergesi kalıplarına UYMAZ")

    the_form = classify(transcript=(
        "Bend the knees and turn the other way, then step the next step."))
    check(the_form.mode == UNKNOWN,
          "'the' kalıbı (üçüncü-şahısta da geçer) bilinçli olarak DIŞARIDA")

    metaphor = classify(transcript="Keep your hands on the wheel at all times.")
    check(metaphor.mode == UNKNOWN,
          "mecaz ('... on the wheel') hareket yönergesi SAYILMAZ")

    # Pasif ÖNCELİĞİ hareket-yönergesi sınıfıyla da bozulmuyor: fiil listesi
    # `move|lift` içeriyor ama `classify` pasifi ÖNCE kontrol ediyor.
    passive_wins = classify(transcript=(
        "Let me move your arm for you. I'll lift your leg."))
    check(passive_wins.mode == PASSIVE and not passive_wins.reference_eligible,
          "pasif önceliği korunuyor (let me move your / I'll lift your)")

    # Sınıflandırma FIXTURE'a akıyor mu — manifestte kalırsa kural uygulanmaz.
    m = HarvestManifest.start(app="lissom", video_id="x", source_url="u")
    m.rom_mode, m.reference_eligible = PASSIVE, False
    blk = m.provenance_block()
    check(blk.get("romMode") == PASSIVE and blk.get("referenceEligible") is False,
          "romMode provenance bloğuna akıyor (fixture onu görebilir)")


def check_dedup_self() -> None:
    """L-106: video kendisiyle kopya sayılmamalı; başkasıyla sayılmalı."""
    import json as _json
    import tempfile
    from pathlib import Path

    from harvest import check_duplicate

    sig_a = "aa" * 64
    with tempfile.TemporaryDirectory() as d:
        idx = Path(d) / "index.json"
        idx.write_text(_json.dumps({"vid_a": sig_a}), encoding="utf-8")
        check(check_duplicate(sig_a, idx, self_id="vid_a") is None,
              "kendi kaydı kopya SAYILMAZ (yeniden hasat mümkün)")
        check(check_duplicate(sig_a, idx, self_id="vid_b") == "vid_a",
              "başka videonun aynı imzası kopya SAYILIR")
        check(check_duplicate(sig_a, idx) == "vid_a",
              "self_id verilmezse eski davranış korunur")


def check_context_tags() -> None:
    """M-F-51 eki: dışlamanın NEDENİ taşınıyor ve sözlük kapalı."""
    from context_tags import (VOCAB, ContextAnnotation, from_out_of_range,
                              from_rom_mode)
    from manifest import HarvestManifest

    check(from_rom_mode("passive").tags == ["demo-mode-mismatch"],
          "passive -> demo-mode-mismatch")
    # Bilgi YOKLUĞU bir bağlam iddiası değildir; etiketlemek olmayan kanıt sunar.
    check(from_rom_mode("unknown") is None and from_rom_mode("active") is None,
          "unknown/active ETİKETLENMEZ")
    check(from_out_of_range(1488, 8078).tags == ["tracking-artifact"],
          "yüksek aralık-dışı oranı -> tracking-artifact")
    check(from_out_of_range(15, 7500) is None,
          "düşük aralık-dışı oranı etiket üretmez")
    for bad in ({"tags": ["yoga"]}, {"tags": [], "source": "guess"}):
        try:
            ContextAnnotation(**bad)
            check(False, f"geçersiz {bad} REDDEDİLMELİ")
        except ValueError:
            check(True, f"sözlük dışı değer sert hata ({list(bad)[0]})")
    check(len(VOCAB) == 5, "aile sözlüğü 5 değerle başlıyor")

    # Etiket PROVENANCE'a akmalı - manifestte kalırsa ReferenceBuilder göremez.
    m = HarvestManifest.start(app="lissom", video_id="x", source_url="u")
    m.context_tags, m.context_source = ["intent-variant"], "manual"
    blk = m.provenance_block()
    check(blk.get("contextTags") == ["intent-variant"]
          and blk.get("contextSource") == "manual",
          "contextTags provenance bloğuna akıyor")


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
        triage_mod._body_presence = (
            lambda p, d, n, m, lower_ids=(), trunk_band=None: (0.92, 0.50, 1.0))
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

        print("[1c] DURUŞ kapısı (G-043; sonda stub'lı)")
        # Görünürlük kusursuz ama kişi ARANAN HAREKETİ yapmıyor: ayakta
        # konuşan eğitmen. Gravita'da ölçüldü — kimlik kapısı olmadan çıkarılan
        # 85 push-up "tekrarının" 65'i böyle kliplerden geldi.
        real_probe = triage_mod._body_presence
        try:
            stub_path = __import__("pathlib").Path("stub.task")
            triage_mod._body_presence = (
                lambda p, d, n, m, lower_ids=(), trunk_band=None: (0.95, 0.95, 0.05))
            posture_th = TriageThresholds(min_duration_s=4.0,
                                          trunk_angle_band_deg=(60.0, 90.0))
            r = triage(long_ok, thresholds=posture_th, pose_model=stub_path)
            check(not r.accepted and any("duruş" in x for x in r.rejects),
                  "görünürlük 0.95 kusursuz ama duruş 0.05 → RET (ayakta konuşma)")

            # Kritik: pencere kurtarması bu reddi GERİ ALMAMALI. Pencere sondası
            # görünürlük ölçer, kimlik ölçmez; ayakta-konuşma videosunda da
            # kusursuz pencere bulunur ve kurtarma tam elemek istediğimiz klibi
            # geri alırdı.
            rescue_th = TriageThresholds(min_duration_s=4.0,
                                         trunk_angle_band_deg=(60.0, 90.0),
                                         min_usable_window_s=1.0)
            r = triage(long_ok, thresholds=rescue_th, pose_model=stub_path)
            check(not r.accepted and any("duruş" in x for x in r.rejects),
                  "pencere kurtarması duruş reddini GERİ ALMIYOR")

            # Kapı körleştirmemeli: gerçekten şınav yapan klip geçmeli.
            triage_mod._body_presence = (
                lambda p, d, n, m, lower_ids=(), trunk_band=None: (0.95, 0.95, 0.60))
            r = triage(long_ok, thresholds=posture_th, pose_model=stub_path)
            check(r.accepted and r.posture_ratio == 0.60,
                  "duruş 0.60 → KABUL, oran rapora yazılıyor")

            # Bant harekete göre değişir (L-080 dersi): aynı klip DİK bantta
            # reddedilmeli — sabit "yatay" varsaymak squat'ı sessizce elerdi.
            upright_th = TriageThresholds(min_duration_s=4.0,
                                          trunk_angle_band_deg=(0.0, 45.0))
            triage_mod._body_presence = (
                lambda p, d, n, m, lower_ids=(), trunk_band=None:
                (0.95, 0.95, 0.60 if trunk_band == (60.0, 90.0) else 0.02))
            r = triage(long_ok, thresholds=upright_th, pose_model=stub_path)
            check(not r.accepted, "bant çağırandan gelir — dik bantta aynı klip RET")

            off_th = TriageThresholds(min_duration_s=4.0)  # varsayılan: kapalı
            r = triage(long_ok, thresholds=off_th, pose_model=stub_path)
            check(r.accepted and r.posture_ratio is None,
                  "bant verilmezse duruş kapısı KAPALI (geriye uyum)")
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
        # M-F-135 bayat-kopya sınıfı: rig'in KENDİ sürümü de damgalanmalı.
        # Gravita'nın squat hasadı, sınıf-düzeyi muafiyeti taşımayan bayat bir
        # rig kopyasıyla koşmuştu; çıktı geçerli görünüyordu çünkü hangi ARAÇ
        # ürettiğini hiçbir alan söylemiyordu.
        rig = blk.get("toolVersions", {}).get("harvestRig")
        check(isinstance(rig, dict) and "vendored" in rig,
              "provenance harvestRig damgası taşıyor (sha/dirty/vendored)")
        check(("sha" in rig) and (rig["vendored"] or rig.get("sha")),
              "damga ya gerçek SHA verir ya vendored der — arada sessiz "
              "üçüncü hâl YOK")
        check_rig_version_gate()
        check_second_person_probe()
        check_mirror_discriminator()

    print("[4] triyaj profili (CLI yolu)")
    check_triage_profile()

    print("[5] harekete özel landmark şartı")
    check_per_movement()

    print("[5b] harekete özel DURUŞ bandı (G-043 + L-080 dersi)")
    import json
    from pathlib import Path
    from harvest import load_triage_profile
    with tempfile.TemporaryDirectory() as td:
        prof = Path(td) / "p.json"
        prof.write_text(json.dumps({
            "thresholds": {"min_duration_s": 4.0},
            "perMovement": {
                "push_up": {"lower_body_ids": [23, 24],
                            "trunk_angle_band_deg": [60, 90]},
                "bodyweight_squat": {"lower_body_ids": [23, 24, 27, 28],
                                     "trunk_angle_band_deg": [0, 45]},
                "dip": [23, 24],
            },
        }), encoding="utf-8")
        th = load_triage_profile(str(prof), "push_up")
        check(th.trunk_angle_band_deg == (60.0, 90.0),
              "yatay hareket bandı profilden okunuyor")
        th = load_triage_profile(str(prof), "bodyweight_squat")
        check(th.trunk_angle_band_deg == (0.0, 45.0),
              "DİK hareket farklı bant alıyor — tek global bant yeterli olmazdı")
        th = load_triage_profile(str(prof), "dip")
        check(th.lower_body_ids == (23, 24) and th.trunk_angle_band_deg is None,
              "çıplak liste biçimi korunuyor (geriye uyum), bant kapalı")

        bad = Path(td) / "bad.json"
        bad.write_text(json.dumps({
            "thresholds": {"min_duration_s": 4.0},
            "perMovement": {"push_up": {"trunk_angle_band_deg": [90, 60]}},
        }), encoding="utf-8")
        try:
            load_triage_profile(str(bad), "push_up")
            check(False, "ters bant (alt>üst) sert hata vermeli")
        except SystemExit:
            check(True, "ters bant (alt>üst) sert hata veriyor")

        typo = Path(td) / "typo.json"
        typo.write_text(json.dumps({
            "thresholds": {"min_duration_s": 4.0},
            "perMovement": {"push_up": {"trunk_band": [60, 90]}},
        }), encoding="utf-8")
        try:
            load_triage_profile(str(typo), "push_up")
            check(False, "perMovement'ta yazım hatası sessizce yutulmamalı")
        except SystemExit:
            check(True, "perMovement'ta bilinmeyen anahtar sessizce yutulmuyor")

    print("[6] kullanılabilir pencere (L-085)")
    check_usable_window()

    print("[7] kaynak-uygunluk / romMode (M-F-43)")
    check_rom_mode()

    print("[8] dedup kendi-eşleşmesi (L-106)")
    check_dedup_self()

    print("[9] bağlam etiketleri (M-F-51 eki)")
    check_context_tags()

    print("[10] statik-tutuş izolatörü (M-F-75)")
    if hold_isolator.self_test() != 0:
        FAILURES.append("hold_isolator self-test")

    print("[11] hazır-bulunma izolatörü (M-F-85)")
    if presence_isolator.self_test() != 0:
        FAILURES.append("presence_isolator self-test")

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
