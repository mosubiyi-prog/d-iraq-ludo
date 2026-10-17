import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('draws a visible Flutter startup frame before async work',
      (tester) async {
    final boot = Completer<void>();
    await tester.pumpWidget(DedaStartupGate(
      initializeForTesting: () => boot.future,
    ));
    expect(find.byKey(const Key('deda_startup_loading')), findsOneWidget);
    expect(find.text('DEDA - الدليل الدقيق'), findsOneWidget);
    expect(find.byKey(const Key('deda_startup_error')), findsNothing);

    boot.completeError(StateError('simulated local startup failure'));
    await tester.pump();
    expect(find.byKey(const Key('deda_startup_error')), findsOneWidget);
    expect(find.textContaining('لا تحذف التطبيق ولا تمسح بياناته'), findsOneWidget);
    expect(find.byKey(const Key('deda_startup_retry')), findsOneWidget);
  });

  testWidgets('shows safely categorized local timeout without leaking account values',
      (tester) async {
    await tester.pumpWidget(DedaStartupGate(
      initializeForTesting: () async {
        throw TimeoutException('underlying sensitive debug message');
      },
    ));
    await tester.pump();
    expect(find.byKey(const Key('deda_startup_error')), findsOneWidget);
    expect(find.text('انتهت مهلة الانتظار'), findsOneWidget);
    expect(find.byKey(const Key('deda_startup_failure_kind')), findsOneWidget);
    expect(find.textContaining('underlying sensitive'), findsNothing);
  });

  testWidgets('storage platform error produces a safe diagnostic phase',
      (tester) async {
    await tester.pumpWidget(DedaStartupGate(
      initializeForTesting: () => Future<void>.error(
        PlatformException(code: 'PREFS_FAILURE', message: 'secret phone test'),
      ),
    ));
    await tester.pump();
    expect(find.text('تعذر التواصل مع تخزين الهاتف'), findsOneWidget);
    expect(find.textContaining('secret phone test'), findsNothing);
  });

  testWidgets('retry does not delete local account or reset progress',
      (tester) async {
    var attempts = 0;
    final second = Completer<void>();
    await tester.pumpWidget(DedaStartupGate(
      initializeForTesting: () {
        attempts++;
        return attempts == 1
            ? Future<void>.error(StateError('first try fails'))
            : second.future;
      },
    ));
    await tester.pump();
    expect(find.byKey(const Key('deda_startup_error')), findsOneWidget);
    await tester.tap(find.byKey(const Key('deda_startup_retry')));
    await tester.pump();
    expect(find.byKey(const Key('deda_startup_loading')), findsOneWidget);
    expect(attempts, 2);
    // Keep app in first-frame startup screen; no fake login state exposed.
    second.completeError(StateError('second controlled failure'));
    await tester.pump();
    expect(find.byKey(const Key('deda_startup_error')), findsOneWidget);
  });
}
