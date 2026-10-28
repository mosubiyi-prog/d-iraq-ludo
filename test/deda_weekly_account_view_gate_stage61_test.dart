import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_weekly_account_view_gate.dart';

void main() {
  late StreamController<Object?> auth;
  late ValueNotifier<int> xp;
  late String account;
  late String? uid;
  int buildCalls = 0;

  setUp(() {
    auth = StreamController<Object?>.broadcast(sync: true);
    xp = ValueNotifier<int>(0);
    account = '07701234567';
    uid = 'stage61_legacy_anon_uid_original';
    buildCalls = 0;
  });
  tearDown(() async {
    await auth.close();
    xp.dispose();
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: DedaWeeklyAccountViewGate(
        readCanonicalAccount: () => account,
        readSessionUid: () => uid,
        authEvents: auth.stream,
        refreshSignal: xp,
        builder: (_, capturedAccount, stillCurrent) {
          buildCalls++;
          return Scaffold(
            body: Column(children: [
              Text(capturedAccount, key: const Key('scoped_owner_only')),
              Text(stillCurrent() ? 'SAME_ACCOUNT' : 'REVOKED'),
            ]),
          );
        },
      ),
    ));
  }

  testWidgets('01: original anonymous UID + canonical account display scope works', (tester) async {
    await open(tester);
    expect(find.text('07701234567'), findsOneWidget);
    expect(find.text('SAME_ACCOUNT'), findsOneWidget);
    expect(find.byKey(const Key('deda_weekly_account_scope_revoked')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('02: switching to different canonical phone account permanently revokes old data', (tester) async {
    await open(tester);
    account = '07709998877';
    xp.value++;
    await tester.pump();
    expect(find.byKey(const Key('scoped_owner_only')), findsNothing);
    expect(find.byKey(const Key('deda_weekly_account_scope_revoked')), findsOneWidget);
    account = '07701234567';
    xp.value++;
    await tester.pump();
    expect(find.byKey(const Key('scoped_owner_only')), findsNothing);
  });

  testWidgets('03: Firebase anonymous UID switch invalidates even same phone', (tester) async {
    await open(tester);
    uid = 'stage61_second_firebase_uid_no_auth';
    auth.add(null);
    await tester.pump();
    expect(find.byKey(const Key('deda_weekly_account_scope_revoked')), findsOneWidget);
    expect(find.byKey(const Key('scoped_owner_only')), findsNothing);
  });

  testWidgets('04: logout revokes old account even when user later signs back in', (tester) async {
    await open(tester);
    final originalUid = uid;
    uid = null;
    auth.add(null);
    await tester.pump();
    expect(find.byKey(const Key('deda_weekly_account_scope_revoked')), findsOneWidget);
    uid = originalUid;
    auth.add(null);
    await tester.pump();
    expect(find.byKey(const Key('scoped_owner_only')), findsNothing);
  });

  testWidgets('05: missing UID refuses account view and never builds private data', (tester) async {
    uid = null;
    await open(tester);
    expect(buildCalls, 0);
    expect(find.byKey(const Key('deda_weekly_account_scope_revoked')), findsOneWidget);
  });

  testWidgets('06: invalid canonical phone refuses account view', (tester) async {
    account = 'bad account';
    await open(tester);
    expect(buildCalls, 0);
    expect(find.byKey(const Key('deda_weekly_account_scope_revoked')), findsOneWidget);
  });

  testWidgets('07: exceptions reading source account fail closed, no old scores', (tester) async {
    await tester.pumpWidget(MaterialApp(home: DedaWeeklyAccountViewGate(
      readCanonicalAccount: () => throw StateError('device logout'),
      readSessionUid: () => uid,
      authEvents: auth.stream,
      builder: (_, __, ___) => const Text('SHOULD_NOT_SHOW'),
    )));
    expect(find.text('SHOULD_NOT_SHOW'), findsNothing);
    expect(find.byKey(const Key('deda_weekly_account_scope_revoked')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('08: refresh on same account never creates XP or fake ranks', (tester) async {
    await open(tester);
    final initialBuilds = buildCalls;
    xp.value++;
    await tester.pump();
    expect(buildCalls, greaterThanOrEqualTo(initialBuilds));
    expect(find.text('SAME_ACCOUNT'), findsOneWidget);
    expect(find.byKey(const Key('deda_weekly_account_scope_revoked')), findsNothing);
  });
}
