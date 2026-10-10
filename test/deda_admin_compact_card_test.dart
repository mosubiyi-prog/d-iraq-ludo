import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_admin_compact_card.dart';

Widget testCard({required String title, VoidCallback? onTap}) {
  return DedaAdminCompactCard(
    icon: Icons.people,
    title: title,
    subtitle: 'إضافة الأعضاء وتحديد أدوارهم وصلاحياتهم',
    accentColor: const Color(0xFF2F6B8A),
    onTap: onTap ?? () {},
  );
}

void main() {
  for (final textScale in [1.0, 1.4, 2.0]) {
    testWidgets('home-sized colorful admin card fits at scale $textScale',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(320, 640),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 96,
                  height: (126 * textScale).clamp(126.0, 240.0),
                  child: testCard(
                    title: 'إدارة الفريق والصلاحيات',
                    onTap: () => tapped = true,
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('إدارة الفريق والصلاحيات'), findsOneWidget);
      expect(find.byType(DedaAdminCompactCard), findsOneWidget);
      await tester.tap(find.byType(DedaAdminCompactCard));
      await tester.pump();
      expect(tapped, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('phone administration has 3 small category cards per row',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: GridView.count(
            crossAxisCount: 3,
            padding: const EdgeInsets.all(16),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            mainAxisExtent: 126,
            children: [
              for (var i = 0; i < 9; i++)
                testCard(title: 'إدارة الفريق والصلاحيات $i'),
            ],
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    final tiles = find.byType(DedaAdminCompactCard);
    expect(tiles, findsNWidgets(9));
    final first = tester.getTopLeft(tiles.at(0));
    final second = tester.getTopLeft(tiles.at(1));
    final third = tester.getTopLeft(tiles.at(2));
    final fourth = tester.getTopLeft(tiles.at(3));
    expect(first.dy, second.dy);
    expect(second.dy, third.dy);
    expect(fourth.dy, greaterThan(first.dy));
    final card = tester.widget<Card>(find.byType(Card).first);
    expect(card.elevation, greaterThan(2));
  });
}
