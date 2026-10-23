import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_qa32_active_account_scope.dart';
import 'package:d_iraq_ludo/deda_stage71_free_owned_use_profile.dart';
import 'package:d_iraq_ludo/deda_stability_read_scope.dart';

const _original = '@DEDA-ABC123';
const _otherOriginal = '@DEDA-DEF456';

class _Read {
  _Read(this.uid, this.original);
  final String uid;
  final String original;
  final result = Completer<DedaQa32ActiveAccountIdentity>();

  void succeed([String display = '@DEDA-GOLD']) => result.complete(
    DedaQa32ActiveAccountIdentity(
      uid: uid, originalId: original, displayId: display,
      fixedColor: display == original ? null : 'gold',
    ),
  );
}

/// No Firebase app, credential or network is initialized by these tests.
/// The fake boundary can only observe a session and return a read result.
class _IdentitySource implements DedaQa32IdentitySource {
  @override
  bool ready = true;
  @override
  bool enabled = true;
  String? uid = 'A';
  @override
  String? get currentUid => ready ? uid : null;
  final events = StreamController<String?>.broadcast(sync: true);
  final reads = <_Read>[];
  int subscriptions = 0;

  @override
  Stream<String?> authChanges() {
    subscriptions++;
    return events.stream;
  }

  @override
  Future<DedaQa32ActiveAccountIdentity> readVerified(
      String uid, String original) {
    final read = _Read(uid, original);
    reads.add(read);
    return read.result.future;
  }

  void change(String? next) {
    uid = next;
    events.add(next);
  }
}

Future<void> _show(WidgetTester tester, _IdentitySource source, {
  String original = _original,
  Duration timeout = const Duration(seconds: 12),
}) => tester.pumpWidget(MaterialApp(home: Scaffold(
  body: DedaQa32ActiveAccountScope.forTesting(
    source: source, originalId: original, readTimeout: timeout,
    builder: (context, proof) => Text(proof?.displayId ?? 'safe-fallback'),
  ),
)));

