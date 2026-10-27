import 'package:flutter/material.dart';
import 'deda_weekly_leaderboard_page.dart';
import 'deda_weekly_leaderboard_policy.dart';

/// INSTALLS BESIDE the original DEDA (different package).
/// VISUAL DEMO ONLY: zero accounts, network, Firebase, prizes, XP or purchases.
void main() => runApp(const DedaVisualPreview());

class DedaVisualPreview extends StatelessWidget {
  const DedaVisualPreview({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'DEDA — معاينة المتصدرين',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        home: const DedaPreviewHome(),
      );
}

class DedaPreviewHome extends StatelessWidget {
  const DedaPreviewHome({super.key});

  void openPreview(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => DedaWeeklyLeaderboardPage(
        previewOnly: true,
        current: demoStandings(previous: false),
        previous: demoStandings(previous: true),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: const Color(0xFF041A33),
          appBar: AppBar(
            title: const Text('DEDA — معاينة خاصة'),
            backgroundColor: const Color(0xFF0B3056),
            centerTitle: true,
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  // Only the independent demo's launcher can scroll on
                  // very short phones. The LEADERBOARD itself never scrolls.
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    children: [
                      const Icon(Icons.emoji_events_rounded,
                          color: Color(0xFFFFD15B), size: 74),
                      const SizedBox(height: 14),
                      const Text('بطاقة متصدرين المهام',
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFFFD15B))),
                      const SizedBox(height: 10),
                      const Text(
                        'هاي معاينة مستقلة حتى تشوف شكل البطاقة ومراكز اللاعبين قبل تشغيل الدوري الحقيقي.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Colors.white70),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 118,
                        width: double.infinity,
                        child: DedaLeaderboardHomeCard(
                          onTap: () => openPreview(context),
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: () => openPreview(context),
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('افتح ترتيب المتصدرين'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFFD15B),
                          foregroundColor: const Color(0xFF051B35),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 26, vertical: 14),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'معاينة فقط — الأسماء والأرصدة المعروضة أمثلة، '
                        'ولا يوجد تسجيل دخول أو حفظ نقاط أو صرف ماسات. '
                        'تطبيق DEDA الأصلي يبقى مثبتاً ومستقلاً.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12, color: Color(0xFF9CB9D9)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

DedaLeaderboardViewData demoStandings({required bool previous}) {
  final points = previous
      ? const <int>[380, 360, 340, 320, 300, 280, 260, 240, 220, 200, 180, 160]
      : const <int>[420, 400, 380, 360, 340, 320, 300, 280, 260, 240, 220, 180];
  final labels = <String>[
    'المركز الذهبي',
    'المركز الفضي',
    'المركز البرونزي',
    'متسابق ديدا 4',
    'متسابق ديدا 5',
    'متسابق ديدا 6',
    'متسابق ديدا 7',
    'متسابق ديدا 8',
    'متسابق ديدا 9',
    'متسابق ديدا 10',
    'متسابق ديدا 11',
    'أنت (تجريبي)',
  ];
  final rows = <DedaWeeklyLeaderboardRow>[
    for (var i = 0; i < points.length; i++)
      DedaWeeklyLeaderboardRow(
        place: i + 1,
        accountUid: 'demo-participant-${i + 1}',
        weeklyPoints: points[i],
        verifiedTaskCompletions: points[i] ~/ 20,
        diamondsIfFinalWinner:
            DedaWeeklyLeaderboardPolicy.diamondsForFinalPlace(i + 1),
      ),
  ];
  return DedaLeaderboardViewData(
    // UI fixtures only, previewOnly watermark always visible;
    // never passed to the actual DEDA or a server ledger.
    verified: true,
    rows: rows,
    profilesByUid: <String, DedaLeaderboardProfile>{
      for (var i = 0; i < labels.length; i++)
        'demo-participant-${i + 1}': DedaLeaderboardProfile(
          accountUid: 'demo-participant-${i + 1}',
          displayName: labels[i],
          activePublicId:
              '@DEDA-DEMO${(i + 1).toString().padLeft(2, '0')}',
        ),
    },
    viewerUid: 'demo-participant-12',
    remainingUntilWeekEnd: previous
        ? Duration.zero
        : const Duration(days: 4, hours: 19, minutes: 27),
  );
}
