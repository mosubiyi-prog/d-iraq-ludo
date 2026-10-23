import 'package:flutter/material.dart';
import 'deda_100377_level_achievement_badges_policy.dart';
import 'deda_six_badge_cutout.dart';

import 'deda_owner18_level_badges.dart' show DedaOwner18Rank;

class DedaSixLevelBadge extends StatelessWidget {
  const DedaSixLevelBadge({super.key, required this.level, this.size = 58});
  final int level;
  final double size;
  @override
  Widget build(BuildContext context) {
    final rank = DedaOwner18Rank.forLevel(level);
    return Tooltip(
      message: '${rank.nameAr} • ${rank.range(true)}',
      child: Semantics(
        label: '${rank.nameAr} • المستوى $level',
        child: DedaSixBadgeCutout(tier: rank.tier, size: size),
      ),
    );
  }
}

class DedaSixAchievementsPage extends StatelessWidget {
  const DedaSixAchievementsPage(
      {super.key, required this.level, this.isArabic = true});
  final int level;
  final bool isArabic;
  String t(String ar, String en) => isArabic ? ar : en;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(t('شارات المستويات', 'Level badges'))),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Text(t(
              'تظهر شارة مستواك تلقائيًا بجانب المستوى في ملفك، وتتغير عند بلوغ النطاق التالي. لا تحتاج إلى شراء أو خصم ماسات.',
              'Your level badge appears automatically in your profile and changes at the next range. No purchase or diamonds are required.')),
          const SizedBox(height: 12),
          for (final rank in DedaOwner18Rank.all)
            Card(
                child: ListTile(
              key: ValueKey('owner18_rank_${rank.minimum}'),
              minVerticalPadding: 12,
              leading: InkWell(
                  onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => AlertDialog(
                            title: Text(isArabic ? rank.nameAr : rank.nameEn),
                            content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  DedaSixBadgeCutout(
                                      tier: rank.tier, size: 200),
                                  const SizedBox(height: 12),
                                  Text(rank.range(isArabic)),
                                ]),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: Text(t('إغلاق', 'Close')))
                            ],
                          )),
                  child:
                      DedaSixBadgeCutout(tier: rank.tier, size: 54)),
              title: Text(isArabic ? rank.nameAr : rank.nameEn),
              subtitle: Text(rank.range(isArabic)),
              trailing: Text(level >= rank.minimum
                  ? (identical(DedaOwner18Rank.forLevel(level), rank)
                      ? t('الحالية', 'Current')
                      : t('مكتسبة', 'Earned'))
                  : t('متبقي ${rank.minimum - level} مستوى',
                      '${rank.minimum - level} levels remaining')),
            )),
        ]),
      );
}
