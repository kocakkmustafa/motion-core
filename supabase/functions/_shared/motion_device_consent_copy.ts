// Parental consent email for the under-13 device path (no account yet).
// Neutral wording: no account, teen or country statement, no new legal claim.
// English and Turkish only; other locales fall back to English until reviewed
// translations exist. Placeholders: {link}, {expiresAt}.

type Copy = { subject: string; text: string };

const deviceCopy: Record<string, Copy> = {
  en: {
    subject: "Approve your child's use of Motion",
    text:
      "Hello,\n\nA child entered your email address in a YULAlab app and asked for your approval to use Motion. Nothing is set up until you approve.\n\nWhat we keep: we do not store your email address in readable form, and we remove its fingerprint once you decide. If you approve, we keep a one-time approval tied to the child's device for up to 30 days, until the sign-up is finished. We do not collect the child's name, email address or birth date for this request.\n\nApprove or decline here (the link works until {expiresAt}):\n{link}\n\nIf you decline, the request is closed and nothing is created. If you did not expect this email, you can ignore it: an unanswered request is deleted after 30 days.\n\nYULAlab · support@yulalab.com",
  },
  tr: {
    subject: "Çocuğunun Motion kullanımını onayla",
    text:
      "Merhaba,\n\nBir çocuk, YULAlab uygulamasına e-posta adresini yazdı ve Motion'ı kullanması için senin onayını istedi. Sen onaylamadan hiçbir şey kurulmaz.\n\nSakladıklarımız: e-posta adresini okunabilir biçimde saklamayız; karar verdiğinde adresin parmak izini de sileriz. Onaylarsan, kayıt tamamlanana kadar en fazla 30 gün boyunca çocuğun cihazına bağlı tek kullanımlık bir onay tutarız. Bu istek için çocuğun adını, e-postasını ya da doğum tarihini toplamayız.\n\nBuradan onayla veya reddet (bağlantı {expiresAt} tarihine kadar geçerli):\n{link}\n\nReddedersen istek kapanır ve hiçbir şey oluşturulmaz. Bu e-postayı beklemiyorsan yok sayabilirsin: yanıtlanmayan istek 30 gün sonra silinir.\n\nYULAlab · support@yulalab.com",
  },
};

export const deviceConsentLocales = Object.keys(deviceCopy);

export function deviceConsentEmail(
  locale: string,
  values: { link: string; expiresAt: string },
): Copy {
  const language = locale.split("-")[0].toLowerCase();
  const chosen = deviceCopy[locale] ?? deviceCopy[language] ?? deviceCopy.en;
  // Replace each placeholder once; inserted values are never re-expanded.
  const fill = (text: string) =>
    text.replace(
      /\{(link|expiresAt)\}/g,
      (_, name: "link" | "expiresAt") => values[name],
    );
  return { subject: chosen.subject, text: fill(chosen.text) };
}
