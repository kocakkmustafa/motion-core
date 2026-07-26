# MediaPipe Pose Landmarker — pinli model bundle'ları

**Tarih:** 2026-07-26 · **Statü:** aile-geneli (motion-core) · Kaynak: `10-ARAC-KATALOGU.md §1`

Katalog kuralı: *"Resmî statü hâlâ Solutions Preview (SLA yok) → model sürümü PİNLENİR, ModelVersion her kayıtta saklanır."*

## Kanonik sürüm: `/float16/1/` (URL'de sürüm segmenti pinli)

| Varyant | Dosya | Boyut (byte) | SHA-256 |
|---|---|---|---|
| lite | `pose_landmarker_lite.v1.task` | 5 777 746 (5.5 MiB) | `59929e1d1ee95287735ddd833b19cf4ac46d29bc7afddbbf6753c459690d574a` |
| full | `pose_landmarker_full.v1.task` | 9 398 198 (9.0 MiB) | `5134a3aad27a58b93da0088d431f366da362b44e3ccfbe3462b3827a839011b1` |
| heavy | `pose_landmarker_heavy.v1.task` | 30 664 242 (29.2 MiB) | `64437af838a65d18e5ba7a0d39b465540069bc8aae8308de3e318aad31fcbc7b` |

İndirme: `https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_<varyant>/float16/1/pose_landmarker_<varyant>.task`

## ⚠️ ÖLÇÜLMÜŞ BULGU (2026-07-26): `latest` ≠ `1` — `full` varyantında

Aynı gün indirilen `/float16/latest/` ve `/float16/1/` bundle'ları karşılaştırıldı:

| Varyant | `1` vs `latest` | Not |
|---|---|---|
| lite | ✅ özdeş | — |
| full | ❌ **FARKLI** (aynı boyut 9 398 198, farklı hash) | `latest` = `4eaa5eb7a98365221087693fcc286334cf0858e2eb6e15b506aa4a7ecdcec4ad` |
| heavy | ✅ özdeş | — |

**Sonuç:** `latest` etiketi sessizce güncelleniyor ve boyut değişmediği için fark gözden kaçabilir. Hiçbir yerde (Python hattı, Android asset, iOS bundle) `latest` KULLANILMAZ.

**Kural:** her build, buradaki SHA-256'yı doğrular; hash tutmuyorsa build durur. `full.latest` karşılaştırma amacıyla saklanır (G1-b kapı ölçümünde v1-vs-latest farkı ölçülebilir), üretimde kullanılmaz.

Aile DEFTER kaydı: **M-L-01**.
