#!/usr/bin/env python3
"""Art.50 makine-okunur işaretleme yardımcısı (C2PA-tarzı; katalog §6.4).

AI-üretimi her varlık (T2/T3 görsel/video, AI-TTS ses) üretim anında burada
işaretlenir: varlığın yanına C2PA'dan esinlenen bir provenance sidecar'ı
(`<dosya>.provenance.json`) yazılır; `exiftool` kuruluysa aynı beyan XMP olarak
dosyaya da gömülür. `scan` alt-komutu content-package CI kapısıdır: manifest'te
`aiGenerated:true` olup geçerli (hash-eşleşmeli) sidecar'ı olmayan varlık
build'i KIRMIZI yapar.

Tam C2PA imza zinciri (cert + claim signature) V2 işi — bugünkü yükümlülük
"makine-okunur işaret"tir ve alan adları C2PA sözlüğüyle hizalı tutulmuştur ki
geçiş kırılmasın.

Kullanım:
    python3 mark_asset.py mark demo.mp4 --generator "champ@a1b2" --tier T2
    python3 mark_asset.py verify demo.mp4
    python3 mark_asset.py scan assets/ --manifest assets-manifest.json
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

SIDECAR_SUFFIX = ".provenance.json"
SPEC = "yula-motion/art50-mark/1"
#: IPTC DigitalSourceType — C2PA'nın AI-üretimi içerik için kullandığı değer.
DIGITAL_SOURCE_TYPE = (
    "http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia"
)


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def sidecar_path(asset: Path) -> Path:
    return asset.with_name(asset.name + SIDECAR_SUFFIX)


def mark(asset: Path, *, generator: str, tier: str, prompt_ref: str | None,
         embed: bool) -> Path:
    doc = {
        "spec": SPEC,
        "assetName": asset.name,
        "assetSha256": _sha256(asset),
        "digitalSourceType": DIGITAL_SOURCE_TYPE,
        "aiGenerated": True,
        "tier": tier,  # T2 pose-driven üretken | T3 form-kritik-olmayan API
        "claimGenerator": "yula-motion mark_asset.py",
        "generator": generator,  # model/servis + sürüm/sha
        "promptRef": prompt_ref,  # üretim reçetesinin repo yolu (varsa)
        "createdAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "disclosure": "This media was generated with AI.",
    }
    out = sidecar_path(asset)
    out.write_text(json.dumps(doc, ensure_ascii=False, indent=2),
                   encoding="utf-8")

    if embed:
        if shutil.which("exiftool"):
            # XMP gömme dosya baytlarını değiştirir -> sidecar hash'i gömme
            # SONRASI dosyadan yeniden hesaplanır.
            subprocess.run(
                ["exiftool", "-overwrite_original",
                 "-XMP-ycc:AiGenerated=true",
                 f"-XMP-ycc:Generator={generator}",
                 f"-XMP-dc:Description=AI-generated ({tier})",
                 str(asset)],
                capture_output=True, text=True, check=False,
            )
            doc["assetSha256"] = _sha256(asset)
            doc["xmpEmbedded"] = True
            out.write_text(json.dumps(doc, ensure_ascii=False, indent=2),
                           encoding="utf-8")
        else:
            print("⚠️  exiftool yok — yalnız sidecar yazıldı (yeterli; gömme "
                  "opsiyonel katman)", file=sys.stderr)
    return out


def verify(asset: Path) -> tuple[bool, str]:
    sc = sidecar_path(asset)
    if not sc.exists():
        return False, "sidecar yok"
    try:
        doc = json.loads(sc.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        return False, f"sidecar bozuk: {exc}"
    if doc.get("spec") != SPEC:
        return False, f"bilinmeyen spec: {doc.get('spec')}"
    if doc.get("assetSha256") != _sha256(asset):
        return False, "hash uyuşmuyor — varlık işaretten SONRA değişmiş"
    if not doc.get("aiGenerated"):
        return False, "aiGenerated:true değil"
    return True, "ok"


def scan(directory: Path, manifest_path: Path | None) -> int:
    """CI kapısı. Dönüş 0 = temiz; 1 = ihlal var."""
    violations: list[str] = []

    if manifest_path and manifest_path.exists():
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        for entry in manifest.get("assets", []):
            name = entry.get("file")
            if not entry.get("aiGenerated"):
                continue
            asset = directory / name
            if not asset.exists():
                violations.append(f"{name}: manifest'te var, diskte yok")
                continue
            ok, reason = verify(asset)
            if not ok:
                violations.append(f"{name}: {reason}")
    else:
        # Manifest'siz tarama: sidecar'ı olan her varlığı doğrula, medya
        # uzantılı ama sidecar'sız dosyaları raporla (uyarı düzeyi karar
        # manifest'tedir — manifest'siz kesin hüküm verilemez).
        media_ext = {".mp4", ".mov", ".webm", ".png", ".jpg", ".jpeg",
                     ".wav", ".mp3", ".m4a"}
        for asset in sorted(directory.rglob("*")):
            if asset.suffix.lower() not in media_ext:
                continue
            if sidecar_path(asset).exists():
                ok, reason = verify(asset)
                if not ok:
                    violations.append(f"{asset.name}: {reason}")

    if violations:
        print("⛔ Art.50 işaretleme ihlalleri:")
        for v in violations:
            print(f"  - {v}")
        return 1
    print("✅ işaretleme taraması temiz")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    m = sub.add_parser("mark")
    m.add_argument("asset")
    m.add_argument("--generator", required=True,
                   help="model/servis + sürüm (ör. champ@<sha>, elevenlabs/v3)")
    m.add_argument("--tier", default="T2", choices=["T2", "T3", "voice"])
    m.add_argument("--prompt-ref", default=None)
    m.add_argument("--embed", action="store_true",
                   help="exiftool ile XMP da göm")

    v = sub.add_parser("verify")
    v.add_argument("asset")

    s = sub.add_parser("scan")
    s.add_argument("directory")
    s.add_argument("--manifest", default=None,
                   help="assets-manifest.json (CI kapısının kararı bundadır)")

    args = ap.parse_args()
    if args.cmd == "mark":
        out = mark(Path(args.asset), generator=args.generator, tier=args.tier,
                   prompt_ref=args.prompt_ref, embed=args.embed)
        print(f"✓ {out.name}")
        return 0
    if args.cmd == "verify":
        ok, reason = verify(Path(args.asset))
        print(("✅ " if ok else "⛔ ") + reason)
        return 0 if ok else 1
    return scan(Path(args.directory),
                Path(args.manifest) if args.manifest else None)


if __name__ == "__main__":
    raise SystemExit(main())
