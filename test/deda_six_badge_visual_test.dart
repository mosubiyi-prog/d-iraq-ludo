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
      await tester.pumpAndSettle();
      final boundary=key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      print('BADGE ${tier.id} boundary=${tester.getSize(find.byKey(key))} painters=${find.descendant(of:find.byKey(key),matching:find.byType(CustomPaint)).evaluate().length}');
      final pixels=await tester.runAsync(() async {
        final image=await boundary.toImage(pixelRatio:1);
        final rgba=await image.toByteData(format:ui.ImageByteFormat.rawRgba);
        final png=await image.toByteData(format:ui.ImageByteFormat.png);
        Directory('six-note-visual-qa').createSync(recursive:true);
        File('six-note-visual-qa/${tier.id}.png').writeAsBytesSync(png!.buffer.asUint8List());
        final bytes=rgba!.buffer.asUint8List();
        var visible=0;
        for(var i=3;i<bytes.length;i+=4) {if(bytes[i]>0) visible++;}
        print('BADGE ${tier.id} pixels=${image.width}x${image.height} visible=$visible center=${rgba.getUint8((128*image.width+128)*4+3)}');
        final result=[rgba.getUint8(3),rgba.getUint8((255*image.width+255)*4+3),rgba.getUint8((128*image.width+128)*4+3)];
        image.dispose();
        return result;
      });
      expect(pixels,[0,0,255],reason:'${tier.id} transparent exterior and original opaque interior');
      expect(tester.takeException(),isNull);
    }
  });
}
