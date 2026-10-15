import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:d_iraq_ludo/main.dart';
import 'package:d_iraq_ludo/places_service.dart';
import 'package:d_iraq_ludo/deda_place_engagement_service.dart';

void main() {
  testWidgets('actual DEDA circle remains at geographic map centre through rotation and zoom',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(440, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final map = MapController();
    const loc = LatLng(32.0343, 44.1420);
    const place = PlaceInfo(
      name: 'غسل يونس العزاوي',
      type: 'غسل سيارات',
      location: loc,
      isDedaRegistered: true,
      isAvailableNow: true,
      publishedPlaceId: '100340_fake_qa_place',
      themeIndex: 3,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            height: 520,
            child: FlutterMap(
              mapController: map,
              options: const MapOptions(
                initialCenter: loc,
                initialZoom: 13,
                interactionOptions: InteractionOptions(flags: InteractiveFlag.all),
              ),
              children: [
                MarkerLayer(
                  markers: [
                    Marker(
                      point: loc,
                      width: 186,
                      height: 260,
                      alignment: Alignment.center,
                      rotate: true,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            top: 3,
                            left: 0,
                            width: 186,
                            height: 148,
                            child: DedaMapPlaceMarker(
                              place: place,
                              icon: Icons.local_car_wash,
                              selected: true,
                              socialLoaded: true,
                              social: const DedaPlaceEngagement(
                                following: false, liked: false, followers: 21,
                              ),
                              onTap: () {},
                              onLabelTap: () {},
                              onFollow: () {},
                              onLike: () {},
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    // Slot 65x42 and its centre circle are the actual geographic icon.
    // Unlike an off-centre marker pivot, this position must not orbit as
    // FlutterMap counter-rotates all labels at any map heading.
    Finder slot() => find.byWidgetPredicate((w) =>
        w is SizedBox && w.width == 65 && w.height == 42);
    expect(slot(), findsOneWidget);
    final geoScreenCentre = tester.getRect(find.byType(FlutterMap)).center;
    for (final bearing in [0.0, 45.0, 90.0, 180.0, 270.0, 359.0]) {
      map.rotate(bearing);
      for (final zoom in [11.8, 13.0, 15.2, 16.0]) {
        map.move(loc, zoom);
        await tester.pump();
        final avatar = tester.getCenter(slot());
        expect((avatar - geoScreenCentre).distance, lessThan(2.5),
            reason: 'DEDA owner pin must remain exactly on place.location at bearing=$bearing zoom=$zoom');
      }
    }
    expect(find.text('غسل يونس العزاوي'), findsOneWidget);
    expect(find.text('21'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
