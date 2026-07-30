"""İkinci-kişi SONDASI — `num_poses=2` ile SALT-RAPOR ölçüm (M-F-141 koruma 1(i)).

**Neden var:** `movement-science-advisor` (Gravita G-076) pasif-ROM'dan FARKLI
bir zarar kanalı adlandırdı: **"asistanlı ideal postür gösterimi."** Koç elini
danışanın kalçasına koyup ideal hattı gösterdiğinde, öznenin KENDİ
üretemeyeceği bir hedef postür doğar. Bu klipler "passive" kelimesini
İÇERMEZ, `romMode` metin sınıflandırıcısında `unknown` düşer, ve bir hareket
`passive_execution_possible=False` ilan edildiği anda referansa GİRER.

Metin sınıflandırıcısı bu kanalı göremez; **kare içinde ikinci kişi olup
olmadığı POSE ile ölçülür.** Üretim hattı `num_poses=1` ile koşuyor, yani
ikinci iskeleti hiç görmüyor (aile geneli kör nokta).

**BU MODÜL HÜKÜM VERMEZ — EŞİK YOKTUR, KLİP REDDETMEZ.** M-F-141 hüküm:
(i) enstrümantasyon + mevcut havuzlarda salt-rapor dağılım, (ii) eşik ANCAK
ölçülmüş ayrışmadan ya da uzman triyajından türer. İcat-eşik yasağı.

**Neden yalnız sayı YETMEZ:** `num_poses=2` istemek ikinci bir "poz"
döndürmeyi garanti eder gibi görünür — ama MediaPipe düşük güvenle
ayna/poster/arka-plan lekesini de ikinci kişi sanabilir. O yüzden sonda
ikinci pozun KALİTESİNİ de raporlar (çekirdek landmark'ların ortalama
visibility/presence'ı). Eşik kararı sayının kendisinden değil, bu
dağılımdan verilir; aksi hâlde "ikinci kişi oranı" olduğundan yüksek okunur.
"""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

import cv2
import numpy as np

#: Gövde çekirdeği: burun + omuzlar + kalçalar. İkinci pozun "gerçek insan mı
#: yoksa leke mi" sorusu bu landmark'ların görünürlüğünden okunur.
CORE_IDS = (0, 11, 12, 23, 24)

#: ŞEKİL karşılaştırması için kullanılan iskelet noktaları (gövde+uzuvlar).
SHAPE_IDS = (11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28)

#: BlazePose sol↔sağ landmark takas çiftleri — ayna sınaması için.
MIRROR_SWAP = {
    1: 4, 4: 1, 2: 5, 5: 2, 3: 6, 6: 3, 7: 8, 8: 7, 9: 10, 10: 9,
    11: 12, 12: 11, 13: 14, 14: 13, 15: 16, 16: 15, 17: 18, 18: 17,
    19: 20, 20: 19, 21: 22, 22: 21, 23: 24, 24: 23, 25: 26, 26: 25,
    27: 28, 28: 27, 29: 30, 30: 29, 31: 32, 32: 31,
}


