"""motion-core offline ölçüm hattı — referans implementasyon.

Üretim motoru native (Kotlin/Swift). Bu paket:
  1. video -> fixture JSON çıkarır (G3),
  2. ölçüm matematiğinin referansını tutar (G1-a kapısı, differential test),
  3. sentetik iskeletle kapı ölçümü koşar.
"""

__version__ = "0.1.0"
