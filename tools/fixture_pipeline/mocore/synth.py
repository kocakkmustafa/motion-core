"""Sentetik iskelet üreteci — G1-a sayısal doğruluk kapısının girdisi.

Neden var: gerçek video olmadan ölçüm matematiğini doğrulayabilmek için.
Üreteç, motorun bulması gereken cevabı BİLİR (açıyı biz veriyoruz), motor o
cevabı bulmak zorundadır. Gerçek videonun cevabını kimse bilmez — o yüzden
gerçek video "MediaPipe ne kadar iyi" sorusunu, sentetik iskelet "matematiğimiz
doğru mu" sorusunu yanıtlar. İki ayrı soru, iki ayrı kapı (G1-a / G1-b).

Koordinat sistemi (MediaPipe world landmarks konvansiyonu):
    +x = kişinin SOLU -> sağı yönünde (medial-lateral)
    +y = AŞAĞI (dikey)
    +z = kişinin ÖNÜ (ön-arka)
    orijin = kalça orta noktası, birim = metre

Sagittal düzlem hareketleri y-z düzleminde döner:
    dir(θ) = (0, cos θ, sin θ)   θ=0 aşağı · θ=90 öne yatay · θ=180 yukarı
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field, replace

import numpy as np

from . import geometry as geo
from . import landmarks as lm


@dataclass(frozen=True)
class BodyProportions:
    """Antropometrik segment uzunlukları (metre). Varsayılan ~1.75 m yetişkin."""

    torso: float = 0.50
    shoulder_width: float = 0.40
    hip_width: float = 0.30
    upper_arm: float = 0.30
    forearm: float = 0.26
    thigh: float = 0.44
    shank: float = 0.42
    foot: float = 0.22
    head: float = 0.24

    def scaled(self, k: float) -> "BodyProportions":
        """Tüm iskeleti orantılı büyüt/küçült (boy farkı simülasyonu)."""
        return BodyProportions(
            **{f.name: getattr(self, f.name) * k for f in self.__dataclass_fields__.values()}
        )


@dataclass(frozen=True)
class Pose:
    """Bir duruşun eklem açıları (derece). Hepsi sagittal düzlemde.

    shoulder_flex : 0 = kol yanda aşağı, 180 = tam baş üstü
    elbow_flex    : 0 = kol tamamen düz
    hip_flex      : 0 = uyluk dikey aşağı (ayakta), artarsa öne kalkar
    knee_flex     : 0 = bacak düz
    trunk_lean    : 0 = gövde dik, artarsa öne eğilir
    heel_lift     : 0 = topuk yerde, artarsa topuk kalkar (metre)

    Not: tibia eğimi ayrı parametre DEĞİLDİR — kinematik zincirde
    (hip_flex - knee_flex) ilişkisinden türer. Ayrı bir `ankle_dorsi` alanı
    tutmak, "ayarladım ama hiçbir şey değişmedi" tuzağı üretirdi.
    """

    shoulder_flex: float = 0.0
    elbow_flex: float = 0.0
    hip_flex: float = 0.0
    knee_flex: float = 0.0
    trunk_lean: float = 0.0
    lateral_bend: float = 0.0
    #: Topuğun yerden kalkma miktarı (metre). Squat/ankle testlerinde
    #: geçersizleştirme sinyali; modellenmezse `heel_rise` metriği hiçbir zaman
    #: sınanmaz ve kapıda "ölü" görünür.
    heel_lift: float = 0.0


def _dir_sagittal(deg: float) -> np.ndarray:
    """Sagittal düzlemde yön birim vektörü (bkz. modül başlığı)."""
    r = math.radians(deg)
    return np.array([0.0, math.cos(r), math.sin(r)])


def build_frame(
    pose: Pose,
    *,
    body: BodyProportions | None = None,
    t_ms: float = 0.0,
    confidence: float = 1.0,
) -> geo.Frame:
    """Verilen açılardan tam 33-landmark iskelet üret.

    Üretilen iskelette `angle_3pt(HIP, SHOULDER, ELBOW)` tam olarak
    `pose.shoulder_flex` değerini verir — kapı testinin dayanağı budur.
    """
    b = body or BodyProportions()
    xyz = np.zeros((33, 3), dtype=float)

    def put(name: str, v: np.ndarray) -> None:
        xyz[lm.idx(name)] = v

    # --- pelvis (orijin) ---
    pelvis = np.zeros(3)
    put("LEFT_HIP", pelvis + np.array([-b.hip_width / 2, 0.0, 0.0]))
    put("RIGHT_HIP", pelvis + np.array([+b.hip_width / 2, 0.0, 0.0]))

    # --- gövde: dikeyden trunk_lean kadar öne eğik ---
    # 180 - lean: 180 tam yukarı, azaldıkça öne yatar.
    trunk_dir = _dir_sagittal(180.0 - pose.trunk_lean)
    lateral = np.array([math.sin(math.radians(pose.lateral_bend)), 0.0, 0.0])
    trunk_vec = trunk_dir * math.cos(math.radians(pose.lateral_bend)) + lateral
    shoulder_mid = pelvis + b.torso * trunk_vec
    put("LEFT_SHOULDER", shoulder_mid + np.array([-b.shoulder_width / 2, 0.0, 0.0]))
    put("RIGHT_SHOULDER", shoulder_mid + np.array([+b.shoulder_width / 2, 0.0, 0.0]))

    # --- baş ---
    head_center = shoulder_mid + b.head * trunk_vec
    put("NOSE", head_center + np.array([0.0, 0.0, 0.06]))
    for name in ("LEFT_EYE", "LEFT_EYE_INNER", "LEFT_EYE_OUTER"):
        put(name, head_center + np.array([-0.03, -0.02, 0.05]))
    for name in ("RIGHT_EYE", "RIGHT_EYE_INNER", "RIGHT_EYE_OUTER"):
        put(name, head_center + np.array([+0.03, -0.02, 0.05]))
    put("LEFT_EAR", head_center + np.array([-0.07, 0.0, 0.0]))
    put("RIGHT_EAR", head_center + np.array([+0.07, 0.0, 0.0]))
    put("MOUTH_LEFT", head_center + np.array([-0.02, 0.04, 0.05]))
    put("MOUTH_RIGHT", head_center + np.array([+0.02, 0.04, 0.05]))

    # --- kollar ---
    # Omuz fleksiyonu, GÖVDE hattına göre tanımlıdır: kol yanda dururken
    # (flex=0) omuz->dirsek yönü, omuz->kalça yönüyle aynıdır. Böylece gövde
    # eğilse bile ölçülen açı = verilen açı olur.
    trunk_down = -trunk_vec  # omuzdan kalçaya bakan yön
    arm_dir = _rotate_sagittal_from(trunk_down, pose.shoulder_flex)
    for side in ("LEFT", "RIGHT"):
        sh = xyz[lm.idx(f"{side}_SHOULDER")]
        el = sh + b.upper_arm * arm_dir
        put(f"{side}_ELBOW", el)
        fore_dir = _rotate_sagittal_from(arm_dir, -pose.elbow_flex)
        wr = el + b.forearm * fore_dir
        put(f"{side}_WRIST", wr)
        hand = wr + 0.08 * fore_dir
        put(f"{side}_INDEX", hand)
        put(f"{side}_PINKY", hand + np.array([0.0, 0.02, 0.0]))
        put(f"{side}_THUMB", hand + np.array([0.0, -0.02, 0.0]))

    # --- bacaklar ---
    # Kalça fleksiyonu: uyluk dikey aşağıdan öne doğru açılır.
    thigh_dir = _dir_sagittal(0.0 + pose.hip_flex)
    for side in ("LEFT", "RIGHT"):
        hip = xyz[lm.idx(f"{side}_HIP")]
        knee = hip + b.thigh * thigh_dir
        put(f"{side}_KNEE", knee)
        # Diz fleksiyonu uyluk hattına göre GERİYE kırar.
        shank_dir = _rotate_sagittal_from(thigh_dir, -pose.knee_flex)
        ankle = knee + b.shank * shank_dir
        put(f"{side}_ANKLE", ankle)
        heel = ankle + np.array([0.0, 0.04 - pose.heel_lift, -0.05])
        put(f"{side}_HEEL", heel)
        put(f"{side}_FOOT_INDEX", ankle + np.array([0.0, 0.04, b.foot - 0.05]))

    vis = np.full(33, float(confidence))
    pres = np.full(33, float(confidence))
    return geo.Frame(xyz=xyz, visibility=vis, presence=pres, t_ms=t_ms)


def _rotate_sagittal_from(base: np.ndarray, deg: float) -> np.ndarray:
    """`base` yönünü sagittal düzlemde (y-z) `deg` kadar döndür."""
    r = math.radians(deg)
    c, s = math.cos(r), math.sin(r)
    y, z = base[1], base[2]
    return np.array([base[0], y * c - z * s, y * s + z * c])


# --------------------------------------------------------------------------
# Bozucular — gerçek dünyanın kusurlarını taklit eder
# --------------------------------------------------------------------------


def add_noise(frame: geo.Frame, sigma: float, *, seed: int = 0) -> geo.Frame:
    """Landmark koordinatlarına Gauss gürültüsü ekle (metre)."""
    rng = np.random.default_rng(seed)
    return replace(frame, xyz=frame.xyz + rng.normal(0.0, sigma, frame.xyz.shape))


def yaw(frame: geo.Frame, deg: float) -> geo.Frame:
    """İskeleti dikey eksen (y) etrafında döndür — kameraya göre sapma."""
    r = math.radians(deg)
    c, s = math.cos(r), math.sin(r)
    rot = np.array([[c, 0.0, s], [0.0, 1.0, 0.0], [-s, 0.0, c]])
    return replace(frame, xyz=frame.xyz @ rot.T)


def occlude(frame: geo.Frame, names: tuple[str, ...], level: float) -> geo.Frame:
    """Belirtilen landmark'ların güvenini düşür (oklüzyon/kadraj dışı)."""
    vis = frame.visibility.copy()
    pres = frame.presence.copy()
    for n in names:
        vis[lm.idx(n)] = level
        pres[lm.idx(n)] = level
    return replace(frame, visibility=vis, presence=pres)


def sequence(
    poses: list[Pose], *, fps: float = 30.0, body: BodyProportions | None = None
) -> list[geo.Frame]:
    """Poz listesinden zaman damgalı kare dizisi üret."""
    dt = 1000.0 / fps
    return [build_frame(p, body=body, t_ms=i * dt) for i, p in enumerate(poses)]


def ramp(start: Pose, end: Pose, n: int) -> list[Pose]:
    """İki poz arasında doğrusal geçiş — hareket simülasyonu."""
    fields = [f.name for f in Pose.__dataclass_fields__.values()]
    out = []
    for i in range(n):
        k = i / max(1, n - 1)
        out.append(
            Pose(
                **{
                    f: getattr(start, f) + k * (getattr(end, f) - getattr(start, f))
                    for f in fields
                }
            )
        )
    return out
