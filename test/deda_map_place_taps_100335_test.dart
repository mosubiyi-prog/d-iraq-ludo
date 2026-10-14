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
    expect(fills.where((c) => c == const Color(0xFF858E88)).length,
        greaterThanOrEqualTo(2),
        reason: 'Inactive NAME fill and DEDA badge must both be grey');
    expect(tester.takeException(), isNull);
  });
  testWidgets('M05 all 14 owner colors fill name and DEDA badge, grey when absent',
      (tester) async {
    for (var index = 0; index < DedaPlacePalette.colors.length; index++) {
      for (final present in [true, false]) {
        final place = PlaceInfo(
          name: 'ماركت',
          type: 'متجر',
          location: const LatLng(32.00, 44.00),
          isDedaRegistered: true,
          isAvailableNow: present,
          publishedPlaceId: 'approved_test_place_100336',
          themeIndex: index,
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
                  onTap: () {},
                  onLabelTap: () {},
                ),
              ),
            ),
          ),
        ));
        final target = present
            ? DedaPlacePalette.forIndex(index)
            : const Color(0xFF858E88);
        final decorations = tester.widgetList<Container>(find.byType(Container))
            .map((w) => w.decoration)
            .whereType<BoxDecoration>()
            .toList();
        final colorFills = decorations.where((d) => d.color == target).length;
        expect(colorFills, greaterThanOrEqualTo(2),
            reason: 'Name and DEDA badge fills should match for color $index / present=$present');
        final ring = decorations.where((d) =>
            d.shape == BoxShape.circle &&
            d.border != null &&
            d.border!.top.color == target).length;
        expect(ring, greaterThanOrEqualTo(1),
            reason: 'Photo/activity frame must match the name and DEDA badge');
        expect(tester.takeException(), isNull);
      }
    }
  });

}
