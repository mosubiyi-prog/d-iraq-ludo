import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_admin_league_reward_status.dart';

void main() {
  testWidgets('does not invent prize credits before real Hadaya receipts',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: DedaAdminLeagueRewardStatus(isArabic:true,
        testGifts:Stream.value(const <Map<String,dynamic>>[])),
    )));
    await tester.pump();
    expect(find.textContaining('لم تظهر جوائز أسبوعية'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('real pending and claimed gifts counted separately',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: DedaAdminLeagueRewardStatus(
        isArabic:true,
        testGifts:Stream.value([
          {'giftId':'award1','sourceType':'weekly_league','targetPublicId':'@DEDA-AAAA11','amount':150,'status':'pending'},
          {'giftId':'award2','sourceType':'weekly_league','targetPublicId':'@DEDA-BBBB22','amount':100,'status':'received'},
          {'giftId':'admin-gift','sourceType':'admin','targetPublicId':'@DEDA-CCCC33','amount':500,'status':'received'},
        ]),
      ),
    )));
    await tester.pump();
    expect(find.text('جوائز هداياي المنشأة: 2'), findsOneWidget);
    expect(find.text('بانتظار الاستلام: 1'), findsOneWidget);
    expect(find.text('تم استلامها: 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
