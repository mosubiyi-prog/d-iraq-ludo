import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_point14_owned_card_fixture.dart';

void main() {
  setUp(() {
    DedaPoint14VerifiedBridge.readRemote = null;
    DedaPoint14VerifiedBridge.activateRemote = null;
    DedaPoint14VerifiedBridge.notifier.value = null;
  });

  void phoneSize(WidgetTester tester, double width, double height) {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget app({
    String identifier = '@DEDA-AQPYXJ',
    double width = 320,
  }) => MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF192A3F),
          body: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                DedaPoint14VerifiedProfileSlot(
                  identifier: identifier,
                  width: width - 45,
                  compact: true,
                  onCopy: () {},
                ),
                SizedBox(
                  width: width - 20,
                  child: DedaPoint14VerifiedAccountPanel(identifier: identifier),
                ),
              ],
            ),
          ),
        ),
      );

  DedaPoint14VerifiedSnapshot snapshot({
    String identifier = '@DEDA-AQPYXJ',
    Set<DedaPremiumIdCardColor> owned = const <DedaPremiumIdCardColor>{},
    DedaPremiumIdCardColor? active,
  }) =>
      DedaPoint14VerifiedSnapshot(
        identifier: identifier,
        owned: owned,
        active: active,
      );

  Finder use(String color) =>
      find.byKey(ValueKey<String>('deda_intakadha_point7_use_' + color));

  Future<void> tapUse(WidgetTester tester, String color) async {
    await tester.ensureVisible(use(color));
    await tester.pumpAndSettle();
    await tester.tap(use(color));
    await tester.pumpAndSettle();
  }

  testWidgets('no connected trusted backend: no owned/use; original ID copy slot',
      (tester) async {
    phoneSize(tester, 360, 900);
    await tester.pumpWidget(app(width: 360));
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(use('gold')).onPressed, isNull);
    expect(find.textContaining('بانتظار إثبات الملكية'), findsWidgets);
    expect(find.byType(DedaPoint14VerifiedProfileSlot), findsOneWidget);
    final profile = tester.widget<DedaProfileVerifiedIdCardSlot>(
        find.byType(DedaProfileVerifiedIdCardSlot).first);
    expect(profile.identifier, '@DEDA-AQPYXJ');
    expect(profile.verifiedOwnedColor, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('verified owned Gold shows Use; server save and refresh updates 50dp profile slot',
      (tester) async {
    phoneSize(tester, 390, 950);
    var remoteActive = null as DedaPremiumIdCardColor?;
    var writes = 0;
    var reads = 0;
    DedaPoint14VerifiedBridge.readRemote = () async {
      reads++;
      return snapshot(
        owned: {DedaPremiumIdCardColor.gold}, active: remoteActive);
    };
    DedaPoint14VerifiedBridge.activateRemote = (color) async {
      writes++;
      remoteActive = color;
      return snapshot(
        owned: {DedaPremiumIdCardColor.gold}, active: remoteActive);
    };
    await tester.pumpWidget(app(width: 390));
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(use('gold')).onPressed, isNotNull);
    expect(tester.widget<OutlinedButton>(use('pink')).onPressed, isNull);
    await tapUse(tester, 'gold');
    expect(writes, 1);
    expect(reads, greaterThanOrEqualTo(2));
    final profile = tester.widget<DedaProfileVerifiedIdCardSlot>(
      find.byType(DedaProfileVerifiedIdCardSlot).first,
    );
    expect(profile.verifiedOwnedColor, DedaPremiumIdCardColor.gold);
    expect(profile.identifier, '@DEDA-AQPYXJ');
    expect(tester.widget<OutlinedButton>(use('gold')).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('verified remote active style survives closing/reopening UI',
      (tester) async {
    phoneSize(tester, 390, 950);
    var active = DedaPremiumIdCardColor.royal;
    DedaPoint14VerifiedBridge.readRemote = () async => snapshot(
      owned: {DedaPremiumIdCardColor.royal},
      active: active,
    );
    DedaPoint14VerifiedBridge.activateRemote = (color) async {
      active = color;
      return snapshot(
        owned: {DedaPremiumIdCardColor.royal}, active: active);
    };
    await tester.pumpWidget(app(width: 390));
    await tester.pumpAndSettle();
    expect(tester.widget<DedaProfileVerifiedIdCardSlot>(
      find.byType(DedaProfileVerifiedIdCardSlot).first,
    ).verifiedOwnedColor, DedaPremiumIdCardColor.royal);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(app(width: 390));
    await tester.pumpAndSettle();
    expect(tester.widget<DedaProfileVerifiedIdCardSlot>(
      find.byType(DedaProfileVerifiedIdCardSlot).first,
    ).verifiedOwnedColor, DedaPremiumIdCardColor.royal);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unowned or mismatched server snapshot never activates paid decoration',
      (tester) async {
    phoneSize(tester, 360, 900);
    DedaPoint14VerifiedBridge.readRemote = () async => snapshot(
      owned: {DedaPremiumIdCardColor.gold},
      active: DedaPremiumIdCardColor.pink,
    );
    DedaPoint14VerifiedBridge.activateRemote = (color) async =>
        snapshot(owned: {DedaPremiumIdCardColor.gold}, active: color);
    await tester.pumpWidget(app(width: 360));
    await tester.pumpAndSettle();
    final profile = tester.widget<DedaProfileVerifiedIdCardSlot>(
      find.byType(DedaProfileVerifiedIdCardSlot).first,
    );
    expect(profile.verifiedOwnedColor, isNull);
    expect(tester.widget<OutlinedButton>(use('gold')).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('server activation failing reread refuses cosmetic entitlement',
      (tester) async {
    phoneSize(tester, 390, 950);
    var reads = 0;
    DedaPoint14VerifiedBridge.readRemote = () async {
      reads++;
      return snapshot(
        owned: {DedaPremiumIdCardColor.gold},
        active: null,
      );
    };
    DedaPoint14VerifiedBridge.activateRemote = (color) async =>
        snapshot(owned: {DedaPremiumIdCardColor.gold}, active: color);
    await tester.pumpWidget(app(width: 390));
    await tester.pumpAndSettle();
    await tapUse(tester, 'gold');
    expect(reads, greaterThanOrEqualTo(2));
    expect(tester.widget<DedaProfileVerifiedIdCardSlot>(
      find.byType(DedaProfileVerifiedIdCardSlot).first,
    ).verifiedOwnedColor, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switch account removes original paid style immediately',
      (tester) async {
    phoneSize(tester, 390, 950);
    DedaPoint14VerifiedBridge.readRemote = () async => snapshot(
      owned: {DedaPremiumIdCardColor.gold},
      active: DedaPremiumIdCardColor.gold,
    );
    DedaPoint14VerifiedBridge.activateRemote = (color) async =>
        snapshot(owned: {DedaPremiumIdCardColor.gold}, active: color);
    await tester.pumpWidget(app(width: 390));
    await tester.pumpAndSettle();
    expect(tester.widget<DedaProfileVerifiedIdCardSlot>(
      find.byType(DedaProfileVerifiedIdCardSlot).first,
    ).verifiedOwnedColor, DedaPremiumIdCardColor.gold);
    await tester.pumpWidget(app(
      identifier: '@DEDA-SECOND', width: 390,
    ));
    await tester.pumpAndSettle();
    final newProfile = tester.widget<DedaProfileVerifiedIdCardSlot>(
      find.byType(DedaProfileVerifiedIdCardSlot).first,
    );
    expect(newProfile.identifier, '@DEDA-SECOND');
    expect(newProfile.verifiedOwnedColor, isNull);
    expect(tester.widget<OutlinedButton>(use('gold')).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stale pending remote activation cannot decorate new account',
      (tester) async {
    phoneSize(tester, 390, 950);
    final pending = Completer<DedaPoint14VerifiedSnapshot>();
    DedaPoint14VerifiedBridge.readRemote = () async => snapshot(
      owned: {DedaPremiumIdCardColor.gold},
      active: null,
    );
    DedaPoint14VerifiedBridge.activateRemote = (color) => pending.future;
    await tester.pumpWidget(app(width: 390));
    await tester.pumpAndSettle();
    final target = use('gold');
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pump();
    await tester.pumpWidget(app(
      identifier: '@DEDA-SECOND', width: 390,
    ));
    pending.complete(snapshot(
      owned: {DedaPremiumIdCardColor.gold},
      active: DedaPremiumIdCardColor.gold,
    ));
    await tester.pumpAndSettle();
    final profile = tester.widget<DedaProfileVerifiedIdCardSlot>(
      find.byType(DedaProfileVerifiedIdCardSlot).first,
    );
    expect(profile.identifier, '@DEDA-SECOND');
    expect(profile.verifiedOwnedColor, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320, 360 and 430 dp: same 50dp hero slot, no layout errors',
      (tester) async {
    for (final width in <double>[320, 360, 430]) {
      phoneSize(tester, width, 950);
      DedaPoint14VerifiedBridge.readRemote = () async => snapshot(
        owned: {DedaPremiumIdCardColor.diamond},
        active: DedaPremiumIdCardColor.diamond,
      );
      await tester.pumpWidget(app(width: width));
      await tester.pumpAndSettle();
      final slot = find.byType(DedaProfileVerifiedIdCardSlot).first;
      expect(tester.getSize(slot).height, 50);
      expect(tester.takeException(), isNull, reason: '$width dp');
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('no production purchase callback, even with an owned ID design',
      (tester) async {
    phoneSize(tester, 390, 950);
    DedaPoint14VerifiedBridge.readRemote = () async => snapshot(
      owned: {DedaPremiumIdCardColor.gold},
      active: DedaPremiumIdCardColor.gold,
    );
    DedaPoint14VerifiedBridge.activateRemote = (color) async =>
        snapshot(owned: {DedaPremiumIdCardColor.gold}, active: color);
    await tester.pumpWidget(app(width: 390));
    await tester.pumpAndSettle();
    final idBuy = find.byKey(const ValueKey<String>('deda_point12_buy_pink'));
    final btn = tester.widget<OutlinedButton>(idBuy);
    expect(btn.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
