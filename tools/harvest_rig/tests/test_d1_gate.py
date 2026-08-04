#!/usr/bin/env python
"""D1 kapısı birim testleri — AĞ ERİŞİMSİZ.

`judge()` bilerek saf fonksiyon: altyazı çekme (ağ) ile hüküm (mantık) ayrı,
o yüzden kapının kendisi sentetik metinle sınanabiliyor. Ağ gerektiren tek
parça `fetch_subtitle` ve o burada koşmuyor — sınanan şey ONUN ÇIKTISININ
NASIL YORUMLANDIĞI.

Koşum:
    python3 tests/test_d1_gate.py
"""
from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import d1_gate  # noqa: E402
from d1_gate import Lexicon, LexiconError, judge  # noqa: E402

FAILURES: list[str] = []


def check(cond: bool, msg: str) -> None:
    print(("  ✅ " if cond else "  ❌ ") + msg)
    if not cond:
        FAILURES.append(msg)


def make_lexicon(tmp: Path, **overrides) -> Lexicon:
    doc = {
        "target": {"hook": ["hook", "hooks"]},
        "others": {"jab": ["jab", "jabs"], "cross": ["cross", "straight"]},
        "variants": {"bag_or_mitt": ["bag", "mitt", "pad"]},
    }
    doc.update(overrides)
    path = tmp / "lex.json"
    path.write_text(json.dumps(doc), encoding="utf-8")
    return Lexicon.load(path)


