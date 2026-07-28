/// EU AI Act Art.50 disclosure metadata for teaching assets (catalog §6.4).
///
/// Every teaching visual and coach-voice asset in a content package carries
/// one of these. The UI reads it to show the human-visible disclosure; the
/// asset pipeline's CI gate (`tools/art50/mark_asset.py scan`) reads the
/// package manifest to enforce the machine-readable mark. In force from
/// 2 August 2026 — this ships before the products do, not after.
library;

/// Production tier of a teaching asset (catalog §6.4 layered strategy).
enum TeachingAssetTier {
  /// Skeleton-driven in-app coach avatar: a deterministic render of the
  /// instructor-consensus reference. No generative model in the loop, so no
  /// Art.50 marking duty — but the family still labels it a virtual coach.
  t1SkeletonAvatar,

  /// Pose-driven generative video (pilot-gated; e.g. Champ). AI-generated:
  /// full disclosure + machine-readable mark.
  t2PoseDrivenGenerative,

  /// Paid-API visuals for non-form-critical surfaces (intros, ambience).
  t3StockGenerative,

  /// AI-produced coach voice (voice-pack TTS).
  aiVoice;

  bool get isAiGenerated => this != t1SkeletonAvatar;
}

/// Disclosure block embedded in content-package asset entries.
final class AiAssetDisclosure {
  const AiAssetDisclosure({
    required this.tier,
    this.generator,
  });

  final TeachingAssetTier tier;

  /// Model/service identifier that produced the asset (null for T1).
  final String? generator;

  bool get aiGenerated => tier.isAiGenerated;

  /// Whether Art.50(2) machine-readable marking is mandatory for this asset.
  bool get requiresMachineReadableMark => tier.isAiGenerated;

  /// Standard English user-facing copy (product language is English).
  String get disclosureText => switch (tier) {
        TeachingAssetTier.t1SkeletonAvatar =>
          'Your coach is a virtual character. Movements are rendered from '
              'real instructor references.',
        TeachingAssetTier.t2PoseDrivenGenerative ||
        TeachingAssetTier.t3StockGenerative =>
          'This demonstration video was generated with AI.',
        TeachingAssetTier.aiVoice => 'Coach voice is AI-generated.',
      };

  Map<String, dynamic> toJson() => <String, dynamic>{
        'tier': tier.name,
        'aiGenerated': aiGenerated,
        if (generator != null) 'generator': generator,
      };

  static AiAssetDisclosure fromJson(Map<String, dynamic> json) =>
      AiAssetDisclosure(
        tier: TeachingAssetTier.values.firstWhere(
          (TeachingAssetTier t) => t.name == json['tier'],
          orElse: () => TeachingAssetTier.t2PoseDrivenGenerative,
        ),
        generator: json['generator'] as String?,
      );
}
