"""MediaPipe Pose Landmarker landmark isimleri ve indeksleri (33 nokta).

Aile sözleşmesi: landmark indeksleri HİÇBİR yerde çıplak sayı olarak yazılmaz.
Config dosyaları isim kullanır; bu modül isim<->indeks çevirisinin tek kaynağıdır.

Kaynak: https://ai.google.dev/edge/mediapipe/solutions/vision/pose_landmarker
"""

from __future__ import annotations

NAMES: tuple[str, ...] = (
    "NOSE",
    "LEFT_EYE_INNER",
    "LEFT_EYE",
    "LEFT_EYE_OUTER",
    "RIGHT_EYE_INNER",
    "RIGHT_EYE",
    "RIGHT_EYE_OUTER",
    "LEFT_EAR",
    "RIGHT_EAR",
    "MOUTH_LEFT",
    "MOUTH_RIGHT",
    "LEFT_SHOULDER",
    "RIGHT_SHOULDER",
    "LEFT_ELBOW",
    "RIGHT_ELBOW",
    "LEFT_WRIST",
    "RIGHT_WRIST",
    "LEFT_PINKY",
    "RIGHT_PINKY",
    "LEFT_INDEX",
    "RIGHT_INDEX",
    "LEFT_THUMB",
    "RIGHT_THUMB",
    "LEFT_HIP",
    "RIGHT_HIP",
    "LEFT_KNEE",
    "RIGHT_KNEE",
    "LEFT_ANKLE",
    "RIGHT_ANKLE",
    "LEFT_HEEL",
    "RIGHT_HEEL",
    "LEFT_FOOT_INDEX",
    "RIGHT_FOOT_INDEX",
)

INDEX: dict[str, int] = {name: i for i, name in enumerate(NAMES)}

COUNT = len(NAMES)
assert COUNT == 33, f"MediaPipe Pose 33 landmark bekler, {COUNT} tanımlı"


def idx(name: str) -> int:
    """İsimden indeks. Bilinmeyen isimde sessizce 0 dönmez — patlar."""
    try:
        return INDEX[name]
    except KeyError as exc:  # pragma: no cover - config hatası
        raise KeyError(
            f"Bilinmeyen landmark adı: {name!r}. Geçerli adlar: {', '.join(NAMES)}"
        ) from exc


def mirror(name: str) -> str:
    """LEFT_* <-> RIGHT_* çevirisi. Taraf-bağımsız config yazmayı sağlar."""
    if name.startswith("LEFT_"):
        return "RIGHT_" + name[5:]
    if name.startswith("RIGHT_"):
        return "LEFT_" + name[6:]
    return name


#: Gövde merkez hattını tanımlayan noktalar — normalizasyon referansı için.
TORSO_UPPER = ("LEFT_SHOULDER", "RIGHT_SHOULDER")
TORSO_LOWER = ("LEFT_HIP", "RIGHT_HIP")


# --------------------------------------------------------------------------
# Türetilmiş (sanal) landmark'lar
# --------------------------------------------------------------------------
#
# MediaPipe gövde ORTA hattı için nokta vermez; yalnız sağ/sol çiftleri verir.
# Gövde açısını tek taraflı çiftle (ör. LEFT_HIP -> LEFT_SHOULDER) ölçmek
# sistematik hata üretir: omuz genişliği (~0.40 m) ile kalça genişliği (~0.30 m)
# eşit olmadığı için vektöre sahte bir yanal bileşen karışır. Ölçülen etki
# gövde dik dururken küçük, öne eğilince 11°'ye kadar çıkıyor (G1-a, L-010).
#
# Çözüm: orta-hat noktaları türetilmiş landmark olarak tanımlanır. Config
# bunları normal isim gibi kullanır; güvenleri bileşenlerinin EN ZAYIFI olur.
VIRTUAL: dict[str, tuple[str, ...]] = {
    "MID_HIP": TORSO_LOWER,
    "MID_SHOULDER": TORSO_UPPER,
    "MID_KNEE": ("LEFT_KNEE", "RIGHT_KNEE"),
    "MID_ANKLE": ("LEFT_ANKLE", "RIGHT_ANKLE"),
}


def is_virtual(name: str) -> bool:
    return name in VIRTUAL


def resolve(name: str) -> tuple[int, ...]:
    """İsmi, üzerine kurulduğu gerçek landmark indekslerine çevir."""
    if name in VIRTUAL:
        return tuple(idx(n) for n in VIRTUAL[name])
    return (idx(name),)


# --------------------------------------------------------------------------
# Vücut bölgeleri (JabLab D2 hattından aileye taşındı — M-F-03)
# --------------------------------------------------------------------------
#
# Görünürlük ayrıştırması bölge bazında yapılır: "hızlı uzuv" ayrı, gövde/taban
# ayrı ölçülür ki kadraj sorunu blur bulgusuyla karışmasın (JabLab J-007).
REGIONS: dict[str, tuple[str, ...]] = {
    "TRUNK": ("LEFT_SHOULDER", "RIGHT_SHOULDER", "LEFT_HIP", "RIGHT_HIP"),
    "BASE": (
        "LEFT_ANKLE", "RIGHT_ANKLE", "LEFT_HEEL", "RIGHT_HEEL",
        "LEFT_FOOT_INDEX", "RIGHT_FOOT_INDEX",
    ),
    "HEAD": ("NOSE", "LEFT_EAR", "RIGHT_EAR"),
}


def arm_region(side: str) -> tuple[str, ...]:
    """Bir tarafın kol landmark'ları (omuz hariç — omuz TRUNK'a aittir)."""
    side = side.upper()
    if side not in ("LEFT", "RIGHT"):
        raise ValueError(f"side 'left' veya 'right' olmalı: {side!r}")
    return (f"{side}_ELBOW", f"{side}_WRIST", f"{side}_INDEX")
