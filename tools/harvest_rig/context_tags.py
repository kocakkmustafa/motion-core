"""Kaynak bağlam etiketleri — dışlanan aykırının NEDEN'i (M-F-51 eki).

Neden gerekli: "dışlandı" tek başına iki ZIT durumu aynı görünüme sokuyor —
kaynak KÖTÜ (artefakt, yanlış kişi) mü, yoksa kaynak DOĞRU ama BAŞKA BİR ŞEYİ
mi ölçüyor (yoga bağlamında "squat" daha sığ bir çömelme). Birincide kaynağı
atarsın, ikincide test tanımını netleştirir ya da o bağlam için ayrı referans
açarsın. Sebep taşınmazsa bilgi her ölçüm turunda yeniden üretilir.

Sözlük AİLE DÜZEYİNDEDİR ve sabittir: her app kendi kelimesini icat ederse
çapraz-app analiz imkânsızlaşır (M-J-05.1 ile aynı gerekçe). Bilinmeyen etiket
SERT HATA — sessiz yutma yok.
"""

from __future__ import annotations

from dataclasses import dataclass, field

#: M-F-51 eki — aile düzeyi başlangıç sözlüğü. Genişletme M-talebiyle.
VOCAB: dict[str, str] = {
    "different-movement": "Kaynak istenen hareketi hiç göstermiyor (alaka süzgeci).",
    "intent-variant": "Hareket doğru ama başka bir bağlamın normuyla yapılıyor "
                      "(yoga-squat: kaynak kendi bağlamında doğru, bizim tanımımız dar).",
    "tracking-artifact": "İzleme hatası: fiziksel olarak imkânsız değerler.",
    "view-unsuitable": "Bakış açısı ölçüme uygun değil — ÖLÇÜLMÜŞ kısalma kaynaklı.",
    "demo-mode-mismatch": "Gösterim modu uyumsuz (pasif/dirençli icra).",
}

#: Etiketin nereden geldiği. `measurement` ayrı tutulur çünkü ölçümden gelen
#: etiket metinden gelenden farklı güvenilirlikte: biri veriye, diğeri kaynağın
#: kendi anlatısına dayanır. "Landmark'ta görünmeyen metadata'dan gelir;
#: görünen parse edilmez, ölçülür" ayrımının kayıt tarafındaki karşılığı budur.
SOURCES = ("channel", "title", "transcript", "measurement", "manual")


@dataclass
class ContextAnnotation:
    tags: list[str] = field(default_factory=list)
    source: str = "manual"
    note: str = ""

    def __post_init__(self) -> None:
        bad = [t for t in self.tags if t not in VOCAB]
        if bad:
            raise ValueError(
                f"bilinmeyen bağlam etiketi: {bad}. Sözlük AİLE düzeyinde "
                f"sabittir ({', '.join(sorted(VOCAB))}); genişletme M-talebiyle. "
                "Serbest metin, çapraz-app analizi imkânsızlaştırır."
            )
        if self.source not in SOURCES:
            raise ValueError(
                f"bilinmeyen contextSource: {self.source!r} "
                f"(geçerli: {', '.join(SOURCES)})"
            )

    def to_detail(self) -> dict:
        return {
            "contextTags": self.tags,
            "contextSource": self.source,
            "contextNote": self.note,
        }


def from_rom_mode(mode: str, *, source: str = "transcript") -> ContextAnnotation | None:
    """romMode `passive` ise gösterim-modu uyumsuzluğu etiketi üretir.

    `unknown` ETİKETLENMEZ: bilgi yokluğu bir bağlam iddiası değildir ve
    yokluğu etiketlemek, sonraki okuyucuya olmayan bir kanıt sunar.
    """
    if mode != "passive":
        return None
    return ContextAnnotation(["demo-mode-mismatch"], source,
                             "romMode=passive: hareketi başka biri üretiyor")


def from_out_of_range(discarded: int, total: int, *, threshold: float = 0.05
                      ) -> ContextAnnotation | None:
    """Fiziksel-aralık dışı kare oranı yüksekse izleme-artefaktı etiketi.

    Eşik oranı ÖLÇÜLDÜ değil SEÇİLDİ (%5) ve bu bir sınırdır: Lissom'da
    gözlenen atılan-kare oranları %0-18 arasındaydı (Gymnastics BC %18,
    Beam With Jim %10, diğerleri <%1). %5 iki kümeyi ayırıyor ama kalibre
    edilmiş bir eşik DEĞİL — daha çok kaynak biriktikçe gözden geçirilmeli.
    """
    if total <= 0 or discarded / total < threshold:
        return None
    return ContextAnnotation(
        ["tracking-artifact"], "measurement",
        f"karelerin %{100 * discarded / total:.0f}'i fiziksel aralık dışı",
    )
