/// DEDA Point10: six LEVEL achievement identities, NOT the six purchased badges.
///
/// This is a source-only, feature-gated policy. A level achievement may NOT
/// become visible/earned before verified cloud account provenance, explicit
/// owner-approved thresholds, and a signed two-account device test exist.
/// Does not load/write user storage, XP, wallet, purchased styles or Firebase.
enum DedaLevelBadgeTier {
  silver('level_silver', 'فضية', 'Silver'),
  gold('level_gold', 'ذهبية', 'Gold'),
  emerald('level_emerald', 'زمردية', 'Emerald'),
  diamond('level_diamond', 'ماسية', 'Diamond'),
  royal('level_royal', 'ملكية', 'Royal'),
  legendary('level_legendary', 'أسطورية', 'Legendary');

  const DedaLevelBadgeTier(this.id, this.arabicName, this.englishName);
  final String id;
  final String arabicName;
  final String englishName;
}

class DedaLevelBadgeThresholds {
  /// Exactly six owner-approved, strictly increasing positive LEVELS.
  /// No implicit 1/5/10 thresholds or level-for-task-points shortcuts.
  final Map<DedaLevelBadgeTier, int> _levels;
  const DedaLevelBadgeThresholds._(this._levels);

  static DedaLevelBadgeThresholds? validate(
      Map<DedaLevelBadgeTier, int>? proposed) {
    if (proposed == null ||
        proposed.length != DedaLevelBadgeTier.values.length) {
      return null;
    }
    var previous = 0;
    final safe = <DedaLevelBadgeTier, int>{};
    for (final tier in DedaLevelBadgeTier.values) {
      final level = proposed[tier];
      if (level == null || level <= previous || level > 99999999) {
        return null;
      }
      safe[tier] = level;
      previous = level;
    }
    return DedaLevelBadgeThresholds._(Map.unmodifiable(safe));
  }

  int levelFor(DedaLevelBadgeTier tier) => _levels[tier]!;
}

class DedaLevelBadgeProgress {
  const DedaLevelBadgeProgress({
    required this.tier,
    required this.requiredLevel,
    required this.isUnlocked,
    required this.levelsRemaining,
  });

  final DedaLevelBadgeTier tier;
  final int requiredLevel;
  final bool isUnlocked;
  final int levelsRemaining;
}

class DedaLevelBadgePolicy {
  DedaLevelBadgePolicy._();

  /// Keeps *all* Point10 achievements hidden/inactive in unapproved builds.
  static const bool releaseEnabled = bool.fromEnvironment(
    'DEDA_100377_LEVEL_ACHIEVEMENTS_APPROVED',
    defaultValue: false,
  );

  /// Release feature gate has NO caller-overridable bypass. Remains off
  /// until verified cloud identity/level plus owner thresholds are connected.
  static List<DedaLevelBadgeProgress>? evaluate({
    required int? serverVerifiedLevel,
    required bool verifiedAccountAndLevel,
    required DedaLevelBadgeThresholds? ownerApprovedThresholds,
  }) {
    if (!releaseEnabled) return null;
    return inspectVerifiedLevelForPolicyQa(
      serverVerifiedLevel: serverVerifiedLevel,
      verifiedAccountAndLevel: verifiedAccountAndLevel,
      ownerApprovedThresholds: ownerApprovedThresholds,
    );
  }

  /// Pure deterministic calculation for source-policy testing only.
  /// Produces NO ownership, Firebase entitlement, user state, or award.
  static List<DedaLevelBadgeProgress>? inspectVerifiedLevelForPolicyQa({
    required int? serverVerifiedLevel,
    required bool verifiedAccountAndLevel,
    required DedaLevelBadgeThresholds? ownerApprovedThresholds,
  }) {
    if (!verifiedAccountAndLevel ||
        serverVerifiedLevel == null ||
        serverVerifiedLevel < 1 ||
        serverVerifiedLevel > 99999999 ||
        ownerApprovedThresholds == null) {
      return null;
    }
    return List<DedaLevelBadgeProgress>.unmodifiable(
        DedaLevelBadgeTier.values.map((tier) {
      final required = ownerApprovedThresholds.levelFor(tier);
      return DedaLevelBadgeProgress(
        tier: tier,
        requiredLevel: required,
        isUnlocked: serverVerifiedLevel >= required,
        levelsRemaining: serverVerifiedLevel >= required
            ? 0
            : required - serverVerifiedLevel,
      );
    }));
  }
}
