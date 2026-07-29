#!/usr/bin/env python
"""Kurucusuz Veri Fabrikası — hasat boru hattı CLI (M-F-13).

Aşamalar (her biri manifest'e kanıtla yazılır; provenance'sız klip İLERLEYEMEZ):

  pull       yt-dlp ile indir (--write-info-json ZORUNLU -> manifest)
  triage     M-O-02 ön-eleme (süre/en-boy/kesme/netlik/üst-gövde)
  dedup      algısal imza (aHash dizisi) — kütüphanedeki kopyaları eler
  extract    fixture_pipeline/extract_landmarks.py --file (provenance gömülü)
  transcribe faster-whisper koçluk-dili madenciliği (kuruluysa)

Kullanım:
  # tek video uçtan uca
  python harvest.py run --url https://youtu.be/... --app jablab --library ~/harvest/jablab

  # yerel dosyayı yalnız triyajdan geçir
  python harvest.py probe VIDEO.mp4

Lisans denetimi (katalog §0/6.2): yt-dlp Unlicense ✓ · PySceneDetect BSD-3 ✓
(opsiyonel) · imagededup Apache ✓ (opsiyonel; yerleşik aHash varsayılan) ·
faster-whisper MIT ✓ (opsiyonel) · ❌ internetarchive paketi (AGPL) bu rig'e
GİRMEZ. Hasat edilen videonun KENDİSİ ship edilmez; yalnız landmark/etiket
türevleri kullanılır (C-017 kurucu-kabul çerçevesi).
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
from manifest import HarvestManifest  # noqa: E402
from rom_mode import classify as classify_rom
from triage import TriageThresholds, triage  # noqa: E402

FIXTURE_PIPELINE = Path(__file__).parent.parent / "fixture_pipeline"
DEFAULT_POSE_MODEL = FIXTURE_PIPELINE / "models" / "pose_landmarker_full.v1.task"


# --------------------------------------------------------------------------
# pull — yt-dlp + info-json provenance
# --------------------------------------------------------------------------

def pull(url: str, out_dir: Path, *, app: str) -> HarvestManifest:
    out_dir.mkdir(parents=True, exist_ok=True)
    tmpl = str(out_dir / "%(id)s.%(ext)s")
    cmd = [
        "yt-dlp",
        "--write-info-json",
        "--no-playlist",
        # 1080p tavan: pose çıkarımı için yeterli, disk/AB yükü yarıya iner.
        "-f", "bv*[height<=1080]+ba/b[height<=1080]/b",
        "--merge-output-format", "mp4",
        "-o", tmpl,
        url,
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"yt-dlp başarısız:\n{proc.stderr[-800:]}")

    info_files = sorted(out_dir.glob("*.info.json"),
                        key=lambda p: p.stat().st_mtime)
    if not info_files:
        raise RuntimeError("info.json üretilmedi — provenance'sız klip kabul edilmez")
    info = json.loads(info_files[-1].read_text(encoding="utf-8"))

    video_id = info.get("id", "unknown")
    m = HarvestManifest.start(
        app=app, video_id=video_id,
        source_url=info.get("webpage_url", url),
    )
    m.absorb_info_json(info)

    for ext in ("mp4", "mkv", "webm"):
        cand = out_dir / f"{video_id}.{ext}"
        if cand.exists():
            m.local_path = str(cand)
            break
    m.record("pull", "ok" if m.local_path else "error",
             file=Path(m.local_path).name if m.local_path else None)
    return m


# --------------------------------------------------------------------------
# dedup — algısal imza (yerleşik; imagededup kuruluysa o da kullanılabilir)
# --------------------------------------------------------------------------

def perceptual_signature(path: str | Path, n_frames: int = 8) -> str:
    """Videonun 8-karelik aHash dizisi (hex). Aynı içerik farklı encode'da
    aynı imzaya düşer; farklı videolar arası Hamming uzaklığı büyüktür."""
    cap = cv2.VideoCapture(str(path))
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    n_total = cap.get(cv2.CAP_PROP_FRAME_COUNT) or 1
    duration_s = n_total / fps
    bits: list[int] = []
    for t in np.linspace(0.5, max(duration_s - 0.5, 1.0), n_frames):
        cap.set(cv2.CAP_PROP_POS_MSEC, float(t) * 1000.0)
        ok, frame = cap.read()
        if not ok:
            bits.extend([0] * 64)
            continue
        g = cv2.cvtColor(cv2.resize(frame, (8, 8)), cv2.COLOR_BGR2GRAY)
        bits.extend(int(v) for v in (g > g.mean()).flatten())
    cap.release()
    return "".join(
        f"{int(''.join(map(str, bits[i:i + 8])), 2):02x}"
        for i in range(0, len(bits), 8)
    )


def hamming(sig_a: str, sig_b: str) -> int:
    if len(sig_a) != len(sig_b):
        return 10 ** 9
    return bin(int(sig_a, 16) ^ int(sig_b, 16)).count("1")


def check_duplicate(
    signature: str, library_index: Path, threshold: int = 64,
    *, self_id: str | None = None,
) -> str | None:
    """Kütüphanede yakın imza varsa video_id'sini döner.

    `self_id` DIŞLANIR: indekste kayıtlı bir videoyu yeniden koşmak
    "kopya: X ile eşleşti" derdi — X'in kendisi. Yeniden hasadı imkânsız
    kılıyor ve mesaj yanıltıcıydı (L-106).
    """
    if not library_index.exists():
        return None
    index = json.loads(library_index.read_text(encoding="utf-8"))
    for vid, sig in index.items():
        if vid == self_id:
            continue
        if hamming(signature, sig) <= threshold:
            return vid
    return None


def register_signature(signature: str, video_id: str, library_index: Path) -> None:
    index: dict[str, str] = {}
    if library_index.exists():
        index = json.loads(library_index.read_text(encoding="utf-8"))
    index[video_id] = signature
    library_index.write_text(json.dumps(index, indent=1), encoding="utf-8")


# --------------------------------------------------------------------------
# extract — fixture_pipeline'a devir (tek çıkarım aracı ilkesi)
# --------------------------------------------------------------------------

def extract(m: HarvestManifest, out_dir: Path, *, variant: str) -> Path:
    assert m.local_path, "extract için indirilmiş dosya gerekir"
    out_path = out_dir / f"{m.video_id}.{variant}.json"
    cmd = [
        sys.executable,
        str(FIXTURE_PIPELINE / "extract_landmarks.py"),
        "--file", m.local_path,
        "--out", str(out_path),
        "--app", m.app,
        "--variant", variant,
        "--source-url", m.source_url,
        "--license", m.license or "standard-youtube",
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True,
                          cwd=str(FIXTURE_PIPELINE))
    if proc.returncode != 0:
        raise RuntimeError(f"extract başarısız:\n{proc.stderr[-800:]}")
    # Fixture'ın provenance bloğunu manifest'in TAM bloğuyla zenginleştir
    # (extract yalnız url+lisans yazar; kanal/tarih/araç-sürümleri manifest'te).
    doc = json.loads(out_path.read_text(encoding="utf-8"))
    doc["provenance"] = {**doc.get("provenance", {}), **m.provenance_block()}
    out_path.write_text(json.dumps(doc, ensure_ascii=False), encoding="utf-8")
    return out_path


# --------------------------------------------------------------------------
# transcribe — koçluk-dili madenciliği (opsiyonel katman)
# --------------------------------------------------------------------------

def transcribe(m: HarvestManifest, out_dir: Path) -> Path | None:
    try:
        from faster_whisper import WhisperModel  # noqa: PLC0415
    except ImportError:
        m.record("transcribe", "skipped", reason="faster-whisper kurulu değil")
        return None
    assert m.local_path
    # Dizin yoksa yazım FileNotFoundError ile ÇÖKER ve boru hattı, fixture
    # üretildikten SONRA patlar: klip diske yazılmış ama imza indeksine
    # kaydedilmemiş olur (yeniden koşumda "kopya" sanılır). Gece boyunca
    # --no-transcribe koşulduğu için bu yol hiç çalışmamıştı; transkript
    # zorunlu hale gelir gelmez BAŞARILI her aday burada çöküyordu.
    out_dir.mkdir(parents=True, exist_ok=True)
    model = WhisperModel("small", compute_type="int8")
    segments, _info = model.transcribe(m.local_path, vad_filter=True)
    out_path = out_dir / f"{m.video_id}.transcript.json"
    out_path.write_text(
        json.dumps(
            [{"start": round(s.start, 2), "end": round(s.end, 2),
              "text": s.text.strip()} for s in segments],
            ensure_ascii=False, indent=1,
        ),
        encoding="utf-8",
    )
    m.record("transcribe", "ok", file=out_path.name)
    return out_path


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------

def load_rom_policy(path: str | None, movement: str | None) -> bool:
    """M-F-45: bu harekette pasif icra biyomekanik olarak mümkün mü.

    Varsayılan `True` = muhafazakâr (fail-closed sürer). Profil politika
    taşıyor ama hareket orada YOKSA sert hata: sessizce varsayılana düşmek,
    kuralın hangi harekette uygulandığını belirsizleştirir.
    """
    if not path:
        return True
    doc = json.loads(Path(path).read_text(encoding="utf-8"))
    policy = doc.get("movementRomPolicy")
    if not policy:
        return True
    if movement not in policy:
        raise SystemExit(
            f"{path}: movementRomPolicy'de '{movement}' yok. "
            f"Tanımlı: {', '.join(sorted(policy))}"
        )
    return bool(policy[movement])


def load_triage_profile(
    path: str | None, movement: str | None = None
) -> TriageThresholds:
    """App-özel triyaj eşiklerini yükle. Bilinmeyen anahtar SESSİZCE YUTULMAZ.

    Sessiz yutma, "eşiği verdim ama etkisi yok" hatasının en sinsi biçimidir:
    komut başarıyla koşar, ölçüm yanlış eşikle yapılır, hiçbir şey söylemez.
    """
    if not path:
        return TriageThresholds()
    from dataclasses import fields as _dc_fields  # noqa: PLC0415

    doc = json.loads(Path(path).read_text(encoding="utf-8"))
    raw = dict(doc.get("thresholds", doc))
    known = {f.name for f in _dc_fields(TriageThresholds)}
    unknown = set(raw) - known
    if unknown:
        raise SystemExit(
            f"{path}: bilinmeyen triyaj eşiği: {', '.join(sorted(unknown))}\n"
            f"Geçerli anahtarlar: {', '.join(sorted(known))}"
        )

    # Hangi landmark'ların kadrajda olacağı HAREKETE göre değişir. Sabit bir
    # "tam gövde" şartı, ölçümü ayak bileğine hiç bakmayan testlerin adaylarını
    # reddediyordu — gerçek veride ölçüldü (L-080): üç `overhead_reach` klibi
    # ayak-bileği şartıyla 0.00 alıp reddedilirken, testin GERÇEKTEN istediği
    # kalça kümesiyle 0.75-1.00 alıyor.
    per = doc.get("perMovement")
    if per:
        if movement is None:
            raise SystemExit(
                f"{path}: profil perMovement taşıyor ama --movement verilmedi. "
                "Harekete özel landmark şartı sessizce atlanamaz."
            )
        if movement not in per:
            raise SystemExit(
                f"{path}: perMovement'ta '{movement}' yok. "
                f"Tanımlı: {', '.join(sorted(per))}"
            )
        raw["lower_body_ids"] = tuple(per[movement])
    return TriageThresholds(**raw)


def cmd_probe(args: argparse.Namespace) -> int:
    model = DEFAULT_POSE_MODEL if DEFAULT_POSE_MODEL.exists() else None
    r = triage(args.video, pose_model=None if args.no_pose else model)
    print(json.dumps(r.to_detail(), ensure_ascii=False, indent=2))
    print("KABUL" if r.accepted else "RET")
    return 0 if r.accepted else 1


def cmd_run(args: argparse.Namespace) -> int:
    library = Path(args.library).expanduser()
    raw_dir, fx_dir = library / "raw", library / "landmarks"
    manifest_dir = library / "manifests"
    manifest_dir.mkdir(parents=True, exist_ok=True)

    m = pull(args.url, raw_dir, app=args.app)
    manifest_path = manifest_dir / f"{m.video_id}.json"
    try:
        if not m.local_path:
            m.save(manifest_path)
            print(f"❌ indirme çıktısı bulunamadı ({m.video_id})")
            return 1

        model = DEFAULT_POSE_MODEL if DEFAULT_POSE_MODEL.exists() else None
        r = triage(m.local_path,
                   thresholds=load_triage_profile(
                       getattr(args, "triage_profile", None),
                       getattr(args, "movement", None)),
                   pose_model=model)
        m.record("triage", "ok" if r.accepted else "rejected",
                 **r.to_detail())
        if not r.accepted:
            print(f"⛔ triyaj reddi: {'; '.join(r.rejects)}")
            return 1

        # M-F-43 kaynak-uygunluk: gösterilen hareket AKTİF mi? Pasif ROM'da
        # aralık klinisyen tarafından üretilir ve aktiften geniştir; böyle bir
        # kaynaktan türetilen referans ULAŞILAMAZ hedef koyar. Ayrım kamerada
        # GÖRÜNMEZ, yalnız kaynağın anlatısında vardır. Klip REDDEDİLMEZ —
        # taksonomi/yöntem kaynağı olarak değerli — ama referansa giremez.
        pep = load_rom_policy(getattr(args, "triage_profile", None),
                              getattr(args, "movement", None))
        rom = classify_rom(title=m.title or "", description=m.description or "",
                           passive_execution_possible=pep)
        m.rom_mode = rom.mode
        m.reference_eligible = rom.reference_eligible
        m.record("romMode", rom.mode, **rom.to_detail())
        if not rom.reference_eligible:
            print(f"⚠️  referansa UYGUN DEĞİL ({rom.mode}): {rom.reason}")

        sig = perceptual_signature(m.local_path)
        m.dedup_signature = sig
        dup = check_duplicate(sig, library / "signature-index.json",
                              self_id=m.video_id)
        if dup:
            m.record("dedup", "rejected", duplicateOf=dup)
            print(f"⛔ kopya: {dup} ile eşleşti")
            return 1
        m.record("dedup", "ok")

        fx_dir.mkdir(parents=True, exist_ok=True)
        fx_path = extract(m, fx_dir, variant=args.variant)
        m.record("extract", "ok", fixture=fx_path.name)

        tr_path = (transcribe(m, library / "transcripts")
                   if not args.no_transcribe
                   else m.record("transcribe", "skipped",
                                 reason="--no-transcribe"))
        # Transkript en güçlü kanıt: "I'll move your arm", "just relax" gibi
        # ifadeler başlıkta görünmez. Erken sınıflandırma fail-closed olduğu
        # için yalnız DAHA İZİNLİ yöne dönebilir; bu yüzden yeniden koşulur.
        if isinstance(tr_path, Path) and tr_path.exists():
            spoken = " ".join(
                seg.get("text", "")
                for seg in json.loads(tr_path.read_text(encoding="utf-8"))
            )
            rom2 = classify_rom(title=m.title or "", description=m.description or "",
                                transcript=spoken, passive_execution_possible=pep)
            if rom2.mode != m.rom_mode:
                print(f"↻ romMode transkriptle güncellendi: "
                      f"{m.rom_mode} → {rom2.mode} ({rom2.reason})")
            m.rom_mode, m.reference_eligible = rom2.mode, rom2.reference_eligible
            m.record("romMode", rom2.mode, source="transcript", **rom2.to_detail())
            doc = json.loads(fx_path.read_text(encoding="utf-8"))
            doc["provenance"] = {**doc.get("provenance", {}), **m.provenance_block()}
            fx_path.write_text(json.dumps(doc, ensure_ascii=False), encoding="utf-8")

        register_signature(sig, m.video_id, library / "signature-index.json")
        print(f"✅ {m.video_id}: fixture={fx_path.name}")
        return 0
    finally:
        m.save(manifest_path)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("probe", help="yerel videoyu triyajdan geçir")
    p.add_argument("video")
    p.add_argument("--no-pose", action="store_true")
    p.set_defaults(fn=cmd_probe)

    r = sub.add_parser("run", help="URL'i uçtan uca hasat et")
    r.add_argument("--url", required=True)
    r.add_argument("--app", required=True,
                   choices=["lissom", "jablab", "gravita", "ostinato", "choreia"])
    r.add_argument("--library", required=True,
                   help="hasat kütüphanesi kökü (raw/landmarks/manifests)")
    r.add_argument("--variant", default="full",
                   choices=["lite", "full", "heavy"])
    r.add_argument("--no-transcribe", action="store_true")
    r.add_argument(
        "--triage-profile",
        help="App-özel triyaj eşikleri (JSON). Örn. lissom app/config/harvest/"
             "triage-profile.v1.json — alt-vücut testli app'ler min_full_body_ratio "
             "verir. Verilmezse rig varsayılanları kullanılır.",
    )
    r.add_argument(
        "--movement",
        help="Adayın hangi test/hareket için toplandığı. Profil `perMovement` "
             "taşıyorsa ZORUNLU: kadrajda aranan landmark'lar harekete göre "
             "değişir ve sabit bir 'tam gövde' şartı, ayak bileğine hiç "
             "bakmayan testlerin adaylarını reddeder (L-080).",
    )
    r.set_defaults(fn=cmd_run)

    args = ap.parse_args()
    return args.fn(args)


if __name__ == "__main__":
    raise SystemExit(main())
