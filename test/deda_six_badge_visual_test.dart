import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_six_badge_cutout.dart';
import '../lib/deda_100377_level_achievement_badges_policy.dart';

void main() {
  testWidgets('all six badge exteriors transparent with original opaque interiors', (tester) async {
    await tester.runAsync(() => DedaSixBadgeCutout.warmUp());
    for (final tier in DedaLevelBadgeTier.values) {
      final key=GlobalKey();
      await tester.pumpWidget(MaterialApp(home: Center(child:RepaintBoundary(
        key:key, child:DedaSixBadgeCutout(tier:tier,size:256)))));
      await tester.pump();
      final boundary=key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
      final image=await boundary.toImage(pixelRatio:1);
      final rgba=await image.toByteData(format:ui.ImageByteFormat.rawRgba);
      expect(rgba!.getUint8(3),0,reason:'${tier.id} top-left backdrop');
      expect(rgba.getUint8((255*256+255)*4+3),0,reason:'${tier.id} bottom-right backdrop');
      expect(rgba.getUint8((128*256+128)*4+3),255,reason:'${tier.id} original interior');
      final png=await image.toByteData(format:ui.ImageByteFormat.png);
      Directory('six-note-visual-qa').createSync(recursive:true);
      File('six-note-visual-qa/${tier.id}.png').writeAsBytesSync(png!.buffer.asUint8List());
      image.dispose();
      });
      expect(tester.takeException(),isNull);
    }
  });
}
