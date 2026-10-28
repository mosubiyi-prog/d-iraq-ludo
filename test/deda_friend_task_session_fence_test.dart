import 'dart:async';

import 'package:d_iraq_ludo/deda_task_signal_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const original = '07701234567';
  const other = '07707654321';
  const uidOriginal = 'original_firebase_uid_A';
  const uidOther = 'second_firebase_uid_B';

  late String currentAccount;
  late String? currentUid;
  late int claimed;

  setUp(() {
    DedaTaskSignalBridge.revoke();
    currentAccount = original;
    currentUid = uidOriginal;
    claimed = 0;
    DedaTaskSignalBridge.bind(
      accountKey: original,
      readCurrentAccount: () => currentAccount,
      onFriendAccepted: () async {
        claimed++;
      },
    );
  });

  tearDown(DedaTaskSignalBridge.revoke);

  Future<void> report({String source = uidOriginal}) =>
      DedaTaskSignalBridge.friendAccepted(
        originatingUid: source,
        readCurrentUid: () => currentUid,
      );

  test('actual current accepted-friend signal is forwarded once', () async {
    await report();
    expect(claimed, 1);
  });

  test('old social subscription after phone/account switch cannot credit', () async {
    currentAccount = other;
    currentUid = uidOther;
    await report();
    expect(claimed, 0);
  });

  test('a same-uid PIN account switch cannot trigger stale bound callback',
      () async {
    currentAccount = other;
    await report();
    expect(claimed, 0);
  });

  test('wrong, missing or empty Firebase UID cannot complete a task', () async {
    await report(source: uidOther);
    await report(source: '');
    currentUid = null;
    await report();
    expect(claimed, 0);
  });

  test('logout revokes a pending old-account completion signal', () async {
    DedaTaskSignalBridge.revoke();
    await report();
    expect(claimed, 0);
  });

  test('new account bind cannot inherit old account friendship signal',
      () async {
    DedaTaskSignalBridge.revoke();
    currentAccount = other;
    currentUid = uidOther;
    DedaTaskSignalBridge.bind(
      accountKey: other,
      readCurrentAccount: () => currentAccount,
      onFriendAccepted: () async { claimed++; },
    );
    await report();
    expect(claimed, 0);
    await report(source: uidOther);
    expect(claimed, 1);
  });

  test('malformed account keys cannot bind rewards', () async {
    DedaTaskSignalBridge.bind(
      accountKey: 'bad-account',
      readCurrentAccount: () => 'bad-account',
      onFriendAccepted: () async { claimed++; },
    );
    await report();
    expect(claimed, 0);
  });

  test('task reporting failure never breaks accepted friendship', () async {
    DedaTaskSignalBridge.bind(
      accountKey: original,
      readCurrentAccount: () => original,
      onFriendAccepted: () async {
        throw StateError('task persistence unavailable');
      },
    );
    await expectLater(report(), completes);
  });

  test('account source callback exception cannot credit reward', () async {
    DedaTaskSignalBridge.bind(
      accountKey: original,
      readCurrentAccount: () => throw StateError('signed out'),
      onFriendAccepted: () async { claimed++; },
    );
    await report();
    expect(claimed, 0);
  });

  test('delayed completion starts only for the right account and UID',
      () async {
    final completed = Completer<void>();
    DedaTaskSignalBridge.bind(
      accountKey: original,
      readCurrentAccount: () => currentAccount,
      onFriendAccepted: () => completed.future,
    );
    final pending = report();
    DedaTaskSignalBridge.revoke();
    currentAccount = other;
    currentUid = uidOther;
    completed.complete();
    await pending;
    await report();
    expect(claimed, 0);
  });
}
