#!/usr/bin/env bash
# MediaPipe Pose Landmarker bundle'larını PİNLİ sürümden indirir ve hash doğrular.
# Model dosyaları repoda tutulmaz (45 MB); bu betik onları yeniden üretir.
# Hash kaynağı: models/MODELS.md — uyuşmazlık = build durur (M-L-01).
# Not: bash 3.2 (macOS varsayılanı) ile uyumlu — associative array kullanılmaz.
set -euo pipefail
cd "$(dirname "$0")/models"

sha_for() {
  case "$1" in
    lite)  echo 59929e1d1ee95287735ddd833b19cf4ac46d29bc7afddbbf6753c459690d574a ;;
    full)  echo 5134a3aad27a58b93da0088d431f366da362b44e3ccfbe3462b3827a839011b1 ;;
    heavy) echo 64437af838a65d18e5ba7a0d39b465540069bc8aae8308de3e318aad31fcbc7b ;;
    *)     echo "bilinmeyen varyant: $1" >&2; exit 2 ;;
  esac
}

for v in lite full heavy; do
  want=$(sha_for "$v")
  out="pose_landmarker_${v}.v1.task"
  if [ -f "$out" ] && [ "$(shasum -a 256 "$out" | cut -d' ' -f1)" = "$want" ]; then
    echo "  ✓ $v  (mevcut, hash doğru)"
    continue
  fi
  # /1/ PİNLİ — /latest/ KULLANILMAZ: full varyantında farklı içerik veriyor (M-L-01)
  url="https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_${v}/float16/1/pose_landmarker_${v}.task"
  echo "  ↓ $v indiriliyor..."
  curl -fsS -o "$out" "$url"
  got=$(shasum -a 256 "$out" | cut -d' ' -f1)
  if [ "$got" != "$want" ]; then
    echo "  ✗ HASH UYUŞMAZLIĞI ($v)" >&2
    echo "    beklenen: $want" >&2
    echo "    gelen   : $got" >&2
    echo "    Google bundle'ı değiştirmiş olabilir. MODELS.md güncellenmeden devam ETME." >&2
    exit 1
  fi
  echo "  ✓ $v  (indirildi, hash doğru)"
done
echo "Tüm modeller hazır."