@dataclass
class SecondPersonReport:
    """Bir klip için salt-rapor ikinci-kişi ölçümü."""

    videoId: str
    sampledFrames: int = 0
    framesWithAnyPose: int = 0
    #: ≥2 poz döndürülen kare sayısı (HAM sayı — kalite süzülmemiş).
    framesWithTwoPoses: int = 0
    #: İkinci pozun çekirdek-landmark ortalama visibility'si, kare başına.
    secondPoseCoreVisibility: list[float] = field(default_factory=list)
    #: Birinci pozun aynı ölçüsü — kıyas tabanı (ikincinin ne kadar zayıf
    #: olduğu ancak birincininkiyle karşılaştırılınca anlaşılır).
    firstPoseCoreVisibility: list[float] = field(default_factory=list)

    #: AYNA AYIRICISI (M-F-171/2). Ayna yansıması AYNALANMIŞ ve EŞZAMANLIdır:
    #: ikinci pozun şekli, birinci pozun SOL/SAĞ TAKASLI şekline benzer.
    #: Gerçek ikinci kişi (ör. yan yana aynı egzersizi yapan iki sunucu) ise
    #: takassız haliyle benzer. Bu yüzden İKİ ölçü birlikte raporlanır —
    #: tek sayı ayna ile iki-kişi-paralel'i ayırt EDEMEZ.
    mirroredShapeDist: list[float] = field(default_factory=list)
    directShapeDist: list[float] = field(default_factory=list)
    error: str | None = None

    @property
    def twoPoseShare(self) -> float:
        """HAM oran — kalite süzgeci YOK. Tek başına hüküm taşımaz."""
        return (self.framesWithTwoPoses / self.framesWithAnyPose
                if self.framesWithAnyPose else 0.0)

    def summary(self) -> dict[str, Any]:
        def stats(xs: list[float]) -> dict[str, float] | None:
            if not xs:
                return None
            a = np.asarray(xs, dtype=float)
            return {
                "mean": round(float(a.mean()), 4),
                "median": round(float(np.median(a)), 4),
                "p90": round(float(np.percentile(a, 90)), 4),
                "max": round(float(a.max()), 4),
            }

        mir, dir_ = stats(self.mirroredShapeDist), stats(self.directShapeDist)
        verdict = "ölçülemedi (iki-pozlu kare yok)"
        if mir and dir_:
            # Mesafe: KÜÇÜK olan daha benzer. Aynalanmış mesafe belirgin
            # küçükse ikinci poz yansımadır.
            dm = dir_["median"] - mir["median"]
            if dm > 0.10:
                verdict = ("AYNA-BENZERİ: aynalanmış şekil mesafesi belirgin "
                           "KÜÇÜK → ikinci poz muhtemelen YANSIMA")
            elif dm < -0.10:
                verdict = ("GERÇEK-İKİNCİ-KİŞİ-BENZERİ: takassız mesafe daha "
                           "küçük → paralel hareket eden ayrı kişi")
            else:
                verdict = ("AYRIM YOK: iki mesafe yakın — bu ölçü sınıfı "
                           "belirleyemiyor (simetrik duruşta ayna ile paralel "
                           "GERÇEKTEN ayırt edilemez; göz triyajı gerekir)")
        return {
            **asdict(self),
            "secondPoseCoreVisibility": stats(self.secondPoseCoreVisibility),
            "firstPoseCoreVisibility": stats(self.firstPoseCoreVisibility),
            "mirroredShapeDist": mir,
            "directShapeDist": dir_,
            "mirrorReading": verdict,
            "twoPoseShare": round(self.twoPoseShare, 4),
            "$note": "SALT RAPOR — eşik yok, klip reddedilmedi. `twoPoseShare` "
                     "HAM orandır (kalite süzgeci uygulanmamıştır); ikinci "
                     "pozun gerçek bir kişi mi olduğu `secondPoseCoreVisibility` "
                     "dağılımının `firstPoseCoreVisibility` ile "
                     "karşılaştırılmasından okunur.",
        }


def _normalized_shape(pts, ids=SHAPE_IDS, *, mirror: bool = False):
    """İskeleti konum/ölçekten ARINDIRIP karşılaştırılabilir şekle çevirir.

    İki poz görüntüde farklı yerde ve farklı ölçektedir; ham koordinat
    karşılaştırmak konumu ölçmek olur, şekli değil. Bu yüzden merkez çıkarılır
    ve RMS ölçeğe bölünür. `mirror=True` ise SOL/SAĞ landmark'lar takaslanır VE
    x ekseni ters çevrilir — ayna yansımasının iki bileşeni de budur.
    """
    idx = [MIRROR_SWAP.get(i, i) if mirror else i for i in ids]
    xy = np.array([[pts[i].x, pts[i].y] for i in idx], dtype=float)
    if mirror:
        xy[:, 0] = -xy[:, 0]
    xy -= xy.mean(axis=0)
    scale = float(np.sqrt((xy ** 2).sum(axis=1).mean()))
    return xy / scale if scale > 1e-9 else None


def _shape_dist(a, b) -> float | None:
    """Normalize edilmiş iskeletler arası ortalama nokta MESAFESİ (küçük=benzer).

    ⚠️ İlk sürümde bunu `1 - mesafe` diye bir "benzerlik" olarak yazmıştım ve
    ÖLÇTÜM: RMS-normalize uzayda uyuşmayan şekillerin tipik mesafesi ~1,1
    olduğu için `max(0, 1-d)` HER vakada 0'a kırpılıyordu — yani ölü bir ölçü.
    Uydurulmuş bir 0-1 skalası yerine HAM mesafe raporlanıyor: iki mesafe
    birbiriyle karşılaştırılır, mutlak bir eşiğe ihtiyaç yok.
    """
    if a is None or b is None:
        return None
    return float(np.linalg.norm(a - b, axis=1).mean())


