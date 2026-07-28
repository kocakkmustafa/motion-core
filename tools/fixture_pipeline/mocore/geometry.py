"""Ölçüm matematiği: açı, normalizasyon, güven, temporal smoothing.

Bu modül motion-core'un ÖLÇÜM SÖZLEŞMESİNİN referans implementasyonudur.
Üretim motoru native (Kotlin/Swift) yazılacak; ikisi de aynı versiyonlu config'i
yorumlar ve AYNI fixture'da AYNI sayıyı üretmek zorundadır (differential test, G4).

Kararların kaynağı: ventures/lissom/app/docs/research/05-landmark-aci-matematigi.md
- Sagittal açılar world landmarks (metre, kalça-orijinli) üzerinden hesaplanır.
- Güven = kullanılan landmark'ların visibility x presence çarpımlarının MİNİMUMU.
- Mesafe metrikleri gövde uzunluğuna bölünerek boy-bağımsız hale getirilir.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np

# --------------------------------------------------------------------------
# Veri tipleri
# --------------------------------------------------------------------------


@dataclass(frozen=True)
class Frame:
    """Tek karelik iskelet.

    xyz: (33, 3) float array. World uzayında metre, kalça-ortası orijinli.
         Image uzayında normalize (0-1) koordinat.
    visibility / presence: (33,) float array, 0-1.
    t_ms: kare zaman damgası (monotonik artan).
    """

    xyz: np.ndarray
    visibility: np.ndarray
    presence: np.ndarray
    t_ms: float

    def __post_init__(self) -> None:
        if self.xyz.shape != (33, 3):
            raise ValueError(f"xyz (33,3) olmalı, {self.xyz.shape} geldi")
        for field in ("visibility", "presence"):
            arr = getattr(self, field)
            if arr.shape != (33,):
                raise ValueError(f"{field} (33,) olmalı, {arr.shape} geldi")

    def confidence(self, indices: tuple[int, ...]) -> float:
        """Verilen landmark kümesinin ortak güveni: en zayıf halka."""
        return float(min(self.visibility[i] * self.presence[i] for i in indices))


# --------------------------------------------------------------------------
# Açı hesapları
# --------------------------------------------------------------------------


def angle_3pt(a: np.ndarray, b: np.ndarray, c: np.ndarray) -> float:
    """B köşesindeki A-B-C açısı, derece. Kosinüs kuralı (3D vektör).

    Dejenere durum (sıfır uzunluklu segment) NaN döner — çağıran taraf
    bunu 'ölçülemedi' olarak ele almalı, 0 derece diye YORUMLAMAMALI.
    """
    ba = a - b
    bc = c - b
    nba = float(np.linalg.norm(ba))
    nbc = float(np.linalg.norm(bc))
    if nba < 1e-9 or nbc < 1e-9:
        return math.nan
    cos = float(np.dot(ba, bc)) / (nba * nbc)
    # Kayan nokta taşmasına karşı; acos alan aralığı dışına çıkmasın.
    cos = max(-1.0, min(1.0, cos))
    return math.degrees(math.acos(cos))


#: Dünya uzayında "yukarı" yönü. MediaPipe world landmarks'ta +y AŞAĞI bakar,
#: bu yüzden yukarı = -y.
UP = np.array([0.0, -1.0, 0.0])


def angle_to_vertical(
    p_from: np.ndarray, p_to: np.ndarray, plane: str = "none"
) -> float:
    """p_from -> p_to segmentinin DİKEY eksenle açısı, derece (0 = tam dik yukarı).

    Tibia eğimi (ankle dorsiflexion), gövde öne eğimi (hip hinge), yana eğilme
    gibi 'dikeye göre ne kadar' metrikleri bunu kullanır.

    `plane` verilirse segment önce o düzleme izdüşürülür — öne eğilmeyi yana
    eğilmeden ayırmak için gereklidir (sagittal = öne/arkaya, frontal = yana).
    """
    seg = p_to - p_from
    if plane != "none":
        seg = project(seg, plane)
    n = float(np.linalg.norm(seg))
    if n < 1e-9:
        return math.nan
    cos = float(np.dot(seg, UP)) / n
    cos = max(-1.0, min(1.0, cos))
    return math.degrees(math.acos(cos))


def project(v: np.ndarray, plane: str) -> np.ndarray:
    """Vektörü anatomik düzleme izdüşür.

    sagittal : yan düzlem — medial-lateral ekseni (x) sıfırla
    frontal  : ön düzlem  — ön-arka ekseni (z) sıfırla
    transverse: yatay düzlem — dikey ekseni (y) sıfırla
    none     : izdüşüm yok (tam 3D)

    UYARI: transverse düzlem ölçümleri tek kamerayla güvenilir DEĞİLDİR
    (bkz. research/05, PMC10635560). Bu fonksiyon matematiği yapar; hangi
    ölçümün kullanıcıya gösterileceği kararı config/kapı seviyesindedir.
    """
    out = v.astype(float).copy()
    if plane == "sagittal":
        out[..., 0] = 0.0
    elif plane == "frontal":
        out[..., 2] = 0.0
    elif plane == "transverse":
        out[..., 1] = 0.0
    elif plane != "none":
        raise ValueError(f"Bilinmeyen düzlem: {plane!r}")
    return out


def angle_3pt_projected(
    a: np.ndarray, b: np.ndarray, c: np.ndarray, plane: str
) -> float:
    """A-B-C açısını verilen düzleme izdüşürerek hesapla."""
    if plane == "none":
        return angle_3pt(a, b, c)
    origin = np.zeros(3)
    ba = project(a - b, plane)
    bc = project(c - b, plane)
    return angle_3pt(ba, origin, bc)


# --------------------------------------------------------------------------
# Normalizasyon
# --------------------------------------------------------------------------


def torso_length(xyz: np.ndarray) -> float:
    """Gövde uzunluğu: omuz-ORTASI <-> kalça-ORTASI mesafesi.

    Kişiler-arası ve mesafe-bağımsız karşılaştırma referansı; tüm normalize
    mesafe metriklerinin paydası.

    Neden orta-hattan orta-hatta: ilk sürüm, literatürdeki (ICCV 2017 / PCK)
    "omuz-ortası ile her iki kalça arası mesafenin ortalaması" tanımını
    kullanıyordu. Ölçüldü: o tanım gövde YANA eğilince kayıyor — bir kalça
    yaklaşıp diğeri uzaklaşırken iki mesafenin ortalaması küçülüyor (40° yan
    eğimde %1,6). Payda kayınca anatomik olarak SABİT olması gereken metrikler
    de kayıyordu (topuk-parmak mesafesi %1,7 oynadı).

    Orta-hattan orta-hatta ölçüm bu etkiyi tamamen kaldırır ve kanonik Dart
    çekirdeğinin tanımıyla aynıdır (`(shoulderMid - hipMid)`).
    """
    from . import landmarks as lm

    shoulder_mid = xyz[list(lm.resolve("MID_SHOULDER"))].mean(axis=0)
    hip_mid = xyz[list(lm.resolve("MID_HIP"))].mean(axis=0)
    return float(np.linalg.norm(shoulder_mid - hip_mid))


def normalized_distance_pts(xyz: np.ndarray, p: np.ndarray, q: np.ndarray) -> float:
    """İki nokta arası mesafe / gövde uzunluğu (boyutsuz).

    Squat derinliği, öne uzanma mesafesi gibi metrikler bunu kullanır —
    ham metre değeri boy ve kamera mesafesiyle değişir, bu oran değişmez.
    """
    t = torso_length(xyz)
    if t < 1e-9:
        return math.nan
    return float(np.linalg.norm(p - q)) / t


def normalized_distance(xyz: np.ndarray, i: int, j: int) -> float:
    """İndeksli sürüm — `normalized_distance_pts` sarmalayıcısı."""
    return normalized_distance_pts(xyz, xyz[i], xyz[j])


def line_deviation(p: np.ndarray, a: np.ndarray, b: np.ndarray,
                   plane: str = "none") -> float:
    """P noktasının A→B doğrusuna dik uzaklığı (İŞARETLİ değil, mutlak).

    "Hizada mı?" sorusunun ölçüsü: plank'ta kalçanın omuz–ayak bileği hattından
    ne kadar saptığı, handstand'de gövdenin dikey hattan ayrılması, gard
    hattının bozulması. Tek bir açıyla ifade edilemez çünkü sapma iki uçtaki
    segment açılarının BİLEŞİK sonucudur.

    `plane` verilirse hesap o düzleme izdüşürülür (sagittal çökme ile frontal
    kayma birbirine karışmasın).
    """
    if plane != "none":
        p, a, b = project(p, plane), project(a, plane), project(b, plane)
    ab = b - a
    n = float(np.linalg.norm(ab))
    if n < 1e-9:
        return math.nan
    # |AP × AB| / |AB| — üçgen alanının iki katı, taban uzunluğuna bölünmüş.
    return float(np.linalg.norm(np.cross(p - a, ab))) / n


# --------------------------------------------------------------------------
# Temporal smoothing — One Euro Filter
# --------------------------------------------------------------------------


class OneEuroFilter:
    """Casiez et al. One Euro Filter — hız-uyarlamalı alçak geçiren filtre.

    Yavaş hareket: agresif yumuşatma (jitter gider).
    Hızlı hareket: hafif yumuşatma (gecikme girmez).

    Parametreler research/05'e göre BAŞLANGIÇ değerleridir; Lissom'un kendi
    fixture'larıyla ampirik kalibre edilecek (literatür tek sayı vermiyor).
    """

    def __init__(
        self, *, min_cutoff: float = 1.0, beta: float = 0.0, d_cutoff: float = 1.0
    ) -> None:
        if min_cutoff <= 0:
            raise ValueError("min_cutoff > 0 olmalı")
        self.min_cutoff = min_cutoff
        self.beta = beta
        self.d_cutoff = d_cutoff
        self._x_prev: np.ndarray | None = None
        self._dx_prev: np.ndarray | None = None
        self._t_prev: float | None = None

    @staticmethod
    def _alpha(cutoff: float, dt: float) -> float:
        tau = 1.0 / (2.0 * math.pi * cutoff)
        return 1.0 / (1.0 + tau / dt)

    def reset(self) -> None:
        self._x_prev = self._dx_prev = self._t_prev = None

    def __call__(self, x: np.ndarray, t_ms: float) -> np.ndarray:
        x = np.asarray(x, dtype=float)
        if self._t_prev is None:
            self._x_prev = x.copy()
            self._dx_prev = np.zeros_like(x)
            self._t_prev = t_ms
            return x.copy()

        dt = (t_ms - self._t_prev) / 1000.0
        if dt <= 0:
            # Zaman damgası artmadı: MediaPipe VIDEO modu bunu zaten reddeder.
            # Sessizce yutmak yerine görünür hata ver.
            raise ValueError(
                f"Zaman damgası artmadı: {self._t_prev} -> {t_ms}. "
                "Fixture üretiminde timestamp kesinlikle artan olmalı."
            )

        dx = (x - self._x_prev) / dt
        a_d = self._alpha(self.d_cutoff, dt)
        dx_hat = a_d * dx + (1 - a_d) * self._dx_prev

        cutoff = self.min_cutoff + self.beta * np.abs(dx_hat)
        # Her bileşen kendi kesim frekansını alır (vektörel).
        a = np.array([self._alpha(float(c), dt) for c in np.atleast_1d(cutoff).ravel()])
        a = a.reshape(np.atleast_1d(cutoff).shape)
        x_hat = a * x + (1 - a) * self._x_prev

        self._x_prev, self._dx_prev, self._t_prev = x_hat, dx_hat, t_ms
        return x_hat


class PoseSmoother:
    """33 landmark x 3 eksen için One Euro filtre bankası."""

    def __init__(self, *, min_cutoff: float = 1.0, beta: float = 0.0) -> None:
        self._f = OneEuroFilter(min_cutoff=min_cutoff, beta=beta)

    def reset(self) -> None:
        self._f.reset()

    def __call__(self, frame: Frame) -> Frame:
        smoothed = self._f(frame.xyz, frame.t_ms)
        return Frame(
            xyz=smoothed,
            visibility=frame.visibility,
            presence=frame.presence,
            t_ms=frame.t_ms,
        )
