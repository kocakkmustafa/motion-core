/// Country-based age rules for the shared Motion account (13+ product).
///
/// Engineering defaults for the first release, NOT legal advice. Every value
/// below needs counsel review before a store submission; [MotionAgePolicy.version]
/// is stored with each declaration so a later table change can be re-applied.
///
/// - Nobody under [MotionAgePolicy.minimumAge] (13) gets a Motion account in
///   any country (US COPPA and the product's 13+ audience decision).
/// - Below a country's digital-consent age a verified parent/guardian must
///   approve the account before account features open.
/// - Every user under [MotionAgePolicy.adultAge] (18) is a teen: no marketing,
///   no personalised advertising, analytics only with explicit opt-in.
library;

/// The result of one neutral age screen.
enum MotionAgeBand {
  /// Under 13: no account and no account data collection.
  blocked,

  /// 13+ but under the country's consent age: parent/guardian approval first.
  parentalConsentRequired,

  /// Under 18 and at/above the consent age.
  teen,

  /// 18 or older.
  adult,
}

/// Digital-consent age for one country. [note] records the basis reviewed.
class MotionAgeRule {
  const MotionAgeRule(this.consentAge, this.note);

  final int consentAge;
  final String note;
}

/// One declaration. Only birth year+month are kept: the day is never asked.
class MotionAgeDeclaration {
  const MotionAgeDeclaration({
    required this.birthYear,
    required this.birthMonth,
    required this.countryCode,
    required this.policyVersion,
  });

  final int birthYear;
  final int birthMonth;

  /// ISO 3166-1 alpha-2 (upper case), or null when the region is unknown.
  final String? countryCode;
  final String policyVersion;

  /// `YYYY-MM`, the only birth data that leaves the device.
  String get birthYearMonth =>
      '${birthYear.toString().padLeft(4, '0')}-'
      '${birthMonth.toString().padLeft(2, '0')}';

  Map<String, Object?> toJson() => {
    'birth_year_month': birthYearMonth,
    'country': countryCode,
    'policy_version': policyVersion,
  };

  static MotionAgeDeclaration? fromJson(Object? json) {
    if (json is! Map) return null;
    final ym = json['birth_year_month'];
    final country = json['country'];
    final version = json['policy_version'];
    if (ym is! String || version is! String) return null;
    final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(ym);
    if (match == null) return null;
    final month = int.parse(match.group(2)!);
    if (month < 1 || month > 12) return null;
    if (country != null &&
        (country is! String || !RegExp(r'^[A-Z]{2}$').hasMatch(country))) {
      return null;
    }
    return MotionAgeDeclaration(
      birthYear: int.parse(match.group(1)!),
      birthMonth: month,
      countryCode: country as String?,
      policyVersion: version,
    );
  }
}

class MotionAgePolicy {
  const MotionAgePolicy._();

  static const version = '2026-10-21.1';
  static const minimumAge = 13;
  static const adultAge = 18;

  /// Unknown or unlisted region: the strictest GDPR Art. 8 value.
  static const defaultRule = MotionAgeRule(
    16,
    'Unknown/unlisted region: strictest GDPR Art. 8 age as a safe default',
  );

