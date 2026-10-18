import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_point12_checkout_fixture.dart';

void main() {
  Widget fixture({
    DedaIdCardPurchaseGateway? purchase,
    DedaIdCardOwnedRefresh? refresh,
    Set<DedaPremiumIdCardColor> owned = const <DedaPremiumIdCardColor>{},
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Center(
            child: SizedBox(
              width: 320,
              child: DedaPremiumIdCardsManagementPanel(
                identifier: '@DEDA-AQPYXJ',
                serverVerifiedOwnedColors: owned,
                verifiedActiveColor: null,
                onActivateVerified: null,
                onPurchaseVerified: purchase,
                refreshVerifiedOwnership: refresh,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Finder buy(String color) =>
      find.byKey(ValueKey<String>('deda_point12_buy_' + color));

  Future<void> openGoldDialog(WidgetTester tester) async {
    final key = buy('gold');
    await tester.ensureVisible(key);
    await tester.pumpAndSettle();
    await tester.tap(key);
    await tester.pumpAndSettle();
  }

  DedaIdCardPurchaseReceipt confirmed(DedaPremiumIdCardColor color, {
    int charged = 5000,
    bool alreadyOwned = false,
    bool confirmedByServer = true,
  }) =>
      DedaIdCardPurchaseReceipt(
        transactionId: 'server-ledger-transaction',
        color: color,
        diamondsCharged: charged,
        serverConfirmed: confirmedByServer,
        alreadyOwned: alreadyOwned,
      );

  testWidgets('no trusted server gateway means NO clickable paid checkout',
      (tester) async {
    await tester.pumpWidget(fixture());
    for (final color in DedaPremiumIdCardColor.values) {
      final button = tester.widget<OutlinedButton>(buy(color.name));
      expect(button.onPressed, isNull);
    }
    expect(find.text('@DEDA-AQPYXJ'), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel confirmation triggers zero gateway calls or charges',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(fixture(
      purchase: (color, requestId) async {
        calls++;
        return confirmed(color);
      },
      refresh: () async => <DedaPremiumIdCardColor>{DedaPremiumIdCardColor.gold},
    ));
    await openGoldDialog(tester);
    expect(find.textContaining('5,000 ماسة'), findsWidgets);
    expect(find.textContaining('سعر البطاقة منفصل'), findsOneWidget);
    await tester.tap(find.byKey(const Key('deda_point12_cancel_purchase')));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmed receipt plus verified ownership unlocks owned state once',
      (tester) async {
    var calls = 0;
    var refreshes = 0;
    final keys = <String>[];
    await tester.pumpWidget(fixture(
      purchase: (color, requestId) async {
        calls++;
        keys.add(requestId);
        return confirmed(color);
      },
      refresh: () async {
        refreshes++;
        return <DedaPremiumIdCardColor>{DedaPremiumIdCardColor.gold};
      },
    ));
    await openGoldDialog(tester);
    await tester.tap(find.byKey(const Key('deda_point12_confirm_purchase')));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(refreshes, 1);
    expect(keys.single, isNotEmpty);
    expect(tester.widget<OutlinedButton>(buy('gold')).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(buy('diamond')).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('double-tap/async pending request cannot issue second payment',
      (tester) async {
    final pending = Completer<DedaIdCardPurchaseReceipt>();
    var calls = 0;
    await tester.pumpWidget(fixture(
      purchase: (color, requestId) {
        calls++;
        return pending.future;
      },
      refresh: () async => <DedaPremiumIdCardColor>{DedaPremiumIdCardColor.gold},
    ));
    await openGoldDialog(tester);
    await tester.tap(find.byKey(const Key('deda_point12_confirm_purchase')));
    await tester.pump();
    expect(calls, 1);
    expect(tester.widget<OutlinedButton>(buy('gold')).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(buy('diamond')).onPressed, isNull);
    pending.complete(confirmed(DedaPremiumIdCardColor.gold));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unverified receipt cannot grant ownership despite callback',
      (tester) async {
    await tester.pumpWidget(fixture(
      purchase: (color, key) async => confirmed(color, charged: 4999),
      refresh: () async => <DedaPremiumIdCardColor>{DedaPremiumIdCardColor.gold},
    ));
    await openGoldDialog(tester);
    await tester.tap(find.byKey(const Key('deda_point12_confirm_purchase')));
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(buy('gold')).onPressed, isNotNull);
    expect(find.textContaining('تعذّر التحقق'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('receipt with no server entitlement cannot grant ownership',
      (tester) async {
    await tester.pumpWidget(fixture(
      purchase: (color, requestId) async => confirmed(color),
      refresh: () async => <DedaPremiumIdCardColor>{},
    ));
    await openGoldDialog(tester);
    await tester.tap(find.byKey(const Key('deda_point12_confirm_purchase')));
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(buy('gold')).onPressed, isNotNull);
    expect(find.textContaining('تعذّر التحقق'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('already-owned remote receipt costs zero and never buys again',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(fixture(
      purchase: (color, requestId) async {
        calls++;
        return confirmed(color, charged: 0, alreadyOwned: true);
      },
      refresh: () async => <DedaPremiumIdCardColor>{DedaPremiumIdCardColor.gold},
    ));
    await openGoldDialog(tester);
    await tester.tap(find.byKey(const Key('deda_point12_confirm_purchase')));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(tester.widget<OutlinedButton>(buy('gold')).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