def main() -> int:
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        lex = make_lexicon(tmp)

        print("\n— argv normalizasyonu (`-` ile başlayan kimlik) —")
        # Lissom L-191 sınıfı: YouTube kimlikleri base64url'den gelir ve `-`
        # ile BAŞLAYABİLİR; argparse onu bir sonraki bayrak sanar.
        norm = d1_gate._normalize_argv(["--id", "-abc123XY", "--json", "r.json"])
        check("--id=-abc123XY" in norm,
              "`--id -abc123` → `--id=-abc123` (argparse tuzağı kapandı)")
        # POZİTİF İKİZ: normal kimlik BOZULMAMALI. Yukarıdaki iddia, her
        # değeri `=`li hâle çeviren bir kusurla da geçerdi — bu ikiz onu
        # ayırt etmiyor; ayırt eden şey aşağıdaki gerçek parse.
        argv = d1_gate._normalize_argv(
            ["--lexicon", str(tmp / "lex.json"), "--id", "-abc123XY",
             "--id", "normalID42"])
        import argparse
        p = argparse.ArgumentParser()
        p.add_argument("--lexicon")
        p.add_argument("--id", action="append", default=[])
        parsed = p.parse_args(argv)
        check(parsed.id == ["-abc123XY", "normalID42"],
              "gerçek parse: hem `-`li hem normal kimlik AYNI listede")

        print("\n— oran kapısı —")
        v = judge("v1", "hook hook hook hook jab", 600.0, lex)
        check(v.ok and v.reason == "pass", "4 hedef vs 1 diğer → GEÇER")
        v = judge("v2", "hook hook jab cross straight", 600.0, lex)
        check(not v.ok and v.reason == "mixed-content",
              "2 hedef vs 3 diğer → karışık içerik, KALIR")
        v = judge("v3", "hook hook jab", 600.0, lex)
        check(v.ok, "tam sınırda (2 = 2×1) GEÇER — kapı kapsayıcı")

        print("\n— sıfır-anma tuzağı —")
        # "0 >= 2*0" aritmetik olarak DOĞRU; ayrı dal olmasaydı hiç teknik
        # anmayan bir kaynak sessizce GEÇERDİ (`PxVQ7HKKchQ` tam buydu).
        v = judge("v4", "welcome to the channel, like and subscribe", 300.0, lex)
        check(not v.ok and v.reason == "no-target-mention",
              "hiç hedef anması yok → KALIR (0>=0 tuzağına düşmüyor)")

        print("\n— altyazı yokluğu ≠ eleme —")
        v = judge("v5", None, None, lex)
        check(v.reason == "nosub",
              "altyazı YOK ayrı sebep — 'uygun değil' ile karışmıyor")
        check(not v.ok, "ama otomatik GEÇMİYOR da (kapıdan geçmemiş sayılır)")

        print("\n— malzeme boyutu kapı DEĞİL, uyarı —")
        v = judge("v6", "hook hooks hook", 120.0, lex)
        check(v.ok and v.material == "thin",
              "2 dk mükemmel saflık: GEÇER ama 'thin' damgalı "
              "(FJJy6Zc3XhM dersi — saflık ≠ ölçülebilirlik)")
        v = judge("v7", "hook hooks hook", 600.0, lex)
        check(v.ok and v.material == "ok", "POZİTİF İKİZ: 10 dk → 'ok'")
        v = judge("v8", "hook hooks hook", None, lex)
        check(v.material == "unknown",
              "süre bilinmiyorsa UYDURULMUYOR ('ok' varsayılmıyor)")

        print("\n— varyant taraması (M-F-175) —")
        v = judge("v9", "hook hook on the bag and the mitt", 600.0, lex)
        check(v.ok, "varyant anması OTO-RET DEĞİL — kaynak elenmiyor")
        check(v.needs_eye_check and v.variant_hits["bag_or_mitt"] == 2,
              "ama göz-doğrulaması ZORUNLU işaretleniyor (2 anma)")
        v = judge("v10", "hook hook shadow work only", 600.0, lex)
        check(not v.needs_eye_check,
              "POZİTİF İKİZ: varyant anması yoksa göz-bayrağı da yok")

        print("\n— kelime sınırı —")
        v = judge("v11", "hooked on hooligans", 600.0, lex)
        check(v.reason == "no-target-mention",
              "'hooked'/'hooligans' hedef sayılmıyor — alt-dize eşleşmesi YOK")

        print("\n— sözlük doğrulaması patlar, sessizce boşa düşmez —")
        try:
            make_lexicon(tmp, target={"a": ["x"], "b": ["y"]})
            check(False, "iki hedefli sözlük reddedilmeli")
        except LexiconError:
            check(True, "iki hedefli sözlük REDDEDİLDİ (oran kapısı anlamsızlaşır)")
        try:
            make_lexicon(tmp, others={"jab": ["hook"]})
            check(False, "çakışan terim reddedilmeli")
        except LexiconError:
            check(True, "hedef terimi `others`ta da varsa REDDEDİLDİ "
                        "(aynı anma hem pay hem payda olurdu)")
        try:
            Lexicon.load(tmp / "yok.json")
            check(False, "eksik dosya reddedilmeli")
        except LexiconError:
            check(True, "okunamayan sözlük REDDEDİLDİ (boş sayıma düşmüyor)")
        try:
            # Gerçek vaka: JabLab sözlüğünü yazarken `variants` içine açıklama
            # koydum. `list("uzun cümle")` HARFLERE böler ve kelime-sınırlı
            # regex tek harflerden kurulur — her kaynak her şeyle eşleşir.
            make_lexicon(tmp, variants={"$comment": "açıklama metni"})
            check(False, "dize değerli terim listesi reddedilmeli")
        except LexiconError:
            check(True, "terim listesi yerine DİZE verilirse REDDEDİLDİ "
                        "(harflere bölünüp 'ölçülen sanılan çöp' üretmiyor)")
        lex_ok = make_lexicon(tmp, target={"$comment": "not", "hook": ["hook"]})
        check(lex_ok.target_name == "hook",
              "POZİTİF İKİZ: üst düzey `$comment` anahtarı hedefi bozmuyor")

    print()
    if FAILURES:
        print(f"❌ {len(FAILURES)} test düştü")
        return 1
    print("✅ d1_gate: tüm testler geçti")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
