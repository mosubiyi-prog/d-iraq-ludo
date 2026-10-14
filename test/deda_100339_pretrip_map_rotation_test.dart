import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('DEDA registered marker offset anchors lower 42px avatar slot', () {
    const markerHeight = 148.0;
    const avatarSlotHeight = 42.0;
    const alignment = Alignment(0, 0.7162162162162162);
    final anchorY = (alignment.y + 1) * markerHeight / 2;
    expect(anchorY, closeTo(markerHeight - avatarSlotHeight / 2, 0.001));
    // The tap area remains 186x148 to cover the name and the engagement bar.
    expect(alignment.x, 0);
  });

  testWidgets('two-finger rotation works in small map inside scroll page',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(440, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = MapController();
    const place = LatLng(32.0343, 44.1420);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 130),
              SizedBox(
                height: 340,
                child: FlutterMap(
                  mapController: controller,
                  options: const MapOptions(
                    initialCenter: place,
                    initialZoom: 13,
                    interactionOptions: InteractionOptions(
                      flags: InteractiveFlag.all,
                    ),
                  ),
                  children: [
                    MarkerLayer(
                      markers: const [
                        Marker(
                          point: place,
                          width: 186,
                          height: 148,
                          alignment: Alignment(0, 0.7162162162162162),
                          rotate: true,
                          child: Icon(Icons.storefront, size: 24),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 350),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();
    final start = controller.camera.rotation;
    final center = tester.getCenter(find.byType(FlutterMap));
    // Keep both pointers within the interactive map bounds and outside
    // of the actual small visual avatar, as in a deliberate two-finger turn.
    final first = await tester.startGesture(center + const Offset(-70, 10), pointer: 12);
    final second = await tester.startGesture(center + const Offset(70, 10), pointer: 13);
    await tester.pump(const Duration(milliseconds: 30));
    await first.moveTo(center + const Offset(0, -60));
    await second.moveTo(center + const Offset(0, 80));
    await tester.pump(const Duration(milliseconds: 150));
    final turn = controller.camera.rotation - start;
    expect(turn.abs(), greaterThan(15), reason: 'two-finger rotation must work before navigation begins');
    await first.up();
    await second.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
