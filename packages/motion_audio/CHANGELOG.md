## 0.1.1 — 2026-10-02

`PitchEstimate.midiNote` NaN, sonsuz ve oran hesabı underflow yapan pozitif
subnormal frekanslarda artık null döndürür. Giriş ve hesap finite kontrolünden
sonra yuvarlanır; normal frekans API'si aynı kalır. Üç gerçek runtime RED
regresyonu düzeltmeden sonra GREEN; mikrofon/cihaz/provider kabulü değildir.
