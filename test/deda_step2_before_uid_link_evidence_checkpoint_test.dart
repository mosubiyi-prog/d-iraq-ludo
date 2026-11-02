import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_step2_before_uid_link_evidence_checkpoint.dart';

const account = '9647712345678';
const original = 'original_100340_uid';
const capture = 'original_phone_capture_00000001';

DedaStep2PreLinkEvidenceReceipt receipt({
  String uid = original, bool progress = true, bool purchases = true,
}) => DedaStep2PreLinkEvidenceReceipt(
  captureId: capture, sourceUid: uid,
  progressReadback: progress, purchaseReadback: purchases,
);

void main() {
  test('pre-link archive is disabled in normal builds', () async {
    var calls = 0;
    final gate = DedaStep2PreLinkCheckpoint(
      archive: (_, __) async { calls++; return receipt(); },
      currentUid: () => original,
      currentIsAnonymous: () => true,
    );
    expect(dedaStep2PreLinkEvidenceCheckpointEnabled, isFalse);
    await expectLater(gate.run(accountKey: account, originalUid: original),
        throwsA(isA<DedaStep2PreLinkCheckpointHold>()));
    expect(calls, 0);
  });

  test('private staged source permits UID linking only after both readbacks', () async {
    var calls = 0;
    final gate = DedaStep2PreLinkCheckpoint(
      enabled: true,
      archive: (a, u) async {
        calls++;
        expect(a, account);
        expect(u, original);
        return receipt();
      },
      currentUid: () => original,
      currentIsAnonymous: () => true,
    );
    final result = await gate.run(accountKey: account, originalUid: original);
    expect(calls, 1);
    expect(result.progressReadback, isTrue);
    expect(result.purchaseReadback, isTrue);
    expect(result.fullAccountRestored, isFalse);
    expect(result.canRestoreDiamonds, isFalse);
    expect(result.canRestoreXp, isFalse);
    expect(result.canReissuePurchases, isFalse);
    expect(result.allowPhoneCutover, isFalse);
  });

  test('source absence, purchase failure, wrong UID all prevent linking', () async {
    for (final bad in [
      receipt(progress: false),
      receipt(purchases: false),
      receipt(uid: 'not_original'),
      const DedaStep2PreLinkEvidenceReceipt(
          captureId:'', sourceUid:original,
          progressReadback:true,purchaseReadback:true),
    ]) {
      final gate = DedaStep2PreLinkCheckpoint(
        enabled:true, archive: (_, __) async => bad,
        currentUid: () => original, currentIsAnonymous: () => true,
      );
      await expectLater(gate.run(accountKey:account,originalUid:original),
          throwsA(isA<DedaStep2PreLinkCheckpointHold>()));
    }
  });

  test('stale identity and wrong account never start an archive', () async {
    for (final uid in ['foreign_uid', null]) {
      var calls = 0;
      final gate = DedaStep2PreLinkCheckpoint(
        enabled:true,
        archive: (_, __) async { calls++; return receipt(); },
        currentUid: () => uid,
        currentIsAnonymous: () => true,
      );
      await expectLater(gate.run(accountKey:account,originalUid:original),
          throwsA(isA<DedaStep2PreLinkCheckpointHold>()));
      expect(calls,0);
    }
    final gate = DedaStep2PreLinkCheckpoint(
      enabled:true,
      archive: (_, __) async => receipt(),
      currentUid: () => original,
      currentIsAnonymous: () => false,
    );
    await expectLater(gate.run(accountKey:account,originalUid:original),
        throwsA(isA<DedaStep2PreLinkCheckpointHold>()));
    await expectLater(gate.run(accountKey:'not-a-phone',originalUid:original),
        throwsA(isA<DedaStep2PreLinkCheckpointHold>()));
  });

  test('Firebase identity changes DURING the network archive must abort link', () async {
    var current = original;
    final completion = Completer<DedaStep2PreLinkEvidenceReceipt>();
    final gate = DedaStep2PreLinkCheckpoint(
      enabled:true,
      archive: (_, __) => completion.future,
      currentUid: () => current,
      currentIsAnonymous: () => true,
    );
    final pending = gate.run(accountKey:account,originalUid:original);
    current = 'different_account';
    completion.complete(receipt());
    await expectLater(pending,throwsA(isA<DedaStep2PreLinkCheckpointHold>()));
  });

  test('anonymous session changes to provider during archive must abort link', () async {
    var anonymous = true;
    final gate = DedaStep2PreLinkCheckpoint(
      enabled:true,
      archive: (_, __) async {
        anonymous=false;
        return receipt();
      },
      currentUid: () => original,
      currentIsAnonymous: () => anonymous,
    );
    await expectLater(gate.run(accountKey:account,originalUid:original),
        throwsA(isA<DedaStep2PreLinkCheckpointHold>()));
  });

  test('archive server denial stays a failure, never treated as empty balance', () async {
    final gate = DedaStep2PreLinkCheckpoint(
      enabled:true,
      archive: (_, __) async => throw StateError('permission-denied'),
      currentUid: () => original,
      currentIsAnonymous: () => true,
    );
    await expectLater(gate.run(accountKey:account,originalUid:original),
        throwsStateError);
  });
}
