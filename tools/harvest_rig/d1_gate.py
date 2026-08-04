#!/usr/bin/env python
"""D1 ÖN-KAPISI — yayımlanmış altyazıdan konu triyajı, video İNDİRMEDEN.

Üç-katmanlı huninin ORTA katmanı (M-F-200):

    başlık = ADAY  ·  D1 yayımlı-metin = ÖN-KAPI  ·  ölçüm/göz = HÜKÜM

Maliyet farkı bu aracın tüm varlık sebebi: bir aday için altyazı ~0,4 MB ve
saniyeler, video ~200 MB ve dakikalar. JabLab turunda 16 aday indirilmeden
elendi ve **kuyruğun uppercut adaylarının HEPSİ kaldı** — hepsi BAŞLIKTAN
seçilmişti ve başlığı "uppercut" olan bir videonun içeriği cross anlatabiliyor
(`eBxn21FtqPg`: uppercut 1 anma, cross 5). Başlık bir kapı değildir.

## Bu araç NE SÖYLER, NE SÖYLEMEZ

SÖYLER: kaynağın KONUSU aranan teknik mi (konu saflığı).
SÖYLEMEZ: o anda hareket olup olmadığı. Eğitmen konuşurken çoğu zaman DURUR.
JabLab bunu ölçtü: ±12 sn'lik "konu pencereleri"nin birleşimi videonun %57'sini
kaplıyordu ve FSM olaylarının %50'si içindeydi — **tesadüften ayrılamaz.**

    Kural: D1 penceresi ARAMAYI daraltmak içindir, OLAY SAYMAK için değil.
    Her sayısal iddia göz-doğrulamasına (D3) bağlanır ya da "onaysız" damgalanır.

## Alan sözlüğü DIŞARIDAN gelir

Bu dosya çekirdekte yaşıyor ve çekirdek alan-bağımsızdır: burada `hook`,
`jab`, `uppercut` gibi bir kelime GEÇMEZ. Terimler `--lexicon` ile bir JSON
dosyasından okunur; JabLab boks terimlerini, Ostinato yay/pozisyon terimlerini
kendi deposunda tutar. (`triage.py`nin "eşikler parametriktir" tercihiyle aynı
gerekçe.)

Sözlük şeması:

    {
      "target":   {"hook": ["hook", "hooks", "hooking"]},
      "others":   {"jab": ["jab", "jabs"], "cross": ["cross", "straight"]},
      "variants": {"bag_or_mitt": ["bag", "mitt", "pad", "partner"]}
    }

`variants` M-F-175 varyant taraması: sıfırdan büyük bir sayım OTO-RET DEĞİLDİR,
göz-doğrulaması ZORUNLU kılar (zayıf metin kanıtı → göz zinciri).

## Kapının bilinen SINIRI — koda yazıldı, yoruma bırakılmadı

Oran kapısı **konu saflığını** ölçer, **malzeme miktarını** ÖLÇMEZ. 2 dakikalık
bir video mükemmel saflıkla geçebilir ve yargılanabilir kare sayısı yine de
yetmeyebilir (`FJJy6Zc3XhM`: hook 4, diğer 0, 2,0 dk → kapıdan geçti, sonra
0 tetikleme). Önceki koşumda bu ders METİNDE yazılıydı ama KODDA değildi ve
kapı tek bir "GEÇTİ/KALDI" üretiyordu. Burada iki boyut AYRI raporlanır:

  * `purity`   — oran kapısı. GEÇER/KALIR üretir.
  * `material` — süre + anma yoğunluğu. **Kapı DEĞİL, uyarı.** Eşik altındaki
    kaynak elenmez, `thin` damgalanır: ne kadar yargılanabilir kare çıkacağı
    ancak ekstraksiyondan sonra bilinir ve şimdi elemek TAHMİN olurdu.

Koşum:
    python3 d1_gate.py --lexicon jablab-boxing.json --id=VIDEO_ID [...]
    python3 d1_gate.py --lexicon L.json --id-file adaylar.txt --json rapor.json
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

from manifest import rig_staleness_warning, rig_version  # noqa: E402

#: Oran kapısı: aranan teknik anması, diğerlerinin toplamının bu katı olmalı.
#: 2,0 keyfi değil ölçülmüş: 1,75'te kalan `iInkodqd5pE` elle bakıldığında
#: gerçekten karışık içerikti, 2,0'ı geçenlerin hiçbiri değildi.
DEFAULT_PURITY_RATIO = 2.0

#: Malzeme UYARISI eşiği (kapı DEĞİL) — bu sürenin altındaki kaynak `thin`.
#: 3 dakika, `FJJy6Zc3XhM` vakasından: 2,0 dk saflıkla geçip 0 tetikleme
#: üretti. Tek vaka bir yasa değil, o yüzden eleme değil UYARI.
DEFAULT_THIN_DURATION_S = 180.0


class LexiconError(ValueError):
    """Sözlük dosyası kullanılamaz — sessizce boş sayıma düşmek yerine patlar."""


@dataclass
class Lexicon:
    """Alan terimleri — bu modülün DIŞINDAN gelir (çekirdek alan-bağımsız)."""

    target_name: str
    target_terms: list[str]
    others: dict[str, list[str]] = field(default_factory=dict)
    variants: dict[str, list[str]] = field(default_factory=dict)

    @staticmethod
    def load(path: Path) -> "Lexicon":
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise LexiconError(f"sözlük okunamadı: {path} ({exc})") from exc

        target = raw.get("target")
        if isinstance(target, dict):
            # Üst düzeyde açıklama serbest, ama HEDEF bölümünde değil: oradaki
            # fazladan bir anahtar "iki hedef" sayılır ve aşağıdaki kapı bunu
            # zaten reddeder — sebebi net olsun diye ayrıca elenmiyor.
            target = {k: v for k, v in target.items() if not k.startswith("$")}
        if not isinstance(target, dict) or len(target) != 1:
            raise LexiconError(
                "`target` TEK anahtarlı bir sözlük olmalı — iki hedefi aynı "
                "koşumda aramak, oran kapısını anlamsız kılar (hangi teknik "
                "'diğer' sayılacak?)")
        name, terms = next(iter(target.items()))
        if not terms:
            raise LexiconError(f"`target.{name}` boş — aranacak terim yok")

        def terms_of(section: str) -> dict[str, list[str]]:
            """Terim listelerini doğrular — `list(v)` ile SESSİZCE dönüştürmez.

            Ölçülmüş tuzak (kendi sözlüğümü yazarken): JSON'da açıklama için
            bir `"$comment": "uzun cümle"` anahtarı bırakmak kolay ve
            `list("uzun cümle")` **harflere** bölünür — kelime-sınırlı regex
            tek harflerden kurulur, her kaynak her şeyle eşleşir. Hata
            vermeyen bir dönüşüm burada tam olarak "ölçülen sanılan çöp"
            üretirdi, o yüzden tip zorunlu.
            """
            out: dict[str, list[str]] = {}
            for key, value in (raw.get(section) or {}).items():
                if not isinstance(value, list) or not all(
                        isinstance(t, str) for t in value):
                    raise LexiconError(
                        f"`{section}.{key}` bir DİZE LİSTESİ olmalı — bulunan: "
                        f"{type(value).__name__}. (Açıklama yazacaksan üst "
                        f"düzey `$comment` alanını kullan; buradaki bir metin "
                        f"harflere bölünür ve sayım anlamsızlaşır.)")
                out[key] = list(value)
            return out

        lex = Lexicon(
            target_name=name,
            target_terms=list(terms),
            others=terms_of("others"),
            variants=terms_of("variants"),
        )
        # Hedef terimi "diğer"lerin içinde de geçiyorsa oran kapısı kendi
        # kendini yer: aynı anma hem pay hem payda olur.
        overlap = {t.lower() for t in lex.target_terms} & {
            t.lower() for terms in lex.others.values() for t in terms}
        if overlap:
            raise LexiconError(
                f"hedef terim(ler)i `others` içinde de var: {sorted(overlap)} — "
                "aynı anma hem pay hem payda olur, kapı anlamını yitirir")
        return lex


@dataclass
class Verdict:
    video_id: str
    ok: bool
    reason: str
    duration_s: float | None = None
    target_hits: int = 0
    other_hits: dict[str, int] = field(default_factory=dict)
    variant_hits: dict[str, int] = field(default_factory=dict)
    purity_ratio: float | None = None
    material: str = "unknown"
    needs_eye_check: bool = False


def _normalize_argv(argv: list[str]) -> list[str]:
    """`--id -abc123` → `--id=-abc123`.

    YouTube kimlikleri base64url alfabesinden gelir ve **`-` ile başlayabilir**;
    argparse böyle bir değeri bir sonraki BAYRAK sanar ve "expected one
    argument" der. Lissom L-191'de bu ölçüldü: aracı kütüphanenin bir
    alt-kümesinde hiç çalışmıyordu, ama toplu koşum glob'la yapıldığı için
    çıktı sorunsuz görünüyordu — sessiz-kırılma sınıfı. Kullanıcıdan `=`
    yazmasını beklemek yerine burada normalize ediliyor.
    """
    out: list[str] = []
    i = 0
    while i < len(argv):
        tok = argv[i]
        if tok in ("--id", "--id-file") and i + 1 < len(argv):
            out.append(f"{tok}={argv[i + 1]}")
            i += 2
            continue
        out.append(tok)
        i += 1
    return out


def count_mentions(text: str, terms: list[str]) -> int:
    """Kelime-sınırlı, büyük/küçük harf duyarsız anma sayımı.

    Alt-dize DEĞİL: `re.escape` + `\\b`. "jab" araması "jabbing"i yakalamalı mı
    kararı SÖZLÜĞÜN işi (oraya "jabbing" yazılır), aracın değil — burada gizli
    bir kök-bulma yapmak, sözlüğü yazan kişinin göremediği eşleşmeler üretirdi.
    """
    if not terms:
        return 0
    pattern = r"\b(?:" + "|".join(re.escape(t) for t in terms) + r")\b"
    return len(re.findall(pattern, text, flags=re.IGNORECASE))


def fetch_subtitle(video_id: str, *, workdir: Path,
                   timeout_s: int = 90) -> tuple[str | None, float | None]:
    """Otomatik altyazıyı çeker → (düz metin, kapsanan süre) ya da (None, None).

    `None` metin = **altyazı YOK**, "uygun değil" DEĞİL. İkisini karıştırmak
    `2I4HLsi0RuU`ı elenmiş sayardı; oysa o kaynak yalnız BU ARAÇLA triyaj
    edilemiyor, göz-doğrulaması hâlâ mümkün.
    """
    if shutil.which("yt-dlp") is None:
        raise RuntimeError("yt-dlp bulunamadı — D1 kapısı ağ aracına bağlı")

    out_tmpl = str(workdir / "%(id)s.%(ext)s")
    cmd = [
        "yt-dlp", "--skip-download",
        "--write-auto-subs", "--sub-langs", "en.*", "--sub-format", "json3",
        "-o", out_tmpl,
        # `--` sonrası: `-` ile başlayan kimlik yt-dlp tarafından da bayrak
        # sanılmasın (argparse'la aynı tuzağın ikinci kopyası).
        "--", f"https://www.youtube.com/watch?v={video_id}",
    ]
    try:
        subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_s)
    except (OSError, subprocess.TimeoutExpired):
        return None, None

    files = sorted(workdir.glob(f"{video_id}*.json3"))
    if not files:
        return None, None

    try:
        doc = json.loads(files[0].read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None, None

    words: list[str] = []
    last_ms = 0
    for ev in doc.get("events") or []:
        start = ev.get("tStartMs")
        dur = ev.get("dDurationMs") or 0
        if isinstance(start, int):
            last_ms = max(last_ms, start + (dur if isinstance(dur, int) else 0))
        for seg in ev.get("segs") or []:
            frag = seg.get("utf8")
            if frag:
                words.append(frag)
    text = "".join(words)
    return (text, last_ms / 1000.0) if text.strip() else (None, None)


def judge(video_id: str, text: str | None, duration_s: float | None,
          lex: Lexicon, *, purity_ratio: float = DEFAULT_PURITY_RATIO,
          thin_below_s: float = DEFAULT_THIN_DURATION_S) -> Verdict:
    """Sayımdan hükme — AĞ YOK, saf fonksiyon (bu yüzden testlenebilir)."""
    if text is None:
        return Verdict(video_id=video_id, ok=False, reason="nosub",
                       duration_s=duration_s)

    target = count_mentions(text, lex.target_terms)
    others = {name: count_mentions(text, terms)
              for name, terms in lex.others.items()}
    variants = {name: count_mentions(text, terms)
                for name, terms in lex.variants.items()}
    other_total = sum(others.values())

    # Hiç teknik anması yok: müziksiz/konuşmasız ya da alakasız kaynak.
    # "0 >= 2*0" aritmetik olarak DOĞRU ve bu vakayı sessizce GEÇİRİRDİ —
    # `PxVQ7HKKchQ` tam buydu (4,7 dk, hiçbir teknik anması yok).
    if target == 0:
        return Verdict(video_id=video_id, ok=False, reason="no-target-mention",
                       duration_s=duration_s, target_hits=0, other_hits=others,
                       variant_hits=variants)

    ratio = float("inf") if other_total == 0 else target / other_total
    passed = target >= purity_ratio * other_total

    material = "unknown"
    if duration_s is not None:
        material = "thin" if duration_s < thin_below_s else "ok"

    return Verdict(
        video_id=video_id,
        ok=passed,
        reason="pass" if passed else "mixed-content",
        duration_s=duration_s,
        target_hits=target,
        other_hits=others,
        variant_hits=variants,
        purity_ratio=None if ratio == float("inf") else round(ratio, 2),
        material=material,
        # Varyant anması OTO-RET DEĞİL (M-F-175): zayıf metin kanıtı göz
        # zincirini tetikler, kaynağı elemez.
        needs_eye_check=any(v > 0 for v in variants.values()),
    )


def _render(verdicts: list[Verdict], lex: Lexicon) -> str:
    rows = [f"D1 kapısı — hedef: {lex.target_name}", ""]
    head = f"{'video':<14}{'süre':>7}{'hedef':>7}{'diğer':>7}{'oran':>7}  sonuç"
    rows += [head, "-" * len(head)]
    for v in verdicts:
        dur = f"{v.duration_s / 60:.1f}dk" if v.duration_s else "—"
        ratio = "∞" if v.purity_ratio is None and v.ok else (
            f"{v.purity_ratio:.2f}" if v.purity_ratio is not None else "—")
        mark = {"pass": "✅ GEÇTİ", "mixed-content": "❌ karışık",
                "no-target-mention": "❌ anma yok",
                "nosub": "⬜ altyazı YOK (elenmiş DEĞİL)"}[v.reason]
        extra = []
        if v.material == "thin":
            extra.append("⚠️MALZEME İNCE")
        if v.needs_eye_check:
            hits = ", ".join(f"{k}={n}" for k, n in v.variant_hits.items() if n)
            extra.append(f"⚠️varyant({hits})→göz")
        rows.append(f"{v.video_id:<14}{dur:>7}{v.target_hits:>7}"
                    f"{sum(v.other_hits.values()):>7}{ratio:>7}  {mark}"
                    + ("  " + " ".join(extra) if extra else ""))
    return "\n".join(rows)


def main(argv: list[str] | None = None) -> int:
    argv = _normalize_argv(list(sys.argv[1:] if argv is None else argv))
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--lexicon", required=True, type=Path,
                   help="alan terimleri JSON'u (çekirdek alan sözlüğü taşımaz)")
    p.add_argument("--id", action="append", default=[],
                   help="video kimliği; `-` ile başlayanlar da güvenli")
    p.add_argument("--id-file", type=Path,
                   help="satır başına bir kimlik (# yorum satırı)")
    p.add_argument("--json", type=Path, help="makine-okur rapor yolu")
    p.add_argument("--purity-ratio", type=float, default=DEFAULT_PURITY_RATIO)
    p.add_argument("--thin-below-s", type=float, default=DEFAULT_THIN_DURATION_S)
    args = p.parse_args(argv)

    # Bayat rig UYARISI — gotcha #4: çıktı sessizce güvenilir görünmesin.
    warning = rig_staleness_warning()
    if warning:
        print(warning, file=sys.stderr)

    lex = Lexicon.load(args.lexicon)

    ids: list[str] = list(args.id)
    if args.id_file:
        for line in args.id_file.read_text(encoding="utf-8").splitlines():
            s = line.split("#", 1)[0].strip()
            if s:
                ids.append(s)
    if not ids:
        p.error("hiç kimlik verilmedi (--id / --id-file)")

    verdicts: list[Verdict] = []
    with tempfile.TemporaryDirectory(prefix="d1-gate-") as tmp:
        for vid in ids:
            text, dur = fetch_subtitle(vid, workdir=Path(tmp))
            verdicts.append(judge(vid, text, dur, lex,
                                  purity_ratio=args.purity_ratio,
                                  thin_below_s=args.thin_below_s))

    print(_render(verdicts, lex))

    if args.json:
        args.json.write_text(json.dumps({
            # Hangi RIG hüküm verdi — bayatsa karar da bayattır (M-F-135).
            "rig": rig_version(),
            "target": lex.target_name,
            "purityRatio": args.purity_ratio,
            "thinBelowSeconds": args.thin_below_s,
            "note": ("D1 konu triyajıdır, OLAY etiketi DEĞİL; her sayısal "
                     "iddia göz-doğrulamasına bağlanır (M-F-200)"),
            "verdicts": [asdict(v) for v in verdicts],
        }, ensure_ascii=False, indent=2), encoding="utf-8")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