def probe(
    path: Path,
    *,
    model_path: Path,
    duration_s: float,
    n_frames: int = 24,
    min_confidence: float = 0.3,
) -> SecondPersonReport:
    """Klibi örnekleyip `num_poses=2` ile ikinci-kişi dağılımını ölçer.

    `min_confidence` ÜRETİM triyajıyla AYNI (0.3) tutulur: sondanın işi yeni
    bir rejim icat etmek değil, üretimin GÖRMEDİĞİ ikinci pozu aynı
    duyarlılıkta saymaktır.
    """
    import mediapipe as mp  # noqa: PLC0415 - ağır import yalnız gerektiğinde
    from mediapipe.tasks import python as mp_python  # noqa: PLC0415
    from mediapipe.tasks.python import vision  # noqa: PLC0415

    rep = SecondPersonReport(videoId=path.stem)
    options = vision.PoseLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=str(model_path)),
        running_mode=vision.RunningMode.IMAGE,
        num_poses=2,  # ← üretim 1 kullanıyor; sondanın tek farkı bu
        min_pose_detection_confidence=min_confidence,
    )

    def core_vis(pts) -> float:
        vals = [pts[i].visibility for i in CORE_IDS if i < len(pts)]
        return float(np.mean(vals)) if vals else 0.0

    cap = cv2.VideoCapture(str(path))
    try:
        times = np.linspace(0.5, max(duration_s - 0.5, 1.0), n_frames)
        with vision.PoseLandmarker.create_from_options(options) as lm:
            for t in times:
                cap.set(cv2.CAP_PROP_POS_MSEC, float(t) * 1000.0)
                ok, frame = cap.read()
                if not ok:
                    continue
                rep.sampledFrames += 1
                rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                res = lm.detect(
                    mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb))
                poses = res.pose_landmarks or []
                if not poses:
                    continue
                rep.framesWithAnyPose += 1
                rep.firstPoseCoreVisibility.append(core_vis(poses[0]))
                if len(poses) >= 2:
                    rep.framesWithTwoPoses += 1
                    rep.secondPoseCoreVisibility.append(core_vis(poses[1]))
                    # AYNA AYIRICISI: ikinci poz, birinci pozun AYNALANMIŞ
                    # şekline mi yoksa TAKASSIZ şekline mi daha çok benziyor?
                    p2 = _normalized_shape(poses[1])
                    dm = _shape_dist(
                        _normalized_shape(poses[0], mirror=True), p2)
                    dd = _shape_dist(_normalized_shape(poses[0]), p2)
                    if dm is not None and dd is not None:
                        rep.mirroredShapeDist.append(dm)
                        rep.directShapeDist.append(dd)
    except Exception as exc:  # noqa: BLE001 - sonda hattı durdurmaz
        rep.error = f"{type(exc).__name__}: {exc}"
    finally:
        cap.release()
    return rep


