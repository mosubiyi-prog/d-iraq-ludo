import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:d_iraq_ludo/main.dart';
import 'package:d_iraq_ludo/places_service.dart';
import 'package:d_iraq_ludo/deda_place_palette.dart';
import 'package:d_iraq_ludo/deda_place_activity_symbol.dart';
import 'package:d_iraq_ludo/deda_place_engagement_service.dart';

void main() {
  testWidgets('M03 label tap differs from lower avatar route tap',
      (tester) async {
    var labelTaps = 0;
    var routeTaps = 0;
    var followTaps = 0;
    var likeTaps = 0;
    const place = PlaceInfo(
      name: 'كوافير',
      type: 'صالون نسائي',
      location: LatLng(35.065223, 43.685798),
      isDedaRegistered: true,
      isAvailableNow: false,
      publishedPlaceId: 'place_qa_100335',
      themeIndex: 1,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 186,
            height: 148,
            child: DedaMapPlaceMarker(
              place: place,
              icon: Icons.store,
              onTap: () => routeTaps++,
              onLabelTap: () => labelTaps++,
              selected: true,
              socialLoaded: true,
              social: const DedaPlaceEngagement(
                following: false,
                liked: false,
                followers: 27,
              ),
              onFollow: () => followTaps++,
              onLike: () => likeTaps++,
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('كوافير'));
    await tester.pump();
    expect(labelTaps, 1);
    expect(routeTaps, 0, reason: 'Name MUST NOT begin navigation');

    // The larger, lower activity symbol belongs to the route avatar.
    final activity = find.byType(DedaPlaceActivitySymbol);
    expect(activity, findsWidgets);
    await tester.tap(activity.last);
    await tester.pump();
    expect(routeTaps, 1);
    expect(labelTaps, 1);

    expect(find.text('27'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.person_add_alt_1_rounded));
    await tester.pump();
    expect(followTaps, 1);
    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await tester.pump();
    expect(likeTaps, 1);
    expect(routeTaps, 1);

    final name = tester.widget<Text>(find.text('كوافير'));
    expect(name.maxLines, 2);
    final fills = tester.widgetList<Container>(find.byType(Container))
        .where((c) => c.decoration is BoxDecoration)
        .map((c) => (c.decoration as BoxDecoration).color)
        .toList();
    expect(fills, contains(DedaPlacePalette.forIndex(1)),
        reason: 'Full place-name bubble should have actual selected fill');
    expect(fills, contains(const Color(0xFF858E88)),
        reason: 'Unavailable DEDA identity should be muted grey');
    expect(tester.takeException(), isNull);
  });
}
