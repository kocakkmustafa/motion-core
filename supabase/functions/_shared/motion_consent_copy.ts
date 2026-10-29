// Fourteen-locale parental consent email. Placeholders: {link}, {expiresAt}.
// Unsupported locales fall back to English, like the app catalog.

type Copy = { subject: string; text: string };

const copy: Record<string, Copy> = {
  en: {
    subject: "Approve your teen's Motion account",
    text:
      "Hello,\n\nYour teen asked to create a Motion account and named you as their parent or guardian. One Motion account is shared by five YULAlab apps (Ostinato, Choreia, JabLab, Gravita and Lissom). Because of their age and country, we need your approval before account features open.\n\nWhat we keep: their email address, the birth month and year they entered, their country and the display name they choose. Practice history stays on their device. We send teens no marketing and show them no personalised ads.\n\nApprove or decline here (the link works until {expiresAt}):\n{link}\n\nIf you decline, the account is deleted. If you did not expect this email, you can ignore it: an unapproved account is deleted after 30 days.\n\nThe teen may have bought a subscription through the store's family controls (e.g. Ask to Buy, Google Play parental approval). Deleting the account does not cancel it; you can manage it in the Apple or Google account. Details: https://yulalab.com/privacy/motion\n\nYULAlab · support@yulalab.com",
  },
  tr: {
    subject: "Çocuğunun Motion hesabını onayla",
    text:
      "Merhaba,\n\nÇocuğun bir Motion hesabı açmak istedi ve seni ebeveyni ya da vasisi olarak belirtti. Tek bir Motion hesabı beş YULAlab uygulamasında (Ostinato, Choreia, JabLab, Gravita ve Lissom) ortak kullanılır. Yaşı ve ülkesi nedeniyle hesap özellikleri açılmadan önce senin onayın gerekiyor.\n\nSakladıklarımız: e-posta adresi, girdiği doğum ayı ve yılı, ülkesi ve seçtiği görünen ad. Pratik geçmişi cihazında kalır. Gençlere pazarlama iletisi göndermeyiz ve kişiselleştirilmiş reklam göstermeyiz.\n\nBuradan onayla veya reddet (bağlantı {expiresAt} tarihine kadar geçerli):\n{link}\n\nReddedersen hesap silinir. Bu e-postayı beklemiyorsan yok sayabilirsin: onaylanmayan hesap 30 gün sonra silinir.\n\nGenç, mağazanın aile denetimleriyle (ör. Satın Almak İçin Sor, Google Play ebeveyn onayı) abonelik almış olabilir. Hesabın silinmesi bu aboneliği iptal etmez; aboneliği Apple veya Google hesabından yönetebilirsiniz. Ayrıntılar: https://yulalab.com/privacy/motion\n\nYULAlab · support@yulalab.com",
  },
  "es-419": {
    subject: "Aprueba la cuenta de Motion de tu hijo o hija",
    text:
      "Hola:\n\nTu hijo o hija pidió crear una cuenta de Motion y te indicó como su madre, padre o tutor. Una sola cuenta de Motion se comparte en cinco apps de YULAlab (Ostinato, Choreia, JabLab, Gravita y Lissom). Por su edad y país, necesitamos tu aprobación antes de activar las funciones de la cuenta.\n\nLo que guardamos: su correo electrónico, el mes y año de nacimiento que ingresó, su país y el nombre visible que elija. El historial de práctica se queda en su dispositivo. No enviamos marketing a adolescentes ni les mostramos anuncios personalizados.\n\nAprueba o rechaza aquí (el enlace funciona hasta el {expiresAt}):\n{link}\n\nSi rechazas, la cuenta se elimina. Si no esperabas este correo, puedes ignorarlo: una cuenta sin aprobar se elimina después de 30 días.\n\nEs posible que tu hijo o hija haya comprado una suscripción con los controles familiares de la tienda (por ejemplo, Ask to Buy de Apple o la aprobación parental de Google Play). Eliminar la cuenta no la cancela; puedes administrarla en la cuenta de Apple o Google. Detalles: https://yulalab.com/privacy/motion\n\nYULAlab · support@yulalab.com",
  },
  "pt-BR": {
    subject: "Aprove a conta Motion do seu filho ou filha",
    text:
      "Olá,\n\nSeu filho ou filha pediu para criar uma conta Motion e indicou você como responsável. Uma única conta Motion é compartilhada por cinco apps da YULAlab (Ostinato, Choreia, JabLab, Gravita e Lissom). Por causa da idade e do país, precisamos da sua aprovação antes de liberar os recursos da conta.\n\nO que guardamos: o e-mail, o mês e o ano de nascimento informados, o país e o nome de exibição escolhido. O histórico de prática fica no dispositivo. Não enviamos marketing para adolescentes nem mostramos anúncios personalizados.\n\nAprove ou recuse aqui (o link vale até {expiresAt}):\n{link}\n\nSe você recusar, a conta será excluída. Se não esperava este e-mail, pode ignorá-lo: uma conta não aprovada é excluída após 30 dias.\n\nSeu filho ou filha pode ter comprado uma assinatura pelos controles familiares da loja (por exemplo, Pedir para Comprar da Apple ou a aprovação parental do Google Play). Excluir a conta não cancela a assinatura; você pode gerenciá-la na conta Apple ou Google. Detalhes: https://yulalab.com/privacy/motion\n\nYULAlab · support@yulalab.com",
  },
  de: {
    subject: "Bitte bestätige das Motion-Konto deines Kindes",
    text:
      "Hallo,\n\ndein Kind möchte ein Motion-Konto erstellen und hat dich als Elternteil oder Erziehungsberechtigte Person angegeben. Ein Motion-Konto wird in fünf YULAlab-Apps (Ostinato, Choreia, JabLab, Gravita und Lissom) gemeinsam genutzt. Wegen des Alters und des Landes brauchen wir deine Zustimmung, bevor die Kontofunktionen freigeschaltet werden.\n\nWas wir speichern: die E-Mail-Adresse, den angegebenen Geburtsmonat und das Geburtsjahr, das Land und den gewählten Anzeigenamen. Der Übungsverlauf bleibt auf dem Gerät. Jugendlichen senden wir keine Werbung und zeigen keine personalisierten Anzeigen.\n\nHier zustimmen oder ablehnen (der Link gilt bis {expiresAt}):\n{link}\n\nWenn du ablehnst, wird das Konto gelöscht. Wenn du diese E-Mail nicht erwartet hast, kannst du sie ignorieren: Ein nicht bestätigtes Konto wird nach 30 Tagen gelöscht.\n\nDein Kind hat möglicherweise über die Familienfunktionen des Stores ein Abo abgeschlossen (z. B. Kaufanfrage bei Apple oder Elterngenehmigung bei Google Play). Das Löschen des Kontos kündigt das Abo nicht; du kannst es im Apple- oder Google-Konto verwalten. Details: https://yulalab.com/privacy/motion\n\nYULAlab · support@yulalab.com",
  },
  fr: {
    subject: "Approuve le compte Motion de ton enfant",
    text:
      "Bonjour,\n\nTon enfant souhaite créer un compte Motion et t’a indiqué comme parent ou tuteur. Un seul compte Motion est partagé par cinq apps YULAlab (Ostinato, Choreia, JabLab, Gravita et Lissom). En raison de son âge et de son pays, ton accord est nécessaire avant d’ouvrir les fonctions du compte.\n\nCe que nous conservons : son adresse e-mail, le mois et l’année de naissance indiqués, son pays et le nom affiché choisi. L’historique d’entraînement reste sur son appareil. Nous n’envoyons aucun marketing aux adolescents et ne leur montrons aucune publicité personnalisée.\n\nApprouve ou refuse ici (lien valable jusqu’au {expiresAt}) :\n{link}\n\nSi tu refuses, le compte est supprimé. Si tu n’attendais pas cet e-mail, tu peux l’ignorer : un compte non approuvé est supprimé après 30 jours.\n\nTon enfant a peut-être souscrit un abonnement via le contrôle parental du store (par ex. Ask to Buy d’Apple ou l’approbation parentale de Google Play). La suppression du compte ne l’annule pas ; tu peux le gérer dans le compte Apple ou Google. Détails : https://yulalab.com/privacy/motion\n\nYULAlab · support@yulalab.com",
  },
  ja: {
    subject: "お子さまのMotionアカウントの承認のお願い",
    text:
      "こんにちは。\n\nお子さまがMotionアカウントの作成を希望し、保護者としてあなたを指定しました。Motionアカウントは5つのYULAlabアプリ（Ostinato、Choreia、JabLab、Gravita、Lissom）で共通して使われます。年齢と国の規定により、アカウント機能を有効にする前に保護者の承認が必要です。\n\n保存する情報：メールアドレス、入力された生年月、国、選んだ表示名。練習履歴は端末内に保存されます。10代の利用者にはマーケティングを送らず、パーソナライズ広告も表示しません。\n\nこちらから承認または拒否してください（リンクの有効期限：{expiresAt}）：\n{link}\n\n拒否した場合、アカウントは削除されます。心当たりがない場合はこのメールを無視してください。承認されないアカウントは30日後に削除されます。\n\nお子さまがストアのファミリー機能（例：Appleの「承認と購入のリクエスト」、Google Playの保護者による承認）でサブスクリプションを購入している場合があります。アカウントを削除してもサブスクリプションは解約されません。AppleまたはGoogleのアカウントで管理できます。詳細：https://yulalab.com/privacy/motion\n\nYULAlab · support@yulalab.com",
  },
  ar: {
    subject: "وافِق على حساب Motion لابنك أو ابنتك",
    text:
      "مرحبًا،\n\nطلب ابنك أو ابنتك إنشاء حساب Motion وذكرك بصفتك وليّ الأمر أو الوصي. يُستخدم حساب Motion واحد في خمسة تطبيقات من YULAlab (Ostinato وChoreia وJabLab وGravita وLissom). بسبب العمر والبلد، نحتاج إلى موافقتك قبل تفعيل ميزات الحساب.\n\nما نحتفظ به: عنوان البريد الإلكتروني، وشهر وسنة الميلاد المُدخلين، والبلد، واسم العرض المختار. يبقى سجل التمرين على الجهاز. لا نرسل أي تسويق للمراهقين ولا نعرض لهم إعلانات مخصّصة.\n\nوافِق أو ارفض من هنا (الرابط صالح حتى {expiresAt}):\n{link}\n\nإذا رفضت، يُحذف الحساب. إذا لم تكن تتوقع هذه الرسالة، يمكنك تجاهلها: يُحذف الحساب غير المُوافَق عليه بعد 30 يومًا.\n\nربما اشترى ابنك أو ابنتك اشتراكًا عبر أدوات الرقابة العائلية في المتجر (مثل Ask to Buy من Apple أو موافقة الوالدين في Google Play). حذف الحساب لا يلغي الاشتراك؛ يمكنك إدارته من حساب Apple أو Google. التفاصيل: https://yulalab.com/privacy/motion\n\nYULAlab · support@yulalab.com",
  },
  it: {
    subject: "Approva l'account Motion di tuo figlio o tua figlia",
    text:
      "Ciao,\n\ntuo figlio o tua figlia ha chiesto di creare un account Motion e ti ha indicato come genitore o tutore. Un solo account Motion è condiviso da cinque app YULAlab (Ostinato, Choreia, JabLab, Gravita e Lissom). In base all'età e al paese, serve la tua approvazione prima di attivare le funzioni dell'account.\n\nCosa conserviamo: l'indirizzo email, il mese e l'anno di nascita inseriti, il paese e il nome visualizzato scelto. La cronologia degli esercizi resta sul dispositivo. Non inviamo marketing agli adolescenti e non mostriamo loro pubblicità personalizzata.\n\nApprova o rifiuta qui (il link è valido fino al {expiresAt}):\n{link}\n\nSe rifiuti, l'account viene eliminato. Se non aspettavi questa email, puoi ignorarla: un account non approvato viene eliminato dopo 30 giorni.\n\nTuo figlio o tua figlia potrebbe aver acquistato un abbonamento tramite i controlli familiari dello store (ad es. Chiedi di acquistare di Apple o l'approvazione dei genitori di Google Play). L'eliminazione dell'account non lo annulla; puoi gestirlo nell'account Apple o Google. Dettagli: https://yulalab.com/privacy/motion\n\nYULAlab · support@yulalab.com",
  },
  ko: {
    subject: "자녀의 Motion 계정을 승인해 주세요",
    text:
      "안녕하세요.\n\n자녀가 Motion 계정을 만들고자 하며 보호자로 귀하를 지정했습니다. 하나의 Motion 계정은 YULAlab 앱 다섯 개(Ostinato, Choreia, JabLab, Gravita, Lissom)에서 함께 사용됩니다. 자녀의 나이와 국가 기준에 따라 계정 기능을 열기 전에 보호자의 승인이 필요합니다.\n\n보관하는 정보: 이메일 주소, 입력한 출생 연월, 국가, 선택한 표시 이름. 연습 기록은 기기에 남습니다. 청소년에게는 마케팅을 보내지 않으며 맞춤형 광고도 표시하지 않습니다.\n\n여기에서 승인하거나 거절하세요(링크 유효 기한: {expiresAt}):\n{link}\n\n거절하면 계정이 삭제됩니다. 예상하지 못한 메일이라면 무시하셔도 됩니다. 승인되지 않은 계정은 30일 후 삭제됩니다.\n\n자녀가 스토어의 가족 관리 기능(예: Apple의 구입 요청, Google Play 보호자 승인)으로 구독을 구매했을 수 있습니다. 계정을 삭제해도 구독은 취소되지 않으며, Apple 또는 Google 계정에서 관리할 수 있습니다. 자세한 내용: https://yulalab.com/privacy/motion\n\nYULAlab · support@yulalab.com",
  },
  id: {
    subject: "Setujui akun Motion anak Anda",
    text:
      "Halo,\n\nAnak Anda ingin membuat akun Motion dan mencantumkan Anda sebagai orang tua atau wali. Satu akun Motion digunakan bersama di lima aplikasi YULAlab (Ostinato, Choreia, JabLab, Gravita, dan Lissom). Karena usia dan negaranya, kami memerlukan persetujuan Anda sebelum fitur akun dibuka.\n\nYang kami simpan: alamat email, bulan dan tahun lahir yang dimasukkan, negara, dan nama tampilan yang dipilih. Riwayat latihan tetap di perangkatnya. Kami tidak mengirim pemasaran kepada remaja dan tidak menampilkan iklan yang dipersonalisasi.\n\nSetujui atau tolak di sini (tautan berlaku hingga {expiresAt}):\n{link}\n\nJika Anda menolak, akun akan dihapus. Jika Anda tidak mengharapkan email ini, abaikan saja: akun yang tidak disetujui dihapus setelah 30 hari.\n\nAnak Anda mungkin telah membeli langganan melalui kontrol keluarga di toko aplikasi (mis. Ask to Buy dari Apple atau persetujuan orang tua di Google Play). Menghapus akun tidak membatalkan langganan tersebut; Anda dapat mengelolanya di akun Apple atau Google. Detail: https://yulalab.com/privacy/motion\n\nYULAlab · support@yulalab.com",
  },
  pl: {
    subject: "Zatwierdź konto Motion swojego dziecka",
    text:
      "Dzień dobry,\n\nTwoje dziecko chce założyć konto Motion i wskazało Cię jako rodzica lub opiekuna. Jedno konto Motion jest wspólne dla pięciu aplikacji YULAlab (Ostinato, Choreia, JabLab, Gravita i Lissom). Ze względu na wiek i kraj potrzebujemy Twojej zgody, zanim funkcje konta zostaną odblokowane.\n\nCo przechowujemy: adres e-mail, podany miesiąc i rok urodzenia, kraj oraz wybraną nazwę wyświetlaną. Historia ćwiczeń zostaje na urządzeniu. Nie wysyłamy nastolatkom treści marketingowych i nie wyświetlamy im spersonalizowanych reklam.\n\nZatwierdź lub odrzuć tutaj (link jest ważny do {expiresAt}):\n{link}\n\nJeśli odrzucisz, konto zostanie usunięte. Jeśli nie spodziewasz się tej wiadomości, możesz ją zignorować: niezatwierdzone konto zostanie usunięte po 30 dniach.\n\nTwoje dziecko mogło kupić subskrypcję za pomocą kontroli rodzicielskiej w sklepie (np. Ask to Buy w Apple lub zgody rodzica w Google Play). Usunięcie konta jej nie anuluje; możesz nią zarządzać na koncie Apple lub Google. Szczegóły: https://yulalab.com/privacy/motion\n\nYULAlab · support@yulalab.com",
  },
  hi: {
    subject: "अपने किशोर के Motion खाते को स्वीकृति दें",
    text:
      "नमस्ते,\n\nआपके किशोर ने Motion खाता बनाने का अनुरोध किया है और आपको अपने माता-पिता या अभिभावक के रूप में बताया है। एक Motion खाता YULAlab के पाँच ऐप (Ostinato, Choreia, JabLab, Gravita और Lissom) में साझा रूप से इस्तेमाल होता है। उनकी उम्र और देश के कारण खाते की सुविधाएँ खोलने से पहले आपकी स्वीकृति ज़रूरी है।\n\nहम क्या रखते हैं: ईमेल पता, दर्ज किया गया जन्म का महीना और वर्ष, देश और चुना गया प्रदर्शन नाम। अभ्यास का इतिहास उनके डिवाइस पर ही रहता है। हम किशोरों को कोई मार्केटिंग नहीं भेजते और उन्हें निजीकृत विज्ञापन नहीं दिखाते।\n\nयहाँ स्वीकृति दें या अस्वीकार करें (लिंक {expiresAt} तक मान्य है):\n{link}\n\nअस्वीकार करने पर खाता मिटा दिया जाएगा। अगर आपको इस ईमेल की उम्मीद नहीं थी, तो इसे अनदेखा करें: बिना स्वीकृति वाला खाता 30 दिन बाद मिटा दिया जाता है।\n\nहो सकता है आपके किशोर ने स्टोर के फ़ैमिली कंट्रोल (जैसे Apple का Ask to Buy या Google Play की माता-पिता की स्वीकृति) से सदस्यता खरीदी हो। खाता मिटाने से वह सदस्यता रद्द नहीं होती; आप उसे Apple या Google खाते में प्रबंधित कर सकते हैं। विवरण: https://yulalab.com/privacy/motion\n\nYULAlab · support@yulalab.com",
  },
  "zh-Hans": {
    subject: "请批准你孩子的 Motion 账户",
    text:
      "你好：\n\n你的孩子申请创建 Motion 账户，并将你填写为家长或监护人。一个 Motion 账户由 YULAlab 的五个应用（Ostinato、Choreia、JabLab、Gravita 和 Lissom）共用。根据孩子的年龄和所在国家，在开放账户功能前需要你的同意。\n\n我们保存的信息：电子邮件地址、填写的出生年月、国家以及选择的显示名称。练习记录保存在孩子的设备上。我们不向青少年发送营销信息，也不展示个性化广告。\n\n请在此批准或拒绝（链接有效期至 {expiresAt}）：\n{link}\n\n如果你拒绝，该账户将被删除。如果你没有预期收到此邮件，可以忽略：未获批准的账户将在 30 天后删除。\n\n你的孩子可能已通过商店的家庭控制功能（例如 Apple 的“购买前询问”或 Google Play 家长批准）购买了订阅。删除账户不会取消该订阅；你可以在 Apple 或 Google 账户中管理。详情：https://yulalab.com/privacy/motion\n\nYULAlab · support@yulalab.com",
  },
};

export const consentLocales = Object.keys(copy);

export function consentEmail(
  locale: string,
  values: { link: string; expiresAt: string },
): Copy {
  const language = locale.split("-")[0].toLowerCase();
  const key = copy[locale]
    ? locale
    : language === "es"
    ? "es-419"
    : language === "pt"
    ? "pt-BR"
    : language === "zh"
    ? "zh-Hans"
    : copy[language]
    ? language
    : "en";
  const chosen = copy[key];
  // Replace each placeholder once; inserted values are never re-expanded.
  const fill = (text: string) =>
    text.replace(
      /\{(link|expiresAt)\}/g,
      (_, name: "link" | "expiresAt") => values[name],
    );
  return { subject: chosen.subject, text: fill(chosen.text) };
}
