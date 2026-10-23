import 'package:flutter/material.dart';
import 'deda_100377_level_achievement_badges_policy.dart';
import 'deda_100377_level_achievements_page_staged.dart';

/// Owner approved 2026-10-23. Uses the existing level; never writes XP.
class DedaOwner18Rank {
  const DedaOwner18Rank(
      this.tier, this.nameAr, this.nameEn, this.minimum, this.maximum);
  final DedaLevelBadgeTier tier;
  final String nameAr;
  final String nameEn;
  final int minimum;
  final int? maximum;

  static const all = <DedaOwner18Rank>[
    DedaOwner18Rank(DedaLevelBadgeTier.gold, 'الذهبي', 'Gold', 1, 9),
    DedaOwner18Rank(DedaLevelBadgeTier.silver, 'الفضي', 'Silver', 10, 19),
    DedaOwner18Rank(DedaLevelBadgeTier.emerald, 'الزمردي', 'Emerald', 20, 29),
    DedaOwner18Rank(DedaLevelBadgeTier.diamond, 'الألماسي', 'Diamond', 30, 39),
    DedaOwner18Rank(DedaLevelBadgeTier.royal, 'الملكي', 'Royal', 40, 49),
    DedaOwner18Rank(
        DedaLevelBadgeTier.legendary, 'الأسطوري', 'Legendary', 50, null),
  ];

  static DedaOwner18Rank forLevel(int level) =>
      all.lastWhere((rank) => level >= rank.minimum, orElse: () => all.first);

  String range(bool ar) => maximum == null
      ? (ar ? 'من المستوى $minimum فما فوق' : 'Level $minimum and above')
      : (ar ? 'من المستوى $minimum إلى $maximum' : 'Levels $minimum–$maximum');
}

class DedaOwner18LevelBadge extends StatelessWidget {
  const DedaOwner18LevelBadge({super.key, required this.level, this.size = 58});
  final int level;
  final double size;
  @override
  Widget build(BuildContext context) {
    final rank = DedaOwner18Rank.forLevel(level);
    return Tooltip(
      message: '${rank.nameAr} • ${rank.range(true)}',
      child: Semantics(
        label: '${rank.nameAr} • المستوى $level',
        child: DedaOriginalSixLevelBadgeArt(tier: rank.tier, size: size),
      ),
    );
  }
}

class DedaOwner18AchievementsPage extends StatelessWidget {
  const DedaOwner18AchievementsPage(
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
                                  DedaOriginalSixLevelBadgeArt(
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
                      DedaOriginalSixLevelBadgeArt(tier: rank.tier, size: 54)),
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
