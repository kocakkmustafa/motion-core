"""Üretilen artefaktlarda SESSİZ ALAN KAYBI kapısı (M-F-174).

Neden bu kapı var
-----------------
Choreia'da aynı arıza ÜÇ KEZ tekrarlandı: bir yeniden üretim, artefaktta duran
bir alanı yok etti ve kimse fark etmedi (`excludedIdentityAmbiguous` ·
`namedVariant` · `excludedNotLesson`). Üçüncüsü sınıfın adını düzeltti:
o alan **elle yamalı değildi**, üretici onu her turda yeniden türetiyordu.
Kayboldu çünkü **girdisi gitti** — ölçümün dayandığı kaynak havuzdan çıkınca
ölçüm fonksiyonu onu göremedi, çıktı boş diziye düştü.

Aile sınıfı bu yüzden şöyle adlandırıldı: **"girdisi kalıcı olmayan alan
kaybolur."** Türetilmiş olmak koruma SAĞLAMAZ. Bu, artefakt üreten her hattı
ilgilendirir — hasat çıktıları, referanslar, akor/ses artefaktları, raporlar.

Neden SATIR-diff yetmez
-----------------------
Kaybı gören tek yer diff'tir, ama yeniden üretilen JSON'da satır-diff bir kayıp
detektörü DEĞİLDİR: üç referansın diff'i binlerce ondalık churn üretir ve
`- "excludedNotLesson": [` satırı o gürültüde görünmez (Choreia turunda gözle
tarandı ve İLK GEÇİŞTE KAÇIRILDI; kaybı anahtar-kümesi karşılaştırması yakaladı).

Bu kapı satırları değil **anahtar YOLLARINI** karşılaştırır. Dizi indeksleri
`[]` ile sıkıştırılır: bir dizinin UZUNLUĞU her üretimde değişebilir (kaynak
sayısı, çevrim sayısı), ama içindeki ALAN ADLARI değişmemeli. İndeksleri korumak
kapıyı gürültüye boğar, gürültülü kapı ise kapatılır.

Neden git-HEAD DEĞİL, açık TABAN dosyası
----------------------------------------
İlk uygulama (Choreia `tools/reference_keyset_gate.py`) tabanı `git show HEAD:`
ile okuyordu. Bunun **iki-commit kör noktası** var: A commit'i alanı kaybeder,
commit'lenir, ve artık HEAD *yeni taban* olur → B commit'i temiz geçer.
`namedVariant` TAM BÖYLE öldü — kayıp daha önceki bir regen'de olmuş, commit'lenmiş,
ve sonraki her karşılaştırma onu "zaten yok" saymıştı. Yani o kapı, üç kayıptan
birini TASARIMI GEREĞİ yakalayamazdı.

Açık taban (`.keyset-baseline.json`, commit'li) bunu kapatır: taban insan onaylı
ve kendiliğinden kaymaz. Kendi riski de var — taban güncellemesi, kaybın
onaylandığı yer olur. Bu yüzden `--update` bir kaybı **REDDEDER**, gerekçesi
`declaredRemovals`'ta beyan edilmedikçe; KAZANÇLARI ise serbestçe absorbe eder.
Asimetri kasıtlı: yeni alan eklemek gürültüsüz olmalı, alan düşürmek olmamalı.

Kapının SINIRI (dürüstlük notu — aynen taşınır)
-----------------------------------------------
Bu kapı bir alanın **VARLIĞINI** ölçer, **DEĞERİNİ** ölçmez. `spokenWords: 9`
yerine `spokenWords: 0` yazılsa bu araç susar. Alan-düzeyi kayıp bu hattın
ÖLÇÜLMÜŞ arıza kipiydi (3 vaka); değer-bozulmasının ölçülmüş bir vakası YOK, o
yüzden buraya kapı konmadı — ihtiyaç ÖLÇÜLDÜĞÜNDE eklenir.

Kardeş arıza kipi de kapının dışında: **"yazılmış ama okunmamış alan."** Choreia
R12'de `bestDeg` dizisi bir take'in diğerlerinin ~2 katı uzakta durduğunu
söylüyordu ve kimse sinyal olarak okumadı. Bu kapı alanın VAR olduğunu ölçebilir,
OKUNDUĞUNU ölçemez.

Kullanım
--------
    python3 artifact_keyset_gate.py <artefakt-dizini>
    python3 artifact_keyset_gate.py <artefakt-dizini> --update
    python3 artifact_keyset_gate.py --self-test

Uygulamalar bunu VENDOR eder (M-F-94: PIN_SHA + DECLARED_DIFFERENCES +
--drift-check); çekirdek Python rig'i kopyalanır, import edilmez.
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import date
from pathlib import Path
from typing import Any

BASELINE_NAME = ".keyset-baseline.json"
BASELINE_VERSION = 1


def keypaths(obj: Any, prefix: str = "") -> set[str]:
    """Anahtar YOLLARI kümesi; dizi indeksleri `[]` ile sıkıştırılır.

    `{"a": [{"b": 1}, {"b": 2}]}` → `{"a", "a[].b"}`. İki elemanın da aynı
    alanı taşıması tek yol üretir: ölçülen şey ŞEMA, veri hacmi değil.
    """
    found: set[str] = set()
    if isinstance(obj, dict):
        for key, value in obj.items():
            path = f"{prefix}.{key}" if prefix else key
            found.add(path)
            found |= keypaths(value, path)
    elif isinstance(obj, list):
        for item in obj:
            found |= keypaths(item, prefix + "[]")
    return found


def empty_containers(obj: Any, prefix: str = "") -> set[str]:
    """Değeri BOŞ LİSTE olan yolların kümesi (`"a[]"` biçiminde).

    Neden ayrı ölçülüyor: bir dizi boşaldığında alt anahtarları da yok olur ve
    bu, "kayıt yok edildi" ile AYNI imzayı üretir — C-113'ün gerçek arızası
    zaten tam buydu (`excludedNotLesson: []`). İkisini tek sınıfta toplamak
    tehlikeli: genel bir kaldırma beyanı, korunmak istenen alanı kapatır ve
    sonraki GERÇEK kayıp sessizce geçer. Bu yüzden boşalma kendi sınıfı, kendi
    beyanı (artefakt+yola ÖZGÜ, blanket değil).
    """
    found: set[str] = set()
    if isinstance(obj, dict):
        for key, value in obj.items():
            found |= empty_containers(value, f"{prefix}.{key}" if prefix else key)
    elif isinstance(obj, list):
        if not obj:
            found.add(prefix + "[]")
        for item in obj:
            found |= empty_containers(item, prefix + "[]")
    return found


def emptied_by(path: str, empties: set[str]) -> str | None:
    """Yol, boşalmış bir kapsayıcının altında mı? İse o kapsayıcıyı döndür."""
    for marker in empties:
        if path.startswith(marker + "."):
            return marker
    return None


def empty_baseline() -> dict[str, Any]:
    return {
        "schemaVersion": BASELINE_VERSION,
        "$comment": (
            "ANAHTAR-KUMESI TABANI (M-F-174). Uretilen artefaktlarda sessiz "
            "alan kaybini yakalar. Elle duzenlenmez: 'artifact_keyset_gate.py "
            "--update' ile tazelenir, ve --update bir alan KAYBINI reddeder — "
            "kaybi mesrulastirmak icin declaredRemovals'a ISIMLE + GEREKCEYLE "
            "yazilmasi gerekir. Taban git-HEAD yerine burada tutulur cunku "
            "HEAD kendiliginden kayar: bir kayip commit'lenince yeni taban olur "
            "ve sonraki karsilastirma temiz gecer (namedVariant tam boyle oldu). "
            "IKI AYRI BEYAN VAR: declaredRemovals = alan SEMADAN kaldirildi "
            "(genel); artifacts[<ad>].declaredEmpty = su artefaktta su kapsayici "
            "MESRU olarak bos (artefakt+yola OZGU, cunku genel bir beyan "
            "korunmak istenen alani kapatir ve sonraki gercek kaybi gecirir)."
        ),
        "declaredRemovals": {},
        "artifacts": {},
    }


def load_baseline(directory: Path) -> dict[str, Any]:
    path = directory / BASELINE_NAME
    if not path.exists():
        return empty_baseline()
    doc = json.loads(path.read_text(encoding="utf-8"))
    if doc.get("schemaVersion") != BASELINE_VERSION:
        raise SystemExit(
            f"{path}: schemaVersion {BASELINE_VERSION} bekleniyor, "
            f"{doc.get('schemaVersion')!r} bulundu — tabanı körlemesine "
            "okumak, kapıyı sessizce devre dışı bırakmaktır")
    return doc


def save_baseline(directory: Path, doc: dict[str, Any]) -> None:
    (directory / BASELINE_NAME).write_text(
        json.dumps(doc, ensure_ascii=False, indent=1, sort_keys=True) + "\n",
        encoding="utf-8")


def artifact_files(directory: Path) -> list[Path]:
    """Dizindeki artefaktlar; taban dosyasının kendisi hariç.

    Nokta ile başlayan dosyalar atlanır: taban ve benzeri defter dosyaları
    artefakt değildir, ve onları artefakt sanmak kapıyı kendi tabanına karşı
    kırar (Choreia'da `decisions.json` bu hatayı bir kez yaptırdı).
    """
    return sorted(p for p in directory.glob("*.json") if not p.name.startswith("."))


def declared(removals: dict[str, Any], path: str) -> bool:
    """Yolun herhangi bir parçası beyan edilmiş kaldırma mı?

    Kök beyan edilmişse yaprakları da beklenen kayıptır: `provisionalReason`
    gidince `provisionalReason.why` de gider, ve her yaprağı tek tek beyan
    ettirmek beyanı tören hâline getirir.
    """
    return any(seg in removals for seg in path.split("."))


def check(directory: Path) -> tuple[int, list[str]]:
    """(hata sayısı, rapor satırları)."""
    doc = load_baseline(directory)
    removals = doc.get("declaredRemovals") or {}
    recorded = doc.get("artifacts") or {}
    report: list[str] = []
    errors = 0

    files = artifact_files(directory)
    if not files:
        return 1, [f"✗ {directory}: artefakt bulunamadı"]

    for path in files:
        current_doc = json.loads(path.read_text(encoding="utf-8"))
        current = keypaths(current_doc)
        empties = empty_containers(current_doc)
        entry = recorded.get(path.name)
        if entry is None:
            # TABANSIZ ARTEFAKT HATA'dır, uyarı değil. "Henüz tabanı yok" ile
            # "tabanı silindi" ayırt edilemez, ve ikincisi kapıyı kapatmanın
            # en kolay yoludur.
            report.append(f"✗ {path.name:<30}TABANI YOK — `--update` ile "
                          "kaydet (kapı tabansız artefaktı geçirmez)")
            errors += 1
            continue

        baseline = set(entry.get("keys") or [])
        declared_empty = set(entry.get("declaredEmpty") or [])
        lost, emptied, excused = [], [], []
        for p_ in sorted(baseline - current):
            if declared(removals, p_):
                excused.append(p_)
                continue
            container = emptied_by(p_, empties)
            if container is not None:
                # Kapsayıcı DURUYOR ama boş. Şema kaybı değil, İÇERİK kaybı —
                # ve C-113'ün gerçek kipi bu. Artefakt+yola özgü beyanla
                # meşrulaşır; genel beyanla ASLA.
                (excused if container in declared_empty else emptied).append(p_)
            else:
                lost.append(p_)
        gained = sorted(current - baseline)

        if lost or emptied:
            errors += 1
            head = []
            if lost:
                head.append(f"{len(lost)} ALAN KAYBI")
            if emptied:
                head.append(f"{len(emptied)} BOŞALMA")
            report.append(f"✗ {path.name:<30}{' + '.join(head)}")
            for p_ in lost:
                report.append(f"      ✗ KAYIP  {p_}  (kapsayıcı dolu, alan yok)")
            for p_ in emptied:
                report.append(f"      ✗ BOŞALDI {p_}  "
                              f"(kapsayıcı `{emptied_by(p_, empties)}` boş)")
            if lost:
                report.append("      → alanı geri getir ya da tabanın "
                              "declaredRemovals'ına gerekçesiyle yaz.")
            if emptied:
                report.append("      → kayıt yok edildi mi, yoksa bu turda "
                              "gerçekten boş mu? İkincisi ise "
                              "artifacts[bu dosya].declaredEmpty'ye kapsayıcıyı "
                              "yaz — GENEL beyan kullanma, korunmak istenen "
                              "alanı kapatır.")
        else:
            extra = []
            if gained:
                extra.append(f"+{len(gained)} yeni")
            if excused:
                extra.append(f"{len(excused)} beyanlı")
            note = f"  ({', '.join(extra)})" if extra else ""
            report.append(f"✓ {path.name:<30}alan bütünlüğü korunuyor{note}")
        report += [f"      + {p_}" for p_ in gained]

    return errors, report


def update(directory: Path, *, today: str | None = None) -> tuple[int, list[str]]:
    """Tabanı tazele. KAYBI/BOŞALMAYI absorbe ETMEZ — kazancı eder.

    Bu asimetri kapının bel kemiği: taban güncellemesi, bir kaybın
    meşrulaştırıldığı yerdir. Kaybı sessizce yazmak, kapıyı her `--update`
    çağrısında kendi kendine kapatmak olur.
    """
    doc = load_baseline(directory)
    removals = doc.get("declaredRemovals") or {}
    recorded = doc.setdefault("artifacts", {})
    report: list[str] = []
    stamp = today or date.today().isoformat()

    files = artifact_files(directory)
    if not files:
        return 1, [f"✗ {directory}: artefakt bulunamadı"]

    blocked = 0
    for path in files:
        current_doc = json.loads(path.read_text(encoding="utf-8"))
        current = keypaths(current_doc)
        empties = empty_containers(current_doc)
        entry = recorded.get(path.name)
        baseline = set((entry or {}).get("keys") or [])
        declared_empty = set((entry or {}).get("declaredEmpty") or [])

        problems = []
        for p_ in sorted(baseline - current):
            if declared(removals, p_):
                continue
            container = emptied_by(p_, empties)
            if container is None:
                problems.append(("KAYIP", p_))
            elif container not in declared_empty:
                problems.append(("BOŞALDI", p_))

        if problems:
            blocked += 1
            report.append(f"✗ {path.name:<30}TAZELENMEDİ — {len(problems)} "
                          "beyansız kayıp/boşalma")
            report += [f"      ✗ {kind:<8}{p_}" for kind, p_ in problems]
            continue

        gained = sorted(current - baseline)
        kept = {"keys": sorted(current), "updatedAt": stamp}
        if declared_empty:
            kept["declaredEmpty"] = sorted(declared_empty)
        recorded[path.name] = kept
        mark = f"  (+{len(gained)} yeni)" if gained else ""
        verb = "kaydedildi" if entry is None else "tazelendi"
        report.append(f"✓ {path.name:<30}{verb}{mark}")
        report += [f"      + {p_}" for p_ in gained]

    if blocked:
        report.append(f"\n{blocked} artefakt TAZELENMEDİ: bir kaybı tabana "
                      "yazmak kapıyı kapatmaktır. Alanı geri getir, ya da "
                      "declaredRemovals (şema) / declaredEmpty (bu artefaktta "
                      "meşru boşluk) ile beyan et.")
        return 1, report

    save_baseline(directory, doc)
    report.append(f"\n{directory / BASELINE_NAME} yazıldı.")
    return 0, report


LIMIT_NOTE = (
    "NOT: bu kapı alanın VARLIĞINI ölçer, DEĞERİNİ ölçmez — ölçülmüş arıza kipi "
    "alan kaybıydı (3 vaka); değer-bozulması ölçülmedi, o yüzden kapı konmadı.\n"
    "Kardeş kip de dışarıda: 'yazılmış ama OKUNMAMIŞ alan' (Choreia R12) — "
    "varlık ölçülebilir, okunmuşluk ölçülemez."
)


def self_test() -> int:
    """Kapı ateşlenebiliyor mu? Ateşlenemeyen kapı süstür.

    Senaryolar iki yöne de bakar: ateşlenmesi GEREKEN durumlar (kayıp, boşalma,
    tabansızlık, --update'in kaybı yutması) ve ateşlenmemesi gereken durumlar
    (değer değişimi, dizi uzunluğu, beyanlı kaldırma). İkinci grup birincisi
    kadar önemli: gürültülü kapı kapatılır, kapatılan kapı yoktur.
    """
    import shutil
    import tempfile

    tmp = Path(tempfile.mkdtemp(prefix="keyset_selftest_"))
    fails: list[str] = []

    def write(doc: dict) -> None:
        (tmp / "a.json").write_text(json.dumps(doc), encoding="utf-8")

    FULL = {"step": "x",
            "sources": [{"videoId": "v1", "why": "r"}],
            "excluded": [{"videoId": "v2", "why": "gerekçe"}]}
    try:
        write(FULL)

        # 1) Tabansız artefakt GEÇMEMELİ: "henüz yok" ile "silindi" ayırt edilemez.
        if check(tmp)[0] == 0:
            fails.append("tabansız artefakt geçti")

        # 2) Taban yazılır → temiz geçer.
        if update(tmp, today="2026-01-01")[0] != 0:
            fails.append("ilk --update başarısız")
        if check(tmp)[0] != 0:
            fails.append("taze taban temiz geçmedi")

        # 3) DEĞER değişimi ateşlememeli — ölçülen şey ŞEMA.
        write({"step": "x",
               "sources": [{"videoId": "v9", "why": "bambaşka"}],
               "excluded": [{"videoId": "v8", "why": "başka"}]})
        if check(tmp)[0] != 0:
            fails.append("değer değişimi kapıyı ateşledi")

        # 4) Dizi UZUNLUĞU değişimi ateşlememeli (kapsayıcı boşalmadıkça).
        write({"step": "x",
               "sources": [{"videoId": "v1", "why": "r"},
                           {"videoId": "v2", "why": "r"},
                           {"videoId": "v3", "why": "r"}],
               "excluded": [{"videoId": "v2", "why": "g"}]})
        if check(tmp)[0] != 0:
            fails.append("dizi uzunluğu değişimi kapıyı ateşledi")

        # 5) BOŞALMA ateşlemeli ve KAYIP'tan AYRI raporlanmalı — C-113'ün
        #    gerçek kipi bu (`excludedNotLesson: []`).
        write({"step": "x",
               "sources": [{"videoId": "v1", "why": "r"}],
               "excluded": []})
        errors, rep = check(tmp)
        if errors == 0:
            fails.append("BOŞALMA yakalanmadı — C-113'ün gerçek kipi")
        if not any("BOŞALDI" in line and "excluded[].why" in line for line in rep):
            fails.append("boşalma, boşalma olarak isimlendirilmedi")
        if any("KAYIP" in line for line in rep):
            fails.append("boşalma KAYIP olarak sınıflandırıldı — ikisi ayrı "
                         "sınıf olmalı, yoksa genel beyan alanı kapatır")

        # 6) --update boşalmayı absorbe ETMEMELİ.
        if update(tmp, today="2026-01-02")[0] == 0:
            fails.append("--update beyansız boşalmayı absorbe etti")

        # 7) declaredEmpty ile meşrulaşmalı — ve YALNIZ o kapsayıcı için.
        doc = load_baseline(tmp)
        doc["artifacts"]["a.json"]["declaredEmpty"] = ["excluded[]"]
        save_baseline(tmp, doc)
        if check(tmp)[0] != 0:
            fails.append("declaredEmpty beyanı boşalmayı meşrulaştırmadı")

        # 8) declaredEmpty BAŞKA kapsayıcıyı korumamalı — beyanın dar olması
        #    tasarımın amacı; genişse korunmak istenen alanı kapatır.
        write({"step": "x", "sources": [], "excluded": []})
        errors, rep = check(tmp)
        if errors == 0:
            fails.append("declaredEmpty('excluded[]') sources[] boşalmasını da "
                         "geçirdi — beyan BLANKET davranıyor")

        # 9) GERÇEK ALAN KAYBI (kapsayıcı dolu, alan yok) KAYIP sınıfında.
        write({"step": "x", "sources": [{"videoId": "v1"}], "excluded": []})
        errors, rep = check(tmp)
        if not any("KAYIP" in line and "sources[].why" in line for line in rep):
            fails.append("dolu kapsayıcıdaki alan kaybı KAYIP olarak "
                         "raporlanmadı")

        # 10) Şema kaldırması BEYANLA geçmeli.
        doc = load_baseline(tmp)
        doc["declaredRemovals"]["why"] = {
            "why": "test: gerekçe alanı şemadan kaldırıldı",
            "declaredAt": "2026-01-02"}
        save_baseline(tmp, doc)
        errors, rep = check(tmp)
        if any("sources[].why" in line for line in rep):
            fails.append("beyan edilmiş şema kaldırması hâlâ raporlanıyor")

        # 11) Taban dosyası artefakt SANILMAMALI.
        if any(p_.name == BASELINE_NAME for p_ in artifact_files(tmp)):
            fails.append("taban dosyası artefakt listesine girdi")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    for f in fails:
        print(f"  ✗ {f}")
    print("✓ self-test geçti (11 senaryo)" if not fails
          else f"✗ {len(fails)} senaryo başarısız")
    return 1 if fails else 0


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("directory", nargs="?", help="artefakt dizini")
    ap.add_argument("--update", action="store_true",
                    help="tabanı tazele (kaybı absorbe ETMEZ)")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()

    if args.self_test:
        return self_test()
    if not args.directory:
        ap.error("artefakt dizini gerekli (ya da --self-test)")

    directory = Path(args.directory).resolve()
    if not directory.is_dir():
        print(f"✗ {directory}: dizin değil")
        return 1

    rc, report = update(directory) if args.update else check(directory)
    print("\n".join(report))
    if not args.update:
        total = len(artifact_files(directory))
        print(f"\n{total - rc}/{total} artefakt alan bütünlüğünü koruyor.")
        print(f"\n{LIMIT_NOTE}")
    return 1 if rc else 0


if __name__ == "__main__":
    sys.exit(main())
