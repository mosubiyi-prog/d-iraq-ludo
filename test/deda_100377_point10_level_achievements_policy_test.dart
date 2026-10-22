import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_100377_level_achievement_badges_policy.dart';

void main() {
  final badges = DedaLevelBadgeTier.values;

  Map<DedaLevelBadgeTier, int> approvedTestFixture() => {
        DedaLevelBadgeTier.silver: 2,
        DedaLevelBadgeTier.gold: 4,
        DedaLevelBadgeTier.emerald: 6,
        DedaLevelBadgeTier.diamond: 8,
        DedaLevelBadgeTier.royal: 10,
        DedaLevelBadgeTier.legendary: 12,
      };

  test('exact six LEVEL identities and NO existing purchased decoration IDs', () {
    expect(badges.length, 6);
    expect(badges.map((t) => t.arabicName).toList(),
        ['فضية', 'ذهبية', 'زمردية', 'ماسية', 'ملكية', 'أسطورية']);
    expect(badges.map((t) => t.id).toSet().length, 6);
    for (final tier in badges) {
      expect(tier.id.startsWith('level_'), isTrue);
      expect({
        'badge_member', 'badge_spark', 'badge_elite',
        'badge_royal', 'badge_season1', 'badge_legendary',
      }.contains(tier.id), isFalse);
    }
    expect(DedaLevelBadgePolicy.releaseEnabled, isFalse);
  });

  test('missing/unapproved/forged threshold maps never unlock anything', () {
    expect(DedaLevelBadgeThresholds.validate(null), isNull);
    expect(DedaLevelBadgeThresholds.validate({}), isNull);
    final invalid = approvedTestFixture()..remove(DedaLevelBadgeTier.royal);
    expect(DedaLevelBadgeThresholds.validate(invalid), isNull);
    final sameThreshold = approvedTestFixture()
      ..[DedaLevelBadgeTier.gold] = 2;
    expect(DedaLevelBadgeThresholds.validate(sameThreshold), isNull);
    final negativeThreshold = approvedTestFixture()
      ..[DedaLevelBadgeTier.silver] = 0;
    expect(DedaLevelBadgeThresholds.validate(negativeThreshold), isNull);
    final legitimate = DedaLevelBadgeThresholds.validate(approvedTestFixture());
    expect(legitimate, isNotNull);
    expect(DedaLevelBadgePolicy.evaluate(
        serverVerifiedLevel: 100,
        verifiedAccountAndLevel: true,
        ownerApprovedThresholds: legitimate), isNull);
  });

  test('no progress or entitlement from phone-local XP, fake login or unknown level', () {
    final thresholds = DedaLevelBadgeThresholds.validate(approvedTestFixture());
    for (final level in <int?>[null, -1, 0]) {
      expect(DedaLevelBadgePolicy.evaluate(
        serverVerifiedLevel: level,
        verifiedAccountAndLevel: true,
        ownerApprovedThresholds: thresholds,
        allowUnreleasedPurePolicyTest: true,
      ), isNull);
    }
    expect(DedaLevelBadgePolicy.evaluate(
        serverVerifiedLevel: 1000,
        verifiedAccountAndLevel: false,
        ownerApprovedThresholds: thresholds,
        allowUnreleasedPurePolicyTest: true), isNull);
    expect(DedaLevelBadgePolicy.evaluate(
        serverVerifiedLevel: 1000,
        verifiedAccountAndLevel: true,
        ownerApprovedThresholds: null,
        allowUnreleasedPurePolicyTest: true), isNull);
  });

  test('test-only illustrative thresholds enforce six boundaries independently', () {
    // Fixture levels 2,4,6,8,10,12 are NOT approved product thresholds.
    final thresholds = DedaLevelBadgeThresholds.validate(approvedTestFixture());
    final one = DedaLevelBadgePolicy.evaluate(
        serverVerifiedLevel: 1,
        verifiedAccountAndLevel: true,
        ownerApprovedThresholds: thresholds,
        allowUnreleasedPurePolicyTest: true)!;
    expect(one.length, 6);
    expect(one.every((v) => !v.isUnlocked), isTrue);
    expect(one.first.levelsRemaining, 1);

    final eight = DedaLevelBadgePolicy.evaluate(
        serverVerifiedLevel: 8,
        verifiedAccountAndLevel: true,
        ownerApprovedThresholds: thresholds,
        allowUnreleasedPurePolicyTest: true)!;
    expect(eight.map((v) => v.isUnlocked).toList(),
        [true, true, true, true, false, false]);
    expect(eight.map((v) => v.levelsRemaining).toList(), [0, 0, 0, 0, 2, 4]);
  });
}