// A fake SDK future first completes the coordinator, then the widget's await
// schedules setState. Flush microtasks and render that explicitly next frame.
// Do not pumpAndSettle: a deliberately pending read has a live deadline timer.
Future<void> _flush(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  test('lifecycle tests require the isolated pilot to be enabled', () {
    expect(dedaStabilityIdentityPilot, isTrue);
  });

  testWidgets('late initialization attaches once and verifies before display', (tester) async {
    final source = _IdentitySource()..ready = false;
    await _show(tester, source);
    expect(source.reads, isEmpty);
    expect(find.text('safe-fallback'), findsOneWidget);
    source.ready = true;
    await _show(tester, source);
    await _flush(tester);
    expect(source.subscriptions, 1);
    expect(source.reads, hasLength(1));
    source.reads.single.succeed();
    await _flush(tester);
    expect(find.text('@DEDA-GOLD'), findsOneWidget);
  });

  testWidgets('cold attach and initial same-UID auth event share one read', (tester) async {
    final source = _IdentitySource();
    await _show(tester, source);
    source.events.add('A');
    source.events.add('A');
    await _flush(tester);
    expect(source.reads, hasLength(1));
    source.reads.single.succeed();
    await _flush(tester);
    expect(find.text('@DEDA-GOLD'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('parent rebuild does not launch another verified read', (tester) async {
    final source = _IdentitySource();
    await _show(tester, source);
    source.reads.single.succeed();
    await _flush(tester);
    await _show(tester, source);
    expect(source.subscriptions, 1);
    expect(source.reads, hasLength(1));
    expect(find.text('@DEDA-GOLD'), findsOneWidget);
  });

  testWidgets('pause rejects old proof and resume starts one fresh generation', (tester) async {
    final source = _IdentitySource();
    await _show(tester, source);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    source.reads.first.succeed('@DEDA-OLD1');
    await _flush(tester);
    expect(find.text('safe-fallback'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    source.events.add('A');
    await _flush(tester);
    expect(source.reads, hasLength(2));
    source.reads.last.succeed('@DEDA-NEW1');
    await _flush(tester);
    expect(find.text('@DEDA-NEW1'), findsOneWidget);
    expect(find.text('@DEDA-OLD1'), findsNothing);
  });

  testWidgets('late initialization on resume performs only one read', (tester) async {
    final source = _IdentitySource()..ready = false;
    await _show(tester, source);
    source.ready = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    source.events.add('A');
    await _flush(tester);
    expect(source.subscriptions, 1);
    expect(source.reads, hasLength(1));
    source.reads.single.succeed();
    await _flush(tester);
    expect(find.text('@DEDA-GOLD'), findsOneWidget);
  });

  testWidgets('UID switch clears previous owner before new proof arrives', (tester) async {
    final source = _IdentitySource();
    await _show(tester, source);
    source.reads.first.succeed('@DEDA-OLD1');
    await _flush(tester);
    source.change('B');
    await _flush(tester);
    expect(find.text('@DEDA-OLD1'), findsNothing);
    expect(find.text('safe-fallback'), findsOneWidget);
    source.reads.last.succeed('@DEDA-NEW1');
    await _flush(tester);
    expect(find.text('@DEDA-NEW1'), findsOneWidget);
  });

  testWidgets('queued A B A events reject first-A result after UID has returned', (tester) async {
    final source = _IdentitySource();
    await _show(tester, source);
    final firstA = source.reads.first;
    // Current state has already returned to A before queued events arrive.
    source.events.add('B');
    source.events.add('A');
    await _flush(tester);
    expect(source.reads, hasLength(3));
    source.reads.last.succeed('@DEDA-NEW1');
    await _flush(tester);
    firstA.succeed('@DEDA-OLD1');
    source.reads[1].succeed('@DEDA-OLD2');
    await _flush(tester);
    expect(find.text('@DEDA-NEW1'), findsOneWidget);
    expect(find.text('@DEDA-OLD1'), findsNothing);
    expect(find.text('@DEDA-OLD2'), findsNothing);
  });

  testWidgets('original account change rejects pending old header result', (tester) async {
    final source = _IdentitySource();
    await _show(tester, source);
    final old = source.reads.single;
    await _show(tester, source, original: _otherOriginal);
    expect(source.reads, hasLength(2));
    source.reads.last.succeed('@DEDA-NEW1');
    old.succeed('@DEDA-OLD1');
    await _flush(tester);
    expect(find.text('@DEDA-NEW1'), findsOneWidget);
    expect(find.text('@DEDA-OLD1'), findsNothing);
  });

  testWidgets('timeout stays fallback without duplicate live request; manual retry recovers', (tester) async {
    final source = _IdentitySource();
    await _show(tester, source, timeout: const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('safe-fallback'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _flush(tester);
    expect(source.reads, hasLength(1));
    source.reads.first.succeed('@DEDA-LATE');
    await _flush(tester);
    expect(find.text('@DEDA-LATE'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _flush(tester);
    expect(source.reads, hasLength(2));
    source.reads.last.succeed('@DEDA-NEW1');
    await _flush(tester);
    expect(find.text('@DEDA-NEW1'), findsOneWidget);
  });

  testWidgets('permission denied is never automatically retried', (tester) async {
    final source = _IdentitySource();
    await _show(tester, source);
    source.reads.first.result.completeError(
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
    );
    await _flush(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(source.reads, hasLength(1));
    expect(find.text('safe-fallback'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one temporary completed read retries and publishes only new proof', (tester) async {
    final source = _IdentitySource();
    await _show(tester, source);
    source.reads.first.result.completeError(
      FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
    );
    await _flush(tester);
    expect(source.reads, hasLength(1));
    await tester.pump(const Duration(milliseconds: 200));
    expect(source.reads, hasLength(2));
    source.reads.last.succeed();
    await _flush(tester);
    expect(find.text('@DEDA-GOLD'), findsOneWidget);
  });

  testWidgets('auth observation errors clear proof without an unhandled exception', (tester) async {
    final source = _IdentitySource();
    await _show(tester, source);
    source.reads.single.succeed();
    await _flush(tester);
    source.events.addError(StateError('fake-auth-observation-error'));
    await _flush(tester);
    expect(find.text('safe-fallback'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(source.reads, hasLength(1));
  });

  testWidgets('dispose cancels subscription and ignores refresh plus late result', (tester) async {
    final source = _IdentitySource();
    await _show(tester, source);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(source.events.hasListener, isFalse);
    source.events.add('B');
    DedaStage71ActiveIdRefresh.changed();
    source.reads.single.succeed();
    await _flush(tester);
    expect(source.reads, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('unverified result never displays an alias for a different UID', (tester) async {
    final source = _IdentitySource();
    await _show(tester, source);
    source.reads.single.result.complete(const DedaQa32ActiveAccountIdentity(
      uid: 'different-user', originalId: _original,
      displayId: '@DEDA-FAKE', fixedColor: 'gold',
    ));
    await _flush(tester);
    expect(find.text('safe-fallback'), findsOneWidget);
    expect(find.text('@DEDA-FAKE'), findsNothing);
  });

  testWidgets('disabled feature and absent session never start reads', (tester) async {
    final source = _IdentitySource()..enabled = false;
    await _show(tester, source);
    expect(source.reads, isEmpty);
    source.enabled = true;
    source.change(null);
    await _flush(tester);
    expect(source.reads, isEmpty);
    expect(find.text('safe-fallback'), findsOneWidget);
  });
}
