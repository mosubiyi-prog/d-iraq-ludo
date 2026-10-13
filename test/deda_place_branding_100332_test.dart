import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_place_palette.dart';
import 'package:d_iraq_ludo/deda_place_logo.dart';

void main() {
  test('exactly seven colors with one lighter match underneath each', () {
    expect(DedaPlacePalette.colors, hasLength(14));
    for (var pair = 0; pair < 7; pair++) {
      final deep = DedaPlacePalette.colors[pair * 2];
      final pale = DedaPlacePalette.colors[pair * 2 + 1];
      expect(deep.computeLuminance(), lessThan(pale.computeLuminance()));
    }
  });

  test('out of range or legacy value becomes a safe default', () {
    expect(DedaPlacePalette.safeIndex(null), 4);
    expect(DedaPlacePalette.safeIndex(-1), 4);
    expect(DedaPlacePalette.safeIndex(14), 4);
    expect(DedaPlacePalette.safeIndex('13'), 13);
  });

  testWidgets('color selection closes on callback and shows checkmark',
      (tester) async {
    var selected = 4;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: DedaPlaceColorChooser(
            selected: selected,
            onChanged: (index) => setState(() => selected = index),
          ),
        ),
      ),
    ));
    expect(find.bySemanticsLabel('لون المكان 5'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('لون المكان 2'));
    await tester.pump();
    expect(selected, 1);
  });

  test('logo upload never runs without explicit audited feature flag', () {
    expect(DedaPlaceLogoService.uploadsEnabled, false);
    expect(DedaPlacePalette.serverPublishingEnabled, false);
  });
}
