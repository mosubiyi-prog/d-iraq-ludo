import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_lab_premium_frame_artwork.dart';
import 'package:d_iraq_ludo/deda_lab_verified_frame_catalog.dart';

void main() {
  test('all thirteen original paid LAB frame styles map 6..18 without losing price', () {
    expect(DedaLabPremiumFrameStyles.paidFrames.length, 13);
    for (var index = 6; index <= 18; index++) {
      final art = DedaLabPremiumFrameStyles.byProfileStyle(index)!;
      expect(art.priceDiamonds, 1000);
      expect(art.bundled, true);
      expect(art.free, false);
      expect(DedaLabPremiumFrameStyles.profileStyleOf(art), index);
      expect(art.portraitLeft + art.portraitWidth, lessThanOrEqualTo(1));
      expect(art.portraitTop + art.portraitHeight, lessThanOrEqualTo(1));
    }
    expect(DedaLabPremiumFrameStyles.byProfileStyle(5), isNull);
    expect(DedaLabPremiumFrameStyles.byProfileStyle(19), isNull);
    expect(dedaLabVerifiedFrames.where((f)=>f.free).length, 3);
  });

  testWidgets('each of the 13 originals renders at phone size with stable portrait', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final art in DedaLabPremiumFrameStyles.paidFrames) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(
          child: DedaLabPremiumFrameArtwork(
            key: ValueKey('asset_' + art.id),
            spec: art,
            size: 111,
            animate: false,
            portrait: const ColoredBox(color: Colors.blue),
          ),
        )),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('deda_lab_original_' + art.id)), findsOneWidget);
      expect(find.byWidgetPredicate((w) =>
        w is Image && w.image is AssetImage &&
        (w.image as AssetImage).assetName == art.assetPath), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
