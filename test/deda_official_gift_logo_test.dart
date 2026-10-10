import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_official_gift_logo.dart';

void main() {
  testWidgets('real DEDA signed launcher emblem is visible on incoming gift',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(
        body: Center(child: DedaOfficialGiftLogo(size: 52)),
      )),
    );
    await tester.pump();
    expect(find.byType(DedaOfficialGiftLogo), findsOneWidget);
    expect(find.byKey(const Key('dedaOfficialGiftLogo')), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('official emblem fits a compact gift tile on small screens',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: DedaOfficialGiftLogo(size: 44),
    )));
    expect(tester.getSize(find.byType(DedaOfficialGiftLogo)),
        const Size(44, 44));
    expect(tester.takeException(), isNull);
  });
}