  /// Reviewed entries. EU/EEA values follow each member state's GDPR Art. 8
  /// choice; others note their basis. Anything absent uses [defaultRule].
  static const rules = <String, MotionAgeRule>{
    // EU member states (GDPR Art. 8 national ages).
    'AT': MotionAgeRule(14, 'GDPR Art. 8 / AT DSG'),
    'BE': MotionAgeRule(13, 'GDPR Art. 8 / BE'),
    'BG': MotionAgeRule(14, 'GDPR Art. 8 / BG'),
    'HR': MotionAgeRule(16, 'GDPR Art. 8 / HR'),
    'CY': MotionAgeRule(14, 'GDPR Art. 8 / CY'),
    'CZ': MotionAgeRule(15, 'GDPR Art. 8 / CZ'),
    'DK': MotionAgeRule(13, 'GDPR Art. 8 / DK'),
    'EE': MotionAgeRule(13, 'GDPR Art. 8 / EE'),
    'FI': MotionAgeRule(13, 'GDPR Art. 8 / FI'),
    'FR': MotionAgeRule(15, 'GDPR Art. 8 / FR'),
    'DE': MotionAgeRule(16, 'GDPR Art. 8 default / DE'),
    'GR': MotionAgeRule(15, 'GDPR Art. 8 / GR'),
    'HU': MotionAgeRule(16, 'GDPR Art. 8 / HU'),
    'IE': MotionAgeRule(16, 'GDPR Art. 8 / IE'),
    'IT': MotionAgeRule(14, 'GDPR Art. 8 / IT'),
    'LV': MotionAgeRule(13, 'GDPR Art. 8 / LV'),
    'LT': MotionAgeRule(14, 'GDPR Art. 8 / LT'),
    'LU': MotionAgeRule(16, 'GDPR Art. 8 / LU'),
    'MT': MotionAgeRule(13, 'GDPR Art. 8 / MT'),
    'NL': MotionAgeRule(16, 'GDPR Art. 8 / NL'),
    'PL': MotionAgeRule(16, 'GDPR Art. 8 / PL'),
    'PT': MotionAgeRule(13, 'GDPR Art. 8 / PT'),
    'RO': MotionAgeRule(16, 'GDPR Art. 8 / RO'),
    'SK': MotionAgeRule(16, 'GDPR Art. 8 / SK'),
    'SI': MotionAgeRule(15, 'GDPR Art. 8 / SI'),
    'ES': MotionAgeRule(14, 'GDPR Art. 8 / ES LOPDGDD'),
    'SE': MotionAgeRule(13, 'GDPR Art. 8 / SE'),
    // EEA / Europe.
    'IS': MotionAgeRule(13, 'GDPR Art. 8 / IS'),
    'LI': MotionAgeRule(16, 'GDPR Art. 8 / LI'),
    'NO': MotionAgeRule(13, 'GDPR Art. 8 / NO'),
    'GB': MotionAgeRule(13, 'UK GDPR / DPA 2018'),
    'CH': MotionAgeRule(16, 'No fixed FADP age: conservative default'),
    // Americas.
    'US': MotionAgeRule(13, 'COPPA: under 13 excluded by minimumAge'),
    'CA': MotionAgeRule(14, 'Quebec Law 25 (14) applied nationally'),
    'BR': MotionAgeRule(16, 'LGPD Art. 14 + ECA Digital: guardian link <16'),
    'MX': MotionAgeRule(18, 'LFPDPPP: minors via legal representative'),
    'AR': MotionAgeRule(16, 'No fixed age: conservative default'),
    // Asia-Pacific / Middle East.
    'KR': MotionAgeRule(14, 'PIPA Art. 22-2: guardian consent under 14'),
    'CN': MotionAgeRule(14, 'PIPL Art. 31: guardian consent under 14'),
    'JP': MotionAgeRule(16, 'APPI guidance: guardian consent ~12-15'),
    'IN': MotionAgeRule(18, 'DPDP Act 2023 s.9: verifiable consent <18'),
    'ID': MotionAgeRule(18, 'PDP Law Art. 25: parental consent for children'),
    'SA': MotionAgeRule(18, 'PDPL: guardian for persons lacking capacity'),
    'AE': MotionAgeRule(18, 'No fixed age: guardian below majority'),
    'TR': MotionAgeRule(18, 'KVKK + TMK: guardian consent below majority'),
    'AU': MotionAgeRule(16, 'Children\'s Online Privacy Code pending'),
  };

  static MotionAgeRule ruleFor(String? countryCode) =>
      rules[countryCode?.toUpperCase()] ?? defaultRule;

  /// Age in whole years with only a birth month. The birthday is treated as
  /// not yet reached during the birth month, so age is never overstated.
  static int ageOn(int birthYear, int birthMonth, DateTime today) {
    var age = today.year - birthYear;
    if (today.month <= birthMonth) age--;
    return age;
  }

  static MotionAgeBand bandFor(
    MotionAgeDeclaration declaration, {
    required DateTime today,
  }) {
    final age = ageOn(declaration.birthYear, declaration.birthMonth, today);
    if (age < minimumAge) return MotionAgeBand.blocked;
    if (age < ruleFor(declaration.countryCode).consentAge) {
      return MotionAgeBand.parentalConsentRequired;
    }
    if (age < adultAge) return MotionAgeBand.teen;
    return MotionAgeBand.adult;
  }

  /// Teens never receive marketing or personalised ads.
  static bool marketingAllowed(MotionAgeBand band) =>
      band == MotionAgeBand.adult;

  /// Teen product analytics needs an explicit opt-in (never on by default).
  static bool analyticsNeedsOptIn(MotionAgeBand band) =>
      band != MotionAgeBand.adult;
}
