import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_session_transition_gate.dart';

void main() {
  test('verified owner lane can safely exceed ordinary timeout', () async {
    final gate = DedaSessionTransitionGate(
      timeout: const Duration(milliseconds: 15));
    final value = await gate.run<int>(
      key: Object(),
      kind: DedaSessionTransitionKind.ownerLogin,
      origin: DedaSessionTransitionOrigin.userAction,
      currentAuthKind: () => DedaSessionAuthKind.anonymous,
      isCurrent: () => true,
      verifiedOwnerLoginMaxWait: const Duration(seconds: 2),
      action: (permit) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        permit.checkCurrent();
        return 7;
      },
    );
    expect(value, 7);
    expect(gate.diagnostics['timedOut'], 0);
  });

  test('admin, background and excessive owner timeout override rejected', () async {
    final gate = DedaSessionTransitionGate(
      timeout: const Duration(milliseconds: 50));
    Future<void> attempt(
        DedaSessionTransitionKind kind,
        DedaSessionTransitionOrigin origin,
        Duration maxWait) async {
      await expectLater(gate.run<void>(
        key: Object(), kind: kind, origin: origin,
        currentAuthKind: () => DedaSessionAuthKind.anonymous,
        isCurrent: () => true,
        verifiedOwnerLoginMaxWait: maxWait,
        action: (permit) async {},
      ), throwsArgumentError);
    }
    await attempt(DedaSessionTransitionKind.adminLogin,
        DedaSessionTransitionOrigin.userAction,
        const Duration(seconds: 60));
    await attempt(DedaSessionTransitionKind.ownerLogin,
        DedaSessionTransitionOrigin.background,
        const Duration(seconds: 60));
    await attempt(DedaSessionTransitionKind.ownerLogin,
        DedaSessionTransitionOrigin.userAction,
        const Duration(seconds: 91));
    await attempt(DedaSessionTransitionKind.ownerLogin,
        DedaSessionTransitionOrigin.userAction,
        const Duration(milliseconds: 1));
  });
}
