import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_lab_original_frames_gallery.dart';
import 'package:d_iraq_ludo/deda_lab_verified_frame_catalog.dart';

void main() {
  testWidgets('real 16 frame thumbnails, 3 free + 13 x1000 and no charge on preview',
      (tester) async {
    DedaLabFrameSpec? selected;
    await tester.binding.setSurfaceSize(const Size(430, 950));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(
        child: DedaLabOriginalFrameGallery(
          avatarStyle: 0,
          portrait: (size) => SizedBox.square(
            dimension: size,
            child: const DecoratedBox(decoration: BoxDecoration(
              color: Color(0xFFE6CDAB),shape: BoxShape.circle)),
          ),
          selectedId: null,
          onSelect: (frame) => selected=frame,
        ),
      )),
    ));
    await tester.pump();
    expect(find.byKey(const Key('deda_lab_original_16_gallery')), findsOneWidget);
    expect(find.byType(DedaLabOriginalFrameArtwork), findsNWidgets(16));
    expect(find.text('🔒 1000 💎'), findsNWidgets(13));
    expect(find.text('مجاني · استخدام'), findsNWidgets(3));
    final paid = find.byKey(const ValueKey('deda_lab_FRAME_03_tile'));
    await tester.ensureVisible(paid);
    await tester.tap(paid);
    expect(selected?.id, 'FRAME_03');
    expect(selected?.free, false);
    expect(selected?.priceDiamonds,1000);
    expect(tester.takeException(),isNull);
  });
}
