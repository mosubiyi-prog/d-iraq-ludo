import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_place_engagement_bar.dart';

void main() {
  Widget view({
    required bool following,
    required bool liked,
    required int followers,
    required VoidCallback follow,
    required VoidCallback like,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: DedaPlaceEngagementBar(
              following: following,
              liked: liked,
              followers: followers,
              busy: false,
              onFollow: follow,
              onLike: like,
            ),
          ),
        ),
      );

  testWidgets('three compact controls only, no descriptive words in the bar',
      (tester) async {
    var follows = 0;
    var likes = 0;
    await tester.pumpWidget(view(
      following: false,
      liked: false,
      followers: 125,
      follow: () => follows++,
      like: () => likes++,
    ));
    expect(find.byIcon(Icons.person_add_alt_1_rounded), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    expect(find.byIcon(Icons.people_alt_outlined), findsOneWidget);
    expect(find.text('125'), findsOneWidget);
    expect(find.text('متابعة'), findsNothing);
    expect(find.text('إعجاب'), findsNothing);

    await tester.tap(find.byIcon(Icons.person_add_alt_1_rounded));
    await tester.pump();
    expect(follows, 1);
    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await tester.pump();
    expect(likes, 1);
  });

  testWidgets('long real follower counts are visible without layout overflow',
      (tester) async {
    await tester.pumpWidget(view(
      following: false,
      liked: false,
      followers: 123456789,
      follow: () {},
      like: () {},
    ));
    expect(find.text('123456789'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('liked heart is exactly red, follow icon becomes a check',
      (tester) async {
    await tester.pumpWidget(view(
      following: true,
      liked: true,
      followers: 126,
      follow: () {},
      like: () {},
    ));
    expect(find.byIcon(Icons.how_to_reg_rounded), findsOneWidget);
    final heart = tester.widget<Icon>(find.byIcon(Icons.favorite_rounded));
    expect(heart.color, const Color(0xFFE53935));
    expect(find.text('126'), findsOneWidget);
  });
}
