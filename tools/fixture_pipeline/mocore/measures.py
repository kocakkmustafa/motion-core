"""Versiyonlu metrik config yorumlayıcısı.

Aile sözleşmesi (10-ARAC-KATALOGU §2): "Kural içerikleri versiyonlu config (JSON) —
native motor yorumlar." Bu modül o config'in REFERANS yorumlayıcısıdır.

Bir metrik ASLA koda gömülmez: hangi landmark'lar, hangi düzlem, hangi güven
eşiği — hepsi config'te durur. Yeni bir test eklemek kod değişimi gerektirmez.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Literal

import numpy as np

from . import geometry as geo
from . import landmarks as lm

SCHEMA_VERSION = 1

#: Güven kapısı varsayılanı. research/05: MediaPipe varsayılanı 0.5, pratik
#: aralık 0.4-0.7. Lissom wellness bağlamında yanlış-pozitif "iyi skor" riskini
#: azaltmak için 0.6 seçildi. Ampirik kalibrasyon G1-b'de.
DEFAULT_MIN_CONFIDENCE = 0.6

MetricKind = Literal[
    "angle3", "angle_vertical", "distance_norm", "height_diff_norm",
    "line_deviation_norm",
]

#: Ölçüm neden üretilemedi — kullanıcıya gösterilecek gerekçenin makine hali.
#: "Ölçemedim" demek, yanlış ölçmekten daima üstündür (00-AILE-MIMARISI §7).
INVALID_OUT_OF_RANGE = "INVALID_OUT_OF_PHYSICAL_RANGE"
INVALID_LOW_CONFIDENCE = "INVALID_LOW_CONFIDENCE"
INVALID_DEGENERATE = "INVALID_DEGENERATE_GEOMETRY"


@dataclass(frozen=True)
class MetricDef:
    """Tek bir ölçülebilir büyüklüğün tanımı."""

    id: str
    kind: MetricKind
    points: tuple[str, ...]
    plane: str = "none"
    min_confidence: float = DEFAULT_MIN_CONFIDENCE
    unit: str = "deg"
    description: str = ""
    #: M-F-34: kusursuz-durum taban değeri. Tolerans TABAN-göreli yorumlanır;
    #: tabanı sıfır sanmak sessiz hata üretir (L-072). None = beyan edilmemiş.
    baseline: float | None = None
    #: D5/v3: metriğin FİZİKSEL olarak mümkün aralığı. İki ayrı işi vardır ve
    #: ikisi de gerekli: (a) config yazım anında saçma eşiği reddeder (206°
    #: diz sınıfı), (b) ÖLÇÜLEN veriyi süzer. İkincisi olmadan izleme
    #: artefaktları referansa sızar — Lissom'da diz fleksiyonu 0-3° ölçüldü
    #: (tam bükülü diz ~30-40°, 0° baldırın uyluğa katlanması demek) ve
    #: trunk_lateral_tilt 180° verdi (L-107). None = beyansız, süzme YOK.
    value_range: tuple[float, float] | None = None

    def __post_init__(self) -> None:
        # L-011: transverse düzlem, dikey ekseni sıfırlar; dikeye göre açı bu
        # düzlemde TANIMSIZDIR ve her zaman tam 90° döner — sabit değer üreten,
        # hiçbir bilgi taşımayan bir "ölü metrik". Sessizce makul görünen bir
        # sayı ürettiği için en tehlikeli hata sınıfı: yükleme anında reddedilir.
        if self.kind == "angle_vertical" and self.plane == "transverse":
            raise ValueError(
                f"{self.id}: angle_vertical + transverse matematiksel olarak "
                "anlamsızdır (her zaman 90°). Transverse düzlemde dönme ölçmek "
                "için foreshortening (distance_norm + plane) kullanın. Bkz. L-011."
            )
        expected = {
            "angle3": 3,
            "angle_vertical": 2,
            "distance_norm": 2,
            "height_diff_norm": 2,
            "line_deviation_norm": 3,   # [ölçülen nokta, doğru başı, doğru sonu]
        }[self.kind]
        if len(self.points) != expected:
            raise ValueError(
                f"{self.id}: {self.kind} {expected} nokta ister, {len(self.points)} verildi"
            )
        for p in self.points:
            lm.resolve(p)  # bilinmeyen isimde patlar (sanal isimler de geçerli)

    @property
    def indices(self) -> tuple[int, ...]:
        """Metriğin dayandığı TÜM gerçek landmark indeksleri (güven kapısı için)."""
        out: list[int] = []
        for p in self.points:
            out.extend(lm.resolve(p))
        return tuple(out)

    def mirrored(self, new_id: str | None = None) -> "MetricDef":
        """Sağ/sol aynası. Tek tanımdan iki taraf üretmeyi sağlar."""
        return MetricDef(
            id=new_id or _mirror_id(self.id),
            kind=self.kind,
            points=tuple(lm.mirror(p) for p in self.points),
            plane=self.plane,
            min_confidence=self.min_confidence,
            unit=self.unit,
            description=self.description,
            baseline=self.baseline,
            value_range=self.value_range,
        )

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "MetricDef":
        kind = d["kind"]
        # L-009: ham 3D açı, omuz/kalça genişlik farkı yüzünden ROM uçlarında
        # ±5.7° sistematik hata veriyor. Düzlem izdüşümü opsiyonel bırakılırsa
        # bu hata er geç geri gelir — config seviyesinde zorunlu tutuluyor.
        if kind in ("angle3", "angle_vertical", "line_deviation_norm") and "plane" not in d:
            raise ValueError(
                f"{d['id']}: açı metriklerinde 'plane' ZORUNLUDUR "
                "(sagittal/frontal/transverse/none). Bilinçli olarak 3D ham açı "
                "isteniyorsa açıkça \"plane\": \"none\" yazın. Gerekçe: L-009."
            )
        return cls(
            id=d["id"],
            kind=kind,
            points=tuple(d["points"]),
            plane=d.get("plane", "none"),
            min_confidence=float(d.get("minConfidence", DEFAULT_MIN_CONFIDENCE)),
            unit=d.get("unit", "deg"),
            description=d.get("description", ""),
            baseline=(float(d["baseline"]) if "baseline" in d else None),
            value_range=(tuple(float(x) for x in d["range"])  # type: ignore[arg-type]
                         if "range" in d else None),
        )


def _mirror_id(mid: str) -> str:
    if mid.endswith("_left"):
        return mid[: -len("_left")] + "_right"
    if mid.endswith("_right"):
        return mid[: -len("_right")] + "_left"
    return mid + "_mirrored"


@dataclass(frozen=True)
class Measurement:
    """Bir karede bir metriğin sonucu."""

    metric_id: str
    value: float
    confidence: float
    valid: bool
    reason: str | None = None
    unit: str = "deg"


def evaluate(metric: MetricDef, frame: geo.Frame) -> Measurement:
    """Bir metriği tek karede hesapla — güven kapısı DAHİL.

    Güven eşiğin altındaysa değer hesaplanır ama `valid=False` döner ve
    çağıran taraf bunu skora KATMAMALIDIR.
    """
    conf = frame.confidence(metric.indices)
    # Sanal noktalar bileşenlerinin ortalamasıdır; gerçek noktalar kendileridir.
    pts = [frame.xyz[list(lm.resolve(p))].mean(axis=0) for p in metric.points]

    if metric.kind == "angle3":
        value = geo.angle_3pt_projected(pts[0], pts[1], pts[2], metric.plane)
    elif metric.kind == "angle_vertical":
        value = geo.angle_to_vertical(pts[0], pts[1], metric.plane)
    elif metric.kind == "height_diff_norm":
        # İki nokta arasındaki DİKEY fark / gövde uzunluğu. İşaretli: pozitif =
        # ilk nokta ikincisinden yukarıda. Lunge'da arka dizin yere yaklaşması,
        # squat'ta kalçanın diz hizasına inmesi gibi "ne kadar alçaldı"
        # sorularının boy-bağımsız cevabı. Yer düzlemi bilinmediği için mutlak
        # yükseklik değil, vücut-içi referansa göre ölçülür.
        t = geo.torso_length(frame.xyz)
        value = (pts[0][1] - pts[1][1]) / t if t > 1e-9 else float("nan")
        # +y aşağı bakar; işareti "yukarısı pozitif" olacak şekilde çevir.
        value = -value
    elif metric.kind == "line_deviation_norm":
        # Nokta–doğru uzaklığı / gövde uzunluğu. Plank'ta kalçanın omuz–ayak
        # bileği hattından sapması gibi "hizada mı?" ölçüleri.
        t = geo.torso_length(frame.xyz)
        d = geo.line_deviation(pts[0], pts[1], pts[2], metric.plane)
        value = d / t if t > 1e-9 else float("nan")
    elif metric.kind == "distance_norm":
        a, b = pts[0], pts[1]
        if metric.plane != "none":
            # Düzleme izdüşürülmüş mesafe = foreshortening ölçümü. Gövde
            # kameraya göre döndükçe omuz hattının frontal izdüşümü kısalır;
            # transverse rotasyonun 2D'de ölçülebilen tek dolaylı işareti budur.
            a, b = geo.project(a, metric.plane), geo.project(b, metric.plane)
        value = geo.normalized_distance_pts(frame.xyz, a, b)
    else:  # pragma: no cover - MetricDef doğrulaması engeller
        raise ValueError(f"Bilinmeyen metrik tipi: {metric.kind}")

    if not np.isfinite(value):
        return Measurement(metric.id, value, conf, False, INVALID_DEGENERATE, metric.unit)
    if conf < metric.min_confidence:
        return Measurement(
            metric.id, value, conf, False, INVALID_LOW_CONFIDENCE, metric.unit
        )
    # Fiziksel olarak imkânsız değer = izleme artefaktı. Güven kapısı bunu
    # YAKALAMIYOR: landmark'lar yüksek görünürlükle ama yanlış yerde
    # kestirilebiliyor ve sonuç anatomik olarak mümkün olmayan bir açı oluyor.
    if metric.value_range is not None:
        lo, hi = metric.value_range
        if not (lo <= value <= hi):
            return Measurement(
                metric.id, value, conf, False, INVALID_OUT_OF_RANGE, metric.unit
            )
    return Measurement(metric.id, value, conf, True, None, metric.unit)


@dataclass(frozen=True)
class MetricSet:
    """Versiyonlu metrik koleksiyonu — bir config dosyasının tamamı."""

    schema_version: int
    set_id: str
    version: str
    metrics: dict[str, MetricDef]

    @classmethod
    def load(cls, path: str | Path) -> "MetricSet":
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        sv = int(data.get("schemaVersion", 0))
        if sv != SCHEMA_VERSION:
            raise ValueError(
                f"{path}: schemaVersion {sv}, bu yorumlayıcı {SCHEMA_VERSION} bekliyor. "
                "Sürüm uyumsuzluğu sessizce yorumlanmaz."
            )
        metrics: dict[str, MetricDef] = {}
        for raw in data["metrics"]:
            m = MetricDef.from_dict(raw)
            metrics[m.id] = m
            if raw.get("mirror"):
                mm = m.mirrored()
                metrics[mm.id] = mm
        return cls(
            schema_version=sv,
            set_id=data["id"],
            version=str(data["version"]),
            metrics=metrics,
        )

    def evaluate_all(self, frame: geo.Frame) -> dict[str, Measurement]:
        return {mid: evaluate(m, frame) for mid, m in self.metrics.items()}
