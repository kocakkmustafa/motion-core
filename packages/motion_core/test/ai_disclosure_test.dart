import 'package:motion_core/motion_core.dart';
import 'package:test/test.dart';

void main() {
  group('AiAssetDisclosure (Art.50)', () {
    test('T1 avatar is not AI-generated and needs no machine mark', () {
      const AiAssetDisclosure d =
          AiAssetDisclosure(tier: TeachingAssetTier.t1SkeletonAvatar);
      expect(d.aiGenerated, isFalse);
      expect(d.requiresMachineReadableMark, isFalse);
      expect(d.disclosureText, contains('virtual character'));
    });

    test('generative tiers demand the machine-readable mark', () {
      for (final TeachingAssetTier tier in <TeachingAssetTier>[
        TeachingAssetTier.t2PoseDrivenGenerative,
        TeachingAssetTier.t3StockGenerative,
        TeachingAssetTier.aiVoice,
      ]) {
        final AiAssetDisclosure d = AiAssetDisclosure(tier: tier);
        expect(d.requiresMachineReadableMark, isTrue, reason: tier.name);
        expect(d.disclosureText, contains('AI'), reason: tier.name);
      }
    });

    test('round-trips through JSON for content packages', () {
      const AiAssetDisclosure d = AiAssetDisclosure(
        tier: TeachingAssetTier.t2PoseDrivenGenerative,
        generator: 'champ@a1b2',
      );
      final AiAssetDisclosure back = AiAssetDisclosure.fromJson(d.toJson());
      expect(back.tier, d.tier);
      expect(back.generator, 'champ@a1b2');
    });
  });
}
