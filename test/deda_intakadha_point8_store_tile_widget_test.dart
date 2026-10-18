import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_intakadha_point8_store_tile_fixture.dart';

void main() {
  Widget sample({
    required double viewport,
    required bool compact,
    required VoidCallback onTap,
  }) {
    final itemWidth = (viewport - 32 - 10) / 2;
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: DedaPoint8StoreTileFixture(
            width: itemWidth,
            compact: compact,
            onTap: onTap,
          ),
        ),
      ),
    );
  }

  testWidgets('shop name fully legible at 320, 360 and 430 dp in the SAME card',
      (tester) async {
    for (final width in <double>[320, 360, 430]) {
      await tester.pumpWidget(sample(
        viewport: width, compact: true, onTap: () {},
      ));
      expect(find.text('متجر\nالمعرّفات'), findsOneWidget);
      expect(find.text('معرّفات مميزة'), findsOneWidget);
      expect(find.byIcon(Icons.storefront_rounded), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
      final title = tester.renderObject<RenderParagraph>(
        find.text('متجر\nالمعرّفات'),
      );
      expect(title.didExceedMaxLines, false,
          reason: 'Arabic identifier-store label must not truncate at $width dp');
      final ink = tester.widget<Ink>(find.byType(Ink).first);
      expect(ink.height, 112);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('original neighboring card keeps 46dp icon, chevron, 16dp title',
      (tester) async {
    await tester.pumpWidget(sample(
      viewport: 360, compact: false, onTap: () {},
    ));
    expect(find.text('تعديل الملف'), findsOneWidget);
    expect(find.byIcon(Icons.edit_rounded), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
    final icon = tester.widget<Icon>(find.byIcon(Icons.edit_rounded));
    expect(icon.size, 26);
    final title = tester.widget<Text>(find.text('تعديل الملف'));
    expect(title.maxLines, 1);
    expect(title.style!.fontSize, 16);
    expect(tester.widget<Ink>(find.byType(Ink).first).height, 112);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shop tile tap fires exactly once; no premature purchase route',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(sample(
      viewport: 360, compact: true, onTap: () => taps++,
    ));
    await tester.tap(find.text('متجر\nالمعرّفات'));
    await tester.pump();
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });
}
