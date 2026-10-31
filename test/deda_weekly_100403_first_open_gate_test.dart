import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/deda_weekly_account_view_gate.dart';

void main() {
  testWidgets('empty anonymous UID on first tap is NOT a logout; authenticates later',
      (tester) async {
    final auth = StreamController<Object?>.broadcast();
    addTearDown(auth.close);
    var account = '07712345678';
    String? uid;
    var now = DateTime.utc(2026, 10, 31, 1); // Baghdad 04:00
    await tester.pumpWidget(MaterialApp(
      home: DedaWeeklyAccountViewGate(
        readCanonicalAccount: () => account,
        readSessionUid: () => uid,
        authEvents: auth.stream,
        startsAt: DateTime.utc(2026, 10, 31, 3),
        clock: () => now,
        builder: (_, __, ___) => const Scaffold(
          body: Center(child: Text('الدوري المباشر')),
        ),
      ),
    ));
    expect(find.text('جاري تهيئة حساب الدوري...'), findsOneWidget);
    expect(find.textContaining('تغيّر الحساب'), findsNothing);

    // Firebase first reports auth readiness without a signed-in user.
    auth.add(null);
    await tester.pump();
    expect(find.textContaining('تغيّر الحساب'), findsNothing);

    // Anonymous session hydrates moments later. Same screen must recover.
    uid = 'anonymousFirebaseUid123';
    auth.add('signed-in');
    await tester.pump();
    expect(find.text('سيبدأ الدوري بعد'), findsOneWidget);
    expect(find.text('02:00:00'), findsOneWidget);
    expect(find.byKey(const Key('deda_weekly_prestart_countdown')),
        findsOneWidget);
    expect(find.text('الدوري المباشر'), findsNothing);

    now = DateTime.utc(2026, 10, 31, 3);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('الدوري المباشر'), findsOneWidget);
    expect(find.textContaining('تغيّر الحساب'), findsNothing);
  });

  testWidgets('once identity bound, switching DEDA account hides old league',
      (tester) async {
    final auth = StreamController<Object?>.broadcast();
    addTearDown(auth.close);
    var account = '07712345678';
    var uid = 'firebaseUid1111111';
    await tester.pumpWidget(MaterialApp(
      home: DedaWeeklyAccountViewGate(
        readCanonicalAccount: () => account,
        readSessionUid: () => uid,
        authEvents: auth.stream,
        builder: (_, __, ___) => const Scaffold(
            body: Text('PRIVATE_LEAGUE_SHOWN')),
      ),
    ));
    expect(find.text('PRIVATE_LEAGUE_SHOWN'), findsNothing);
    auth.add('initialized');
    await tester.pump();
    expect(find.text('PRIVATE_LEAGUE_SHOWN'), findsOneWidget);
    account = '07707654321';
    uid = 'firebaseUid2222222';
    auth.add('new-user');
    await tester.pump();
    expect(find.text('PRIVATE_LEAGUE_SHOWN'), findsNothing);
    expect(find.textContaining('تم تبديل الحساب'), findsOneWidget);
  });
}
