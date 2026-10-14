import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/main.dart';
import 'package:d_iraq_ludo/deda_place_engagement_bar.dart';

void main() {
  testWidgets('Makani is a separate owner-only entry without changing personal profile', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DedaMakaniPage()));
    expect(find.byType(DedaMakaniPage), findsOneWidget);
    expect(find.byIcon(Icons.storefront_outlined), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Account information keeps user choice and phone, not owner selector',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DedaAccountInfoPage()));
    expect(find.byType(DedaAccountInfoPage), findsOneWidget);
    expect(find.byType(SegmentedButton<DedaAccountType>), findsNothing);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('like numeral sits next to its heart even with long values',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(child: DedaPlaceEngagementBar(
          following: true, liked: true, followers: 987654321,
          likes: 123456789, busy: false,
          onFollow: () {}, onLike: () {},
        )),
      ),
    ));
    expect(find.text('123456789'), findsOneWidget);
    expect(find.text('987654321'), findsOneWidget);
    final heart = tester.getRect(find.byIcon(Icons.favorite_rounded));
    final number = tester.getRect(find.text('123456789'));
    expect(heart.left - number.right, inInclusiveRange(0, 14));
    expect(tester.takeException(), isNull);
  });
}
