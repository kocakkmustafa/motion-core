"""Ön-eleme filtreleri (M-O-02 gereksinimleri + katalog §6.2).

Ostinato'nun 57-videoluk kamera-açı triyajı ölçtü: shorts/dikey format,
el-yakın-çekim ve baş-kırpık kadrajlar aday havuzunun ~%25'i. Bunları landmark
çıkarımına sokmak hem boşa GPU hem sahte-temiz fixture riski. Bu modül ucuz
sinyallerle klip daha boru hattına girmeden eler:

  1. süre ≥ 90 sn (shorts eleme)
  2. yatay en-boy oranı (dikey format eleme)
  3. kesme yoğunluğu (çok-sahneli kurgu eleme — tek-sahne öğretim videosu istenir)
  4. netlik (Laplacian varyansı — bulanık kaynak referans olamaz)
  5. üst-gövde varlığı (seyrek MediaPipe sondası — baş-kırpık/el-yakın eleme)

Hepsi örneklemeli çalışır: karar dakikalar süren tam-tarama değil, saniyeler
süren sondadır. Eşikler parametriktir; bir app kendi havuzunda farklı eşik
isterse config'ten değiştirir, kod değişmez.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

import cv2
import numpy as np


@dataclass
class TriageThresholds:
    min_duration_s: float = 90.0
    require_landscape: bool = True
    #: dakika başına kesme üst sınırı — öğretim videoları uzun planlıdır;
    #: hızlı kurgulu tanıtım/müzik videosu referans kaynağı değildir.
    max_cuts_per_min: float = 12.0
    #: örneklenmiş karelerin medyan Laplacian varyansı alt sınırı.
    min_sharpness: float = 40.0
    #: üst-gövde (burun+iki omuz) görünür kare oranı alt sınırı.
    min_upper_body_ratio: float = 0.6
    #: TAM gövde (üst-gövde + kalçalar + ayak bilekleri) görünür kare oranı alt
    #: sınırı. Varsayılan 0.0 = KAPALI (geriye uyumlu).
    #:
    #: Neden ayrı bir eşik: üst-gövde sondası "kişi kadrajda mı" sorusunu
    #: yanıtlar, "ölçmek istediğim eklem kadrajda mı" sorusunu yanıtlamaz.
    #: Lissom pilotunda ÖLÇÜLDÜ (L-046): üst-gövde eşiğini geçen kliplerde alt
    #: vücut metriklerinin geçerli-ölçüm oranı %72-77'ye, bazı kliplerde
    #: %2-7'ye düşüyor — squat/ayak bileği/lunge testleri o kliplerden
    #: ölçülemez. Alt-vücut testi olan app'ler (Lissom, Gravita) bunu açar.
    min_full_body_ratio: float = 0.0
    #: "Alt gövde"nin hangi landmark'lar olduğu HAREKETE göre değişir; sabit
    #: bir küme app'e özgü bir varsayımdır ve sessizce yanlış reddeder.
    #: ÖLÇÜLDÜ (L-080): kalça+ayak bileği sabit istenince Lissom'un
    #: `overhead_reach` (bir OMUZ testi) adaylarının 8'de 7'si "alt vücut
    #: kadraj dışı" diye reddedildi — o test ayak bileğine hiç bakmıyor.
    #: Çağıran, ölçeceği metriklerin gerçekten istediği indeksleri verir.
    #: Varsayılan = kalça+ayak bileği (eski davranış birebir korunur).
    lower_body_ids: tuple[int, ...] = (23, 24, 27, 28)
    #: sonda yoğunlukları
    cut_probe_fps: float = 2.0
    pose_probe_frames: int = 12


@dataclass
class TriageReport:
    path: str
    duration_s: float
    width: int
    height: int
    fps: float
    cuts_per_min: float | None = None
    sharpness: float | None = None
    upper_body_ratio: float | None = None
    full_body_ratio: float | None = None
    rejects: list[str] = field(default_factory=list)

    @property
    def accepted(self) -> bool:
        return not self.rejects

    def to_detail(self) -> dict[str, object]:
        return {
            "durationS": round(self.duration_s, 1),
            "resolution": f"{self.width}x{self.height}",
            "cutsPerMin": None if self.cuts_per_min is None else round(self.cuts_per_min, 1),
            "sharpness": None if self.sharpness is None else round(self.sharpness, 1),
            "upperBodyRatio": None if self.upper_body_ratio is None else round(self.upper_body_ratio, 2),
            "fullBodyRatio": None if self.full_body_ratio is None else round(self.full_body_ratio, 2),
            "rejects": self.rejects,
        }


def _sampled_grays(cap: cv2.VideoCapture, times_s: list[float]) -> list[np.ndarray]:
    out: list[np.ndarray] = []
    for t in times_s:
        cap.set(cv2.CAP_PROP_POS_MSEC, t * 1000.0)
        ok, frame = cap.read()
        if not ok:
            continue
        out.append(cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY))
    return out


def _cut_density(cap: cv2.VideoCapture, duration_s: float, probe_fps: float) -> float:
    """Dakika başına sert-kesme tahmini (HSV histogram korelasyon düşüşleri).

    PySceneDetect kuruluysa daha hassas sonuç verir; bu yerleşik tahminci sıfır
    ek bağımlılıkla aynı KARARI (tek-sahne mi kurgu mu) verebilecek kadar iyidir.
    """
    n = max(int(duration_s * probe_fps), 2)
    n = min(n, 240)  # sonda tavanı — karar için yeter
    times = np.linspace(0.5, max(duration_s - 0.5, 1.0), n)
    prev_hist: np.ndarray | None = None
    cuts = 0
    comparisons = 0
    for t in times:
        cap.set(cv2.CAP_PROP_POS_MSEC, float(t) * 1000.0)
        ok, frame = cap.read()
        if not ok:
            continue
        hsv = cv2.cvtColor(cv2.resize(frame, (160, 90)), cv2.COLOR_BGR2HSV)
        hist = cv2.calcHist([hsv], [0, 1], None, [24, 24], [0, 180, 0, 256])
        cv2.normalize(hist, hist)
        if prev_hist is not None:
            comparisons += 1
            corr = cv2.compareHist(prev_hist, hist, cv2.HISTCMP_CORREL)
            if corr < 0.5:
                cuts += 1
        prev_hist = hist
    if comparisons == 0:
        return 0.0
    span_min = (times[-1] - times[0]) / 60.0
    return cuts / span_min if span_min > 0 else 0.0


def _sharpness(grays: list[np.ndarray]) -> float:
    if not grays:
        return 0.0
    return float(np.median([cv2.Laplacian(g, cv2.CV_64F).var() for g in grays]))


def _body_presence(
    path: Path, duration_s: float, n_frames: int, model_path: Path,
    lower_ids: tuple[int, ...] = (23, 24, 27, 28),
) -> tuple[float, float]:
    """Örneklenmiş karelerde (üst-gövde oranı, tam-gövde oranı) — TEK geçişte.

    Üst-gövde = burun + iki omuz ("kişi kadrajda mı").
    Tam-gövde = + kalçalar + ayak bilekleri ("alt vücut da ölçülebilir mi") —
    alt-vücut testi olan app'ler (Lissom L-046, Gravita) için. İki oran aynı
    çıkarım geçişinden türetilir; sonda maliyeti eşik sayısından bağımsızdır.
    """
    import mediapipe as mp  # noqa: PLC0415 - ağır import yalnız gerektiğinde
    from mediapipe.tasks import python as mp_python  # noqa: PLC0415
    from mediapipe.tasks.python import vision  # noqa: PLC0415

    options = vision.PoseLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=str(model_path)),
        running_mode=vision.RunningMode.IMAGE,
        num_poses=1,
        min_pose_detection_confidence=0.3,
    )
    # BlazePose indeksleri: 0=nose · 11/12=omuzlar · 23/24=kalçalar ·
    # 27/28=ayak bilekleri.
    upper_ids = (0, 11, 12)
    cap = cv2.VideoCapture(str(path))
    times = np.linspace(0.5, max(duration_s - 0.5, 1.0), n_frames)
    seen_upper = 0
    seen_full = 0
    total = 0
    with vision.PoseLandmarker.create_from_options(options) as lm:
        for t in times:
            cap.set(cv2.CAP_PROP_POS_MSEC, float(t) * 1000.0)
            ok, frame = cap.read()
            if not ok:
                continue
            total += 1
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            res = lm.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb))
            if not res.pose_landmarks:
                continue
            pts = res.pose_landmarks[0]
            if all(pts[i].visibility >= 0.5 for i in upper_ids):
                seen_upper += 1
                if all(pts[i].visibility >= 0.5 for i in lower_ids):
                    seen_full += 1
    cap.release()
    if total == 0:
        return 0.0, 0.0
    return seen_upper / total, seen_full / total


def triage(
    path: str | Path,
    *,
    thresholds: TriageThresholds | None = None,
    pose_model: Path | None = None,
) -> TriageReport:
    """Videoyu ele; [TriageReport.accepted] karar, `rejects` gerekçe listesi.

    Ucuz kontroller önce koşar ve reddedilen videoda pahalı sondalar (kesme
    yoğunluğu, poz) hiç çalışmaz — 100-videoluk aday listesi dakikada taranır.
    """
    th = thresholds or TriageThresholds()
    p = Path(path)
    cap = cv2.VideoCapture(str(p))
    if not cap.isOpened():
        raise RuntimeError(f"Video açılamadı: {p}")

    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    n_frames = cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    duration_s = n_frames / fps if fps > 0 else 0.0

    report = TriageReport(
        path=str(p), duration_s=duration_s, width=width, height=height, fps=fps
    )

    if duration_s < th.min_duration_s:
        report.rejects.append(
            f"süre {duration_s:.0f}s < {th.min_duration_s:.0f}s (shorts?)"
        )
    if th.require_landscape and height >= width:
        report.rejects.append(f"dikey format {width}x{height}")
    if report.rejects:
        cap.release()
        return report  # ucuz eleme yetti; pahalı sondalara girme

    report.cuts_per_min = _cut_density(cap, duration_s, th.cut_probe_fps)
    if report.cuts_per_min > th.max_cuts_per_min:
        report.rejects.append(
            f"kesme yoğunluğu {report.cuts_per_min:.1f}/dk > {th.max_cuts_per_min}"
        )

    sample_times = list(np.linspace(0.5, max(duration_s - 0.5, 1.0), 8))
    report.sharpness = _sharpness(_sampled_grays(cap, sample_times))
    cap.release()
    if report.sharpness < th.min_sharpness:
        report.rejects.append(
            f"netlik {report.sharpness:.0f} < {th.min_sharpness:.0f} (bulanık kaynak)"
        )
    if report.rejects:
        return report

    if pose_model is not None:
        upper, full = _body_presence(
            p, duration_s, th.pose_probe_frames, pose_model,
            lower_ids=th.lower_body_ids,
        )
        report.upper_body_ratio = upper
        if report.upper_body_ratio < th.min_upper_body_ratio:
            report.rejects.append(
                f"üst-gövde oranı {report.upper_body_ratio:.2f} < "
                f"{th.min_upper_body_ratio} (baş-kırpık/el-yakın kadraj?)"
            )
        if th.min_full_body_ratio > 0.0:
            report.full_body_ratio = full
            if report.full_body_ratio < th.min_full_body_ratio:
                report.rejects.append(
                    f"tam-gövde oranı {report.full_body_ratio:.2f} < "
                    f"{th.min_full_body_ratio} (bu hareketin istediği "
                    f"landmark'lar {th.lower_body_ids} kadraj dışı)"
                )
    return report
