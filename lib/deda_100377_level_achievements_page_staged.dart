import 'package:flutter/material.dart';

import 'deda_100377_level_achievement_badges_policy.dart';

/// Point11 preview-only, NOT wired into DEDA's published navigation.
/// All six level-earned achievements are independent of bought style badges.
/// Do not present "earned" from phone-local XP or unverified owner claims.
/// Point10 release gate is OFF; no live achievements are enabled here.
class DedaLevelAchievementsPage extends StatelessWidget {
  const DedaLevelAchievementsPage({
    super.key,
    required this.verifiedServerLevel,
    required this.hasVerifiedAccountAndLevel,
    this.isArabic = true,
  });

  final int? verifiedServerLevel;
  final bool hasVerifiedAccountAndLevel;
  final bool isArabic;

  String _text(String arabic, String english) => isArabic ? arabic : english;

  @override
  Widget build(BuildContext context) {
    // Owner-reviewed PRELIMINARY levels; NOT proof of a user grant.
    final ranges = DedaLevelBadgeThresholds.preliminaryOwnerRanges;
    final earned = DedaLevelBadgePolicy.evaluate(
      serverVerifiedLevel: verifiedServerLevel,
      verifiedAccountAndLevel: hasVerifiedAccountAndLevel,
      ownerApprovedThresholds: ranges,
    );
    // Owner's 3x2 original artwork reference order:
    // gold / silver / emerald / diamond / royal / legendary.
    // This is ONLY the gallery presentation order; it does NOT change
    // any tier thresholds, unlocks, XP or existing "مستوى ذهبي 1" label.
    const tiers = <DedaLevelBadgeTier>[
      DedaLevelBadgeTier.gold,
      DedaLevelBadgeTier.silver,
      DedaLevelBadgeTier.emerald,
      DedaLevelBadgeTier.diamond,
      DedaLevelBadgeTier.royal,
      DedaLevelBadgeTier.legendary,
    ];
    // Calculated progress follows policy enum order (silver before gold).
    // Bind by identity, NOT array index, when UI order differs.
    final progressForTier = <DedaLevelBadgeTier, DedaLevelBadgeProgress>{
      if (earned != null)
        for (final proof in earned) proof.tier: proof,
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(_text('شاراتك وإنجازاتك', 'Your Badges & Achievements')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            _text(
              'الشارات الست تُكتسب حسب المستوى، بدون شراء أو خصم ماسات.',
              'Six level badges are earned automatically, without purchases or diamonds.',
            ),
            key: const Key('deda_p11_earned_not_purchased'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (earned == null)
            Text(
              _text(
                'التوزيع مبدئي. تفعيل الشارات يحتاج توحيد مستوى الحساب والتحقق منه.',
                'Ranges are preliminary. Unlocking requires a verified account level.',
              ),
              key: const Key('deda_p11_no_unverified_unlock'),
              style: const TextStyle(color: Color(0xFF765B3C)),
            ),
          const SizedBox(height: 12),
          for (var i = 0; i < tiers.length; i++)
            _LevelBadgeTile(
              tier: tiers[i],
              threshold: ranges.levelFor(tiers[i]),
              progress: progressForTier[tiers[i]],
              isArabic: isArabic,
            ),
        ],
      ),
    );
  }
}

/// An exact crop from the owner's supplied 3x2 badge art sheet,
/// preserved as ONE authenticated repository image asset; never substitute
/// the separate paid cosmetic badge pictures or fabricate earned status.
/// Gold/Silver/Emerald on row 1, Diamond/Royal/Legendary on row 2.
class DedaOriginalSixLevelBadgeArt extends StatelessWidget {
  const DedaOriginalSixLevelBadgeArt({
    super.key,
    required this.tier,
    this.size = 68,
  });

  static const asset =
      'assets/deda_owner_level_badges/owner_approved_six_rank_badges_768x512.webp';

  final DedaLevelBadgeTier tier;
  final double size;

  @override
  Widget build(BuildContext context) {
    final column = switch (tier) {
      DedaLevelBadgeTier.gold => 0,
      DedaLevelBadgeTier.silver => 1,
      DedaLevelBadgeTier.emerald => 2,
      DedaLevelBadgeTier.diamond => 0,
      DedaLevelBadgeTier.royal => 1,
      DedaLevelBadgeTier.legendary => 2,
    };
    final row = switch (tier) {
      DedaLevelBadgeTier.gold ||
      DedaLevelBadgeTier.silver ||
      DedaLevelBadgeTier.emerald => 0,
      _ => 1,
    };
    // OverflowBox must allow the full 3x2 image to exceed the cell. Only
    // the exact owner's artwork cell is visible after ClipRect.
    return SizedBox(
      key: ValueKey<String>('deda_owner_level_art_${tier.id}'),
      width: size,
      height: size,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: size * 3,
          maxWidth: size * 3,
          minHeight: size * 2,
          maxHeight: size * 2,
          child: Transform.translate(
            offset: Offset(-column * size, -row * size),
            child: Image.asset(
              asset,
              key: ValueKey<String>('deda_owner_level_asset_${tier.id}'),
              width: size * 3,
              height: size * 2,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.medium,
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.image_not_supported_outlined),
            ),
          ),
        ),
      ),
    );
  }
}

class _LevelBadgeTile extends StatelessWidget {
  const _LevelBadgeTile({
    required this.tier,
    required this.threshold,
    required this.progress,
    required this.isArabic,
  });

  final DedaLevelBadgeTier tier;
  final int threshold;
  final DedaLevelBadgeProgress? progress;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final unlocked = progress?.isUnlocked == true;
    final hasVerifiedProgress = progress != null;
    final requiredLabel = isArabic
        ? 'من المستوى $threshold'
        : 'From level $threshold';
    final status = !hasVerifiedProgress
        ? (isArabic ? 'بانتظار التحقق' : 'Verification pending')
        : unlocked
            ? (isArabic ? 'مكتسبة' : 'Earned')
            : (isArabic
                ? 'متبقي ${progress!.levelsRemaining} مستوى'
                : '${progress!.levelsRemaining} levels remaining');

    return Card(
      key: ValueKey<String>('deda_p11_${tier.id}'),
      margin: const EdgeInsets.only(bottom: 9),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            // The original artwork is shown even when pending/locked.
            // Its appearance never grants a badge or changes any level.
            Stack(
              children: <Widget>[
                DedaOriginalSixLevelBadgeArt(tier: tier),
                if (!unlocked)
                  const Positioned(
                    right: 0,
                    bottom: 0,
                    child: Icon(
                      Icons.lock_outline,
                      size: 17,
                      color: Color(0xFF7B8290),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    isArabic ? tier.arabicName : tier.englishName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  Text(requiredLabel),
                  Text(
                    status,
                    key: ValueKey<String>('deda_p11_status_${tier.id}'),
                  ),
                  if (hasVerifiedProgress && !unlocked)
                    LinearProgressIndicator(
                      value: ((threshold - progress!.levelsRemaining) /
                              threshold)
                          .clamp(0.0, 1.0)
                          .toDouble(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
