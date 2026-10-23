import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_owner18_level_badges.dart';

void main() {
  test('approved rank changes only at 1,10,20,30,40,50', () {
    final values = {
      1: 0,
      9: 0,
      10: 1,
      19: 1,
      20: 2,
      29: 2,
      30: 3,
      39: 3,
      40: 4,
      49: 4,
      50: 5,
      999: 5
    };
    for (final entry in values.entries) {
      expect(DedaOwner18Rank.forLevel(entry.key),
          same(DedaOwner18Rank.all[entry.value]));
    }
  });
  testWidgets(
      'level one gold is current; six ranges have a readable explanation',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: DedaOwner18AchievementsPage(level: 1)));
    expect(find.text('الحالية'), findsOneWidget);
    expect(find.text('من المستوى 1 إلى 9'), findsOneWidget);
    expect(find.textContaining('لا تحتاج إلى شراء'), findsOneWidget);
    expect(find.text('بانتظار التحقق'), findsNothing);
    await tester.scrollUntilVisible(find.text('من المستوى 50 فما فوق'), 300);
    expect(find.text('من المستوى 50 فما فوق'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
