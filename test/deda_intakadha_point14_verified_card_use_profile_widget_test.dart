import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_point14_fixture.dart';

void main() {
  const id = '@DEDA-AQPYXJ';
  String uid = 'verified_test_uid';
  Set<DedaPremiumIdCardColor> owned = {DedaPremiumIdCardColor.gold};
  DedaPremiumIdCardColor? active;
  var reads = 0;
  var writes = 0;
  var rejectActivation = false;

  DedaVerifiedIdCardSnapshot server() => DedaVerifiedIdCardSnapshot(
        accountUid: uid,
        publicId: id,
        ownedColors: Set.of(owned),
        activeColor: active,
        serverConfirmed: true,
      );

  Widget app() => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                DedaVerifiedIdCardsAccountSection(
                  identifier: id,
                ),
                DedaVerifiedIdCardsProfileSlot(
                  identifier: id,
                  onCopy: () {},
                  width: 285,
                  compact: true,
                ),
              ],
            ),
          ),
        ),
      );

  Finder use(String color) =>
      find.byKey(ValueKey<String>('deda_intakadha_point7_use_' + color));

  setUp(() {
    uid = 'verified_test_uid';
    owned = {DedaPremiumIdCardColor.gold};
    active = null;
    reads = 0;
    writes = 0;
    rejectActivation = false;
    DedaVerifiedIdCardsState.clearForLogout();
    DedaVerifiedIdCardsBridge.authenticatedUid = () => uid;
    DedaVerifiedIdCardsBridge.readFromServer = () async {
      reads++;
      return server();
    };
    DedaVerifiedIdCardsBridge.activateOnServer = (color) async {
      writes++;
      if (rejectActivation) throw StateError('server-rejected');
      active = color;
      return server();
    };
  });
  tearDown(() {
    DedaVerifiedIdCardsBridge.authenticatedUid = null;
    DedaVerifiedIdCardsBridge.readFromServer = null;
    DedaVerifiedIdCardsBridge.activateOnServer = null;
    DedaVerifiedIdCardsState.clearForLogout();
  });

  testWidgets('verified purchase enables Use and appears in same 50px profile slot',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(reads, greaterThan(0));
    expect(tester.widget<OutlinedButton>(use('gold')).onPressed, isNotNull);
    expect(tester.widget<OutlinedButton>(use('pink')).onPressed, isNull);
    // Before use: four store previews only; profile defaults to original ID chip.
    expect(find.byType(DedaPremiumIdCard), findsNWidgets(4));
    await tester.ensureVisible(use('gold'));
    await tester.tap(use('gold'));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(active, DedaPremiumIdCardColor.gold);
    expect(find.byType(DedaPremiumIdCard), findsNWidgets(5));
    expect(find.text(id), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed use keeps previous original profile chip', (tester) async {
    rejectActivation = true;
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.ensureVisible(use('gold'));
    await tester.tap(use('gold'));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(find.byType(DedaPremiumIdCard), findsNWidgets(4));
    expect(find.textContaining('التصميم السابق محفوظ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unverified account or missing bridge never enables use', (tester) async {
    DedaVerifiedIdCardsBridge.readFromServer = null;
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(use('gold')).onPressed, isNull);
    expect(find.byType(DedaPremiumIdCard), findsNWidgets(4));
    expect(writes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('different login cannot inherit prior owner card', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.ensureVisible(use('gold'));
    await tester.tap(use('gold'));
    await tester.pumpAndSettle();
    expect(find.byType(DedaPremiumIdCard), findsNWidgets(5));
    uid = 'different_user';
    DedaVerifiedIdCardsBridge.readFromServer = null;
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byType(DedaPremiumIdCard), findsNWidgets(4));
    expect(tester.widget<OutlinedButton>(use('gold')).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a fake remotely active unowned style is rejected', (tester) async {
    DedaVerifiedIdCardsBridge.readFromServer = () async =>
        const DedaVerifiedIdCardSnapshot(
          accountUid: 'verified_test_uid',
          publicId: id,
          ownedColors: {DedaPremiumIdCardColor.gold},
          activeColor: DedaPremiumIdCardColor.pink,
          serverConfirmed: true,
        );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(use('gold')).onPressed, isNull);
    expect(find.byType(DedaPremiumIdCard), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });
}