def main() -> int:
    """Bir hasat kütüphanesinin `raw/` dizinini tarar, JSON rapor yazar."""
    import argparse

    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--library", required=True,
                    help="hasat kütüphanesi (raw/ + manifests/ içerir)")
    ap.add_argument("--model", required=True, help="pose landmarker .task yolu")
    ap.add_argument("--frames", type=int, default=24)
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    lib = Path(args.library).expanduser()
    raw = lib / "raw"
    if not raw.is_dir():
        print(f"⛔ raw/ yok: {raw}")
        return 1

    # Süreyi manifestten al; yoksa cv2'den oku (manifest tek doğruluk kaynağı
    # değil, ama varsa ona güvenmek yeniden-ölçümden ucuz).
    durations: dict[str, float] = {}
    for mf in (lib / "manifests").glob("*.json"):
        try:
            doc = json.loads(mf.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        for st in doc.get("stages", []):
            d = (st.get("detail") or {}).get("durationS")
            if d:
                durations[str(doc.get("video_id"))] = float(d)

    # M-F-171/3: PAYDA manifestli kliplere sınırlanır. v1 `raw/*.mp4`'ü
    # körlemesine tarıyordu ve MANİFESTSİZ (yetim) dosyaları da sayıyordu —
    # Gravita'da bu, push_up havuzunun ">0,3 aday" listesini YANLIŞ yaptı:
    # iki "aday" aslında yetim SQUAT klibiydi (G-087). Yetimler sessizce
    # ATLANMAZ; kendileri bir bulgudur, ayrıca raporlanır.
    manifested = {str(json.loads(mf.read_text(encoding="utf-8")).get("video_id"))
                  for mf in (lib / "manifests").glob("*.json")}
    all_vids = sorted(p for p in raw.iterdir()
                      if p.suffix.lower() in {".mp4", ".mkv", ".webm", ".mov"})
    vids = [p for p in all_vids if p.stem in manifested]
    orphans = [p.stem for p in all_vids if p.stem not in manifested]
    print(f"{len(all_vids)} ham dosya → {len(vids)} MANİFESTLİ klip taranıyor "
          f"({len(orphans)} yetim AYRI raporlanıyor) · num_poses=2 · "
          f"SALT RAPOR (eşik yok)\n")
    if orphans:
        print(f"  ⚠️ yetim (manifestsiz, PAYDAYA DAHİL DEĞİL): "
              f"{', '.join(orphans)}\n")
    for v in vids:
        dur = durations.get(v.stem)
        if dur is None:
            cap = cv2.VideoCapture(str(v))
            fps = cap.get(cv2.CAP_PROP_FPS) or 25.0
            cnt = cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0
            cap.release()
            dur = (cnt / fps) if fps else 10.0
        r = probe(v, model_path=Path(args.model).expanduser(),
                  duration_s=dur, n_frames=args.frames)
        s = r.summary()
        reports.append(s)
        sv = s["secondPoseCoreVisibility"]
        print(f"  {v.stem[:24]:24} kare={r.sampledFrames:3} "
              f"pozlu={r.framesWithAnyPose:3} ikiPoz={r.framesWithTwoPoses:3} "
              f"ham-oran={r.twoPoseShare:.3f} "
              f"2.poz-vis-medyan={(sv['median'] if sv else float('nan')):.3f}"
              + (f"  ⚠️{r.error}" if r.error else ""))

    shares = [r["twoPoseShare"] for r in reports]
    out = {
        "$probe": "second person in frame (num_poses=2) — REPORT ONLY",
        "$ruling": "M-F-141 koruma 1(i): enstrümantasyon + salt-rapor dağılım. "
                   "EŞİK YOK, klip reddedilmedi. Eşik ancak ölçülmüş "
                   "ayrışmadan ya da uzman triyajından türer.",
        "$whyItMatters": "advisor (G-076): 'asistanlı ideal postür gösterimi' "
                         "pasif-ROM'dan farklı bir zarar kanalıdır ve metin "
                         "sınıflandırıcısı onu göremez; üretim num_poses=1 "
                         "ile koştuğu için ikinci iskelet hiç görülmüyor.",
        "$rawShareCaveat": "twoPoseShare kalite süzülmemiş HAM orandır — "
                           "MediaPipe ayna/poster/lekeyi de ikinci kişi "
                           "sayabilir. Hüküm için ikinci-poz görünürlük "
                           "dağılımı birinciyle karşılaştırılmalı.",
        "clips": len(reports),
        "orphans": orphans,
        "$orphansNote": "MANİFESTSİZ ham dosyalar — paydaya DAHİL DEĞİL ve "
                        "sessizce atlanmadı. v1 bunları sayıyordu ve Gravita'da "
                        "push_up havuzunun aday listesini yanlış yaptı (G-087): "
                        "iki 'aday' aslında yetim squat klibiydi. Yetim dosya "
                        "kendisi bir bulgudur (kesintili hasat turu / "
                        "kütüphane karışması, G-057 sınıfı).",
        "shareDistribution": {
            "mean": round(float(np.mean(shares)), 4) if shares else None,
            "median": round(float(np.median(shares)), 4) if shares else None,
            "zeroClips": sum(1 for s in shares if s == 0.0),
            "max": round(float(np.max(shares)), 4) if shares else None,
        },
        "reports": reports,
    }
    dest = Path(args.out).expanduser() if args.out else lib / "second-person-probe.json"
    dest.write_text(json.dumps(out, ensure_ascii=False, indent=2),
                    encoding="utf-8")
    print(f"\nham-oran dağılımı: {out['shareDistribution']}")
    print(f"yazıldı: {dest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
