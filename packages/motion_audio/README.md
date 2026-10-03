# motion_audio

Yula Motion ailesi için sinyal primitive'leri: pitch/onset/chord, latency
calibration ve bounded transient frame buffer. Müfredat veya çalım doğruluğu
hükmü vermez. Public API `motion_audio.dart` üzerinden korunur.

0.1.1: `PitchEstimate.midiNote` geçersiz/sayısal olarak temsil edilemeyen pitch
için null döndürür; NaN, infinity ve `double.minPositive` buna dahildir. Normal
pitch hesabı ve public constructor değişmedi. Bu kaynak düzeltmesi mikrofon
capture eklemez; Dart test kanıtı cihaz ses kabulü değildir.
