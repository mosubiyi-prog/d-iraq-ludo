import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/deda_protected_section_entry.dart';
import '../lib/deda_auth_session_runtime.dart';
import '../lib/deda_session_transition_gate.dart';
import '../lib/main.dart' as app;

class EntryHarness {
  EntryHarness({Duration timeout = const Duration(seconds: 12)}) {
    controller = DedaAuthSessionController(current: () => live, timeout: timeout);
  }
  DedaAuthSnapshot live = const DedaAuthSnapshot('owner', DedaSessionAuthKind.anonymous, 1);
  String account = '07700000000';
  int epoch = 1;
  bool mounted = true;
  late final DedaAuthSessionController controller;
  Future<T> enter<T>(Future<T> Function() action) => runDedaProtectedSectionEntry(
    controller: controller, accountKey: () => account,
    accountEpoch: () => epoch, isMounted: () => mounted, prepare: action,
  );
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('section preparation delegates its SDK helpers through the existing complete lane', () async {
    final h = EntryHarness();
    expect(await h.enter(() => h.controller.wait(() async => 'verified result')), 'verified result');
  });
  test('two section entries cannot launch competing session mutations', () async {
    final h = EntryHarness(), hold = Completer<String>();
    var calls = 0;
    final first = h.enter(() { calls++; return hold.future; });
    await expectLater(h.enter(() async { calls++; return 'duplicate'; }),
      throwsA(isA<DedaSessionTransitionBusy>()));
    expect(calls, 1); hold.complete('owner result'); expect(await first, 'owner result');
  });
  test('admin session is preserved and automatic owner preparation never runs', () async {
    final h = EntryHarness(); h.live = const DedaAuthSnapshot('manager', DedaSessionAuthKind.authenticated, 2);
    var calls = 0;
    await expectLater(h.enter(() async { calls++; return 'bad'; }), throwsA(isA<DedaSessionTransitionDenied>()));
    expect(calls, 0); expect(h.live.uid, 'manager');
  });
  test('missing SDK session still requires the original owner proof and cannot fabricate a result', () async {
    final h = EntryHarness(); h.live = const DedaAuthSnapshot(null, DedaSessionAuthKind.none, 2);
    var calls = 0;
    await expectLater(h.enter<String>(() async { calls++; throw StateError('owner proof required'); }), throwsStateError);
    expect(calls, 1); expect(h.live.kind, DedaSessionAuthKind.none);
  });
  test('A to B to A selection invalidates the first section result', () async {
    final h = EntryHarness(), hold = Completer<String>();
    final first = h.enter(() => hold.future);
    final check = expectLater(first, throwsA(isA<DedaStaleSessionTransition>()));
    h.account = '07700000001'; h.epoch++;
    h.account = '07700000000'; h.epoch++;
    hold.complete('obsolete'); await check;
  });
  test('closed screen cannot publish a late prepared session', () async {
    final h = EntryHarness(), hold = Completer<String>();
    final first = h.enter(() => hold.future);
    final check = expectLater(first, throwsA(isA<DedaStaleSessionTransition>()));
    h.mounted = false; hold.complete('obsolete'); await check;
  });
  test('timeout is visible but keeps the original live operation from being duplicated', () async {
    final h = EntryHarness(timeout: const Duration(milliseconds: 10)), hold = Completer<String>();
    var calls = 0, followupWrites = 0;
    final first = h.enter(() async {
      calls++;
      await h.controller.wait(() => hold.future);
      followupWrites++; return 'late';
    });
    await expectLater(first, throwsA(isA<TimeoutException>()));
    await expectLater(h.enter(() async { calls++; return 'duplicate'; }), throwsA(isA<DedaSessionTransitionBusy>()));
    hold.complete('late'); await Future<void>.delayed(Duration.zero);
    expect(calls, 1); expect(followupWrites, 0);
  });
  test('completed failure allows an explicit later attempt without automatic retry', () async {
    final h = EntryHarness(); var calls = 0;
    await expectLater(h.enter<String>(() async { calls++; throw StateError('failed'); }), throwsStateError);
    expect(calls, 1);
    expect(await h.enter(() async { calls++; return 'verified'; }), 'verified'); expect(calls, 2);
  });
  for (final page in ['friends', 'requests']) {
    testWidgets('actual $page page exits failed entry to a retry control instead of permanent loading', (tester) async {
      SharedPreferences.setMockInitialValues({});
      app.DedaPreferences.isLoggedIn = false; app.DedaPreferences.phone = '';
      await tester.pumpWidget(MaterialApp(home: page == 'friends'
        ? app.DedaFriendsPage(onAddFriend: () {}) : const app.DedaFriendRequestsPage()));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
