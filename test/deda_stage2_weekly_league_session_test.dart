import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_weekly_account_view_gate.dart';
import 'package:d_iraq_ludo/deda_weekly_firestore_direct_bridge.dart';

void main() {
  test('ranking bound never treats first 100 as complete if more exist', () {
    expect(DedaWeeklyFirestoreDirectBridge.completeRankingSnapshot(101), isTrue);
    expect(DedaWeeklyFirestoreDirectBridge.completeRankingSnapshot(5000), isTrue);
    expect(DedaWeeklyFirestoreDirectBridge.completeRankingSnapshot(5001), isFalse);
  });
  testWidgets('same UID and phone after account A-B-A cannot revive old league', (tester) async {
    final events = StreamController<Object?>.broadcast();
    final accountEpoch = ValueNotifier<int>(0);
    addTearDown(accountEpoch.dispose);
    addTearDown(events.close);
    var authEpoch = 0;
    var account = '07700000000';
    var uid = 'original-firebase-uid';
    bool Function()? current;
    await tester.pumpWidget(MaterialApp(home: DedaWeeklyAccountViewGate(
      readCanonicalAccount: () => account, readSessionUid: () => uid,
      readAccountEpoch: () => accountEpoch.value, readAuthEpoch: () => authEpoch,
      accountChanges: accountEpoch, authEvents: events.stream,
      builder: (_, key, guard) { current = guard; return const Text('league-ready'); },
    )));
    events.add(uid);
    await tester.pump();
    expect(find.text('league-ready'), findsOneWidget);
    expect(current!(), isTrue);
    account = '07800000000';
    accountEpoch.value++;
    account = '07700000000';
    accountEpoch.value++;
    await tester.pump();
    expect(current!(), isFalse);
    expect(find.text('league-ready'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('auth epoch A-B-A invalidates before next screen rebuild', (tester) async {
    final events = StreamController<Object?>.broadcast();
    addTearDown(events.close);
    var authEpoch = 0;
    bool Function()? current;
    await tester.pumpWidget(MaterialApp(home: DedaWeeklyAccountViewGate(
      readCanonicalAccount: () => '07700000000',
      readSessionUid: () => 'original-firebase-uid',
      readAuthEpoch: () => authEpoch, authEvents: events.stream,
      builder: (_, key, guard) { current = guard; return const Text('league-ready'); },
    )));
    events.add('original-firebase-uid');
    await tester.pump();
    expect(current!(), isTrue);
    authEpoch += 2;
    expect(current!(), isFalse);
    events.add('original-firebase-uid');
    await tester.pump();
    expect(find.text('league-ready'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
