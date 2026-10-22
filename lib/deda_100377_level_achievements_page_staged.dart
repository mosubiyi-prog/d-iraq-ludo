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
    const tiers = DedaLevelBadgeTier.values;
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
              progress: earned == null ? null : earned[i],
              isArabic: isArabic,
            ),
        ],
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
            Icon(
              unlocked ? Icons.workspace_premium : Icons.lock_outline,
              color: unlocked
                  ? const Color(0xFF906F35)
                  : const Color(0xFF7B8290),
              size: 30,
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
