import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_cross_device_restore.dart';
import 'package:d_iraq_ludo/deda_legacy_progress_capture.dart';
import 'package:d_iraq_ludo/deda_legacy_purchase_evidence.dart';
import 'package:d_iraq_ludo/deda_owner_session_firebase_port.dart';
import 'package:d_iraq_ludo/deda_progress_evidence_store.dart';
import 'package:d_iraq_ludo/deda_session_flow_prototype.dart';
import 'package:d_iraq_ludo/deda_session_principal_tracker.dart';
import 'package:d_iraq_ludo/deda_session_transition_gate.dart';

const _account = '07700000000';
const _captureId = 'legacy_progress_original_000001';
const _purchaseId = 'legacy_purchase_original_000001';
const _originalPersonalId = '@DEDA-ABC123';
const _path = 'deda_progress_evidence/$_account/captures/$_captureId';

class _Legacy implements DedaLegacyProgressReadStore {
  @override
  Future<Map<String, String?>> readStrings(List<String> keys) async => {
    keys[0]: '{"awards":{"earned":{"points":85}}}',
    keys[1]: '{"coins":10,"xp":85}',
    keys[2]: '{"diamonds":110,"spendIds":["purchase-1"]}',
  };
}

class _ZeroLegacy implements DedaLegacyProgressReadStore {
  @override
  Future<Map<String, String?>> readStrings(List<String> keys) async => {
    keys[0]: '{"points":0}',
    keys[1]: '{"coins":0,"xp":0}',
    keys[2]: '{"diamonds":0}',
  };
}

class _LegacyPurchases implements DedaLegacyPurchaseReadStore {
  @override
  Future<Map<String, Object?>> readValues(List<String> keys) async => {
    for (final key in keys)
      key: key.startsWith('deda_style_inventory_')
          ? '{"owned":["FRAME_03"],"receipt":"unverified-local"}'
          : key.endsWith('_FRAME_03') ? 'pending-original-payment' : null,
  };
}

class _Local implements DedaRecoveryLocalStore {
  final values = <String, String>{};
  int writes = 0;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> writeOnce(String key, String value) async {
    if (values.containsKey(key) && values[key] != value) {
      throw StateError('overwrite-blocked');
    }
    writes++;
    values[key] = value;
  }
}

class _Io implements DedaProgressEvidenceIo {
  _Io() {
    docs['deda_account_directory/$_account'] = {
      'accountKey': _account, 'active': true, 'createdUid': 'old-phone',
    };
    asUser('old-phone');
  }
  final tracker = DedaSessionPrincipalTracker();
  final docs = <String, Map<String, dynamic>>{};
  Completer<void>? listHold;
  int historyReads = 0;
  bool cachedDirectory = false;
  bool ready = true;
  String install = 'old-phone-install';
  @override
  DedaFlowSdkUser? currentUser;
  void asUser(String uid, {String account = _account}) {
    currentUser = tracker.observe(uid, DedaSessionAuthKind.anonymous);
    docs['deda_sessions/$uid'] = {
      'uid': uid, 'accountKey': account, 'installId': install,
    };
    docs['users/$uid'] = {
      'accountKey': account, 'sharePersonalId': _originalPersonalId,
    };
  }
  @override
  Future<String> installId(void Function() check) async {
    check(); return install;
  }
  @override
  Future<DedaOwnerServerDocument> readServer(String path) async =>
      DedaOwnerServerDocument(docs[path],
          fromCache: cachedDirectory &&
              path.startsWith('deda_account_directory/'));
  @override
  Future<List<DedaListedProgressEvidence>> listServer(
      String path, {required int limit}) async {
    historyReads++;
    if (listHold != null) await listHold!.future;
    return [
      for (final entry in docs.entries.where((e) =>
          e.key.startsWith('$path/')).take(limit))
        DedaListedProgressEvidence(
            entry.key.split('/').last, DedaOwnerServerDocument(entry.value))
    ];
  }
  @override
  Object serverTimestamp() => Timestamp.fromMillisecondsSinceEpoch(1000);
  @override
  Future<void> writeOnce(String path, Map<String, dynamic> fields,
      void Function() check) async {
    check();
    if (docs.containsKey(path)) throw const DedaProgressEvidenceConflict();
    docs[path] = Map.of(fields);
    check();
  }
}

class _Fixture {
  final io = _Io();
  final local = _Local();
  bool live = true;
  late final archive = DedaProgressEvidenceStore(io);
  late final purchases = DedaLegacyPurchaseEvidenceStore(archive);
  late final recovery = DedaCrossDeviceRestore(
      archive: archive, local: local, purchaseArchive: purchases);
  Future<void> seed({bool withPurchases = true}) async {
    final capture = await DedaLegacyProgressReader(_Legacy()).capture(
        accountKey: _account, isCurrent: () => true);
    await archive.save(
        captureId: _captureId, capture: capture, isCurrent: () => true);
    if (withPurchases) {
      await purchases.save(
          captureId: _purchaseId, progressCaptureId: _captureId,
          capture: await DedaLegacyPurchaseReader(_LegacyPurchases()).capture(
              accountKey: _account, originalId: _originalPersonalId,
              isCurrent: () => true),
          isCurrent: () => true);
    }
  }
  void useSecondPhone() {
    io.install = 'replacement-install';
    io.asUser('new-phone');
  }
  Future<DedaRecoveryStage> stage() => recovery.stage(
      accountKey: _account, isCurrent: () => live);
}

void main() {
  test('second phone stages FULL original raw data without touching spendable balances',
      () async {
    final f = _Fixture();
    await f.seed();
    f.useSecondPhone();
    final result = await f.stage();
    expect(result.status,
        DedaRecoveryStageStatus.stagedAwaitingServerReconciliation);
    expect(result.captureId, _captureId);
    final raw = f.local.values[DedaCrossDeviceRestore.pendingKey(_account)]!;
    final data = jsonDecode(raw) as Map;
    expect(data['accountKey'], _account);
    expect(data['sourceUid'], 'old-phone');
    expect(data['financiallySettled'], false);
    expect(data['purchasesSettled'], false);
    expect(data['purchaseEvidenceLinked'], true);
    final purchase = data['purchaseEvidence'] as Map;
    expect(purchase['captureId'], _purchaseId);
    expect(purchase['originalId'], _originalPersonalId);
    expect((purchase['localSnapshot'] as String), contains('FRAME_03'));
    // Only the untrusted staging key was written: zero frame/ID grants.

    expect((data['records'] as Map)['earnedDiamonds'],
        '{"diamonds":110,"spendIds":["purchase-1"]}');
    expect((data['records'] as Map)['taskPoints'],
        '{"awards":{"earned":{"points":85}}}');
    expect(f.local.values.keys, hasLength(1));
    expect(f.local.values.keys.single, contains('untrusted_recovery'));
  });

  test('no purchase sidecar preserves unknown ownership instead of zeroing frames',
      () async {
    final f = _Fixture();
    await f.seed(withPurchases: false);
    f.useSecondPhone();
    final result = await f.stage();
    expect(result.status,
        DedaRecoveryStageStatus.stagedAwaitingServerReconciliation);
    final data = jsonDecode(
        f.local.values[DedaCrossDeviceRestore.pendingKey(_account)]!) as Map;
    expect(data['purchaseEvidenceLinked'], false);
    expect(data['purchaseEvidence'], isNull);
    expect(data['purchasesSettled'], false);
  });

  test('two purchase claims for same archive are held, never silently selected',
      () async {
    final f = _Fixture();
    await f.seed();
    final original = await DedaLegacyPurchaseReader(_LegacyPurchases()).capture(
        accountKey: _account, originalId: _originalPersonalId,
        isCurrent: () => true);
    await f.purchases.save(
        captureId: 'legacy_purchase_original_000002',
        progressCaptureId: _captureId, capture: original,
        isCurrent: () => true);
    f.useSecondPhone();
    expect((await f.stage()).status,
        DedaRecoveryStageStatus.purchaseEvidenceConflict);
    expect(f.local.values, isEmpty);
  });

  test('second phone repeated read is idempotent, never duplicates records',
      () async {
    final f = _Fixture();
    await f.seed();
    f.useSecondPhone();
    await f.stage();
    final again = await f.stage();
    expect(again.status, DedaRecoveryStageStatus.alreadyStaged);
    expect(f.local.writes, 1);
  });

  test('same Firebase UID on another installation is still a prior-device archive',
      () async {
    final f = _Fixture();
    await f.seed();
    f.io.install = 'second-installation-same-uid';
    f.io.asUser('old-phone');
    final result = await f.stage();
    expect(result.status,
        DedaRecoveryStageStatus.stagedAwaitingServerReconciliation);
    final data = jsonDecode(
        f.local.values[DedaCrossDeviceRestore.pendingKey(_account)]!) as Map;
    expect(data['sourceUid'], 'old-phone');
    expect(data['installId'], 'old-phone-install');
    expect(data['purchaseEvidenceLinked'], true);
    expect(data['financiallySettled'], false);
  });

  test('locally initialized replacement device defaults cannot hide old history',
      () async {
    final f = _Fixture();
    await f.seed();
    f.useSecondPhone();
    // The application might already have written 0-valued local keys.
    // A server preflight must still detect an old device before upload.
    final localDefaults = await DedaLegacyProgressReader(_ZeroLegacy()).capture(
        accountKey: _account, isCurrent: () => true);
    expect(localDefaults.hasAnyLocalRecord, true);
    final stage = await f.stage();
    expect(stage.status,
        DedaRecoveryStageStatus.stagedAwaitingServerReconciliation);
    expect(f.local.values.keys, hasLength(1));
  });

  test('original device without archives does not invent a zero balance',
      () async {
    final f = _Fixture();
    expect((await f.stage()).status,
        DedaRecoveryStageStatus.noPreviousDeviceArchive);
    expect(f.local.values, isEmpty);
  });

  test('new phone without old archive holds pre-existing account before backup',
      () async {
    final f = _Fixture();
    f.useSecondPhone();
    expect((await f.stage()).status,
        DedaRecoveryStageStatus.priorAccountWithoutArchive);
    expect(f.local.values, isEmpty);
  });

  test('missing or mismatched server directory fails closed without local writes',
      () async {
    final f = _Fixture();
    f.io.docs.remove('deda_account_directory/$_account');
    expect((await f.stage()).status,
        DedaRecoveryStageStatus.accountDirectoryUnverified);
    f.io.docs['deda_account_directory/$_account'] = {
      'accountKey': '07709999999', 'active': true, 'createdUid': 'old-phone',
    };
    expect((await f.stage()).status,
        DedaRecoveryStageStatus.accountDirectoryUnverified);
    f.io.docs['deda_account_directory/$_account'] = {
      'accountKey': _account, 'active': true, 'createdUid': 'old-phone',
    };
    f.io.cachedDirectory = true;
    expect((await f.stage()).status,
        DedaRecoveryStageStatus.accountDirectoryUnverified);
    expect(f.local.values, isEmpty);
  });

  test('twenty entries from current phone cannot hide older truncated history',
      () async {
    final f = _Fixture();
    final original = await DedaLegacyProgressReader(_ZeroLegacy()).capture(
        accountKey: _account, isCurrent: () => true);
    for (var n = 0; n < 20; n++) {
      await f.archive.save(
          captureId: 'new_account_history_capture_${n.toString().padLeft(3, '0')}',
          capture: original, isCurrent: () => true);
    }
    expect((await f.stage()).status,
        DedaRecoveryStageStatus.archiveWindowIncomplete);
    expect(f.local.values, isEmpty);
  });

  test('old phone cannot restore its own snapshot into current wallet',
      () async {
    final f = _Fixture();
    await f.seed();
    expect((await f.stage()).status,
        DedaRecoveryStageStatus.noPreviousDeviceArchive);
    expect(f.local.writes, 0);
  });

  test('two historical captures from one original phone require review',
      () async {
    final f = _Fixture();
    await f.seed();
    await f.archive.save(
        captureId: 'old_phone_earlier_capture_00002',
        capture: await DedaLegacyProgressReader(_Legacy()).capture(
            accountKey: _account, isCurrent: () => true),
        isCurrent: () => true);
    f.useSecondPhone();
    expect((await f.stage()).status,
        DedaRecoveryStageStatus.historicalCapturesNeedReview);
    expect(f.local.values, isEmpty);
  });

  test('full history page with prior captures refuses incomplete restore',
      () async {
    final f = _Fixture();
    await f.seed();
    final capture = await DedaLegacyProgressReader(_Legacy()).capture(
        accountKey: _account, isCurrent: () => true);
    for (var n = 1; n < 20; n++) {
      await f.archive.save(
          captureId: 'old_phone_history_batch_${n.toString().padLeft(4, '0')}',
          capture: capture, isCurrent: () => true);
    }
    f.useSecondPhone();
    expect((await f.stage()).status,
        DedaRecoveryStageStatus.archiveWindowIncomplete);
    expect(f.local.values, isEmpty);
  });

  test('old and newer previous device sources trigger manual review, not latest-spendable',
      () async {
    final f = _Fixture();
    await f.seed();
    f.io.install = 'third-install';
    f.io.asUser('third-phone');
    await f.archive.save(
        captureId: 'third_account_backup_0000001',
        capture: await DedaLegacyProgressReader(_Legacy()).capture(
            accountKey: _account, isCurrent: () => true),
        isCurrent: () => true);
    f.useSecondPhone();
    expect((await f.stage()).status,
        DedaRecoveryStageStatus.multipleSourcesRequireReview);
    expect(f.local.values, isEmpty);
  });

  test('unrelated PIN account cannot stage another account archived state',
      () async {
    final f = _Fixture();
    await f.seed();
    f.io.install = 'other-install';
    f.io.asUser('other-phone', account: '07700000001');
    await expectLater(f.stage(), throwsA(isA<DedaSessionProofRejected>()));
    expect(f.local.values, isEmpty);
  });

  test('account switch during server history read rejects late data',
      () async {
    final f = _Fixture();
    await f.seed();
    f.useSecondPhone();
    final hold = Completer<void>();
    f.io.listHold = hold;
    final result = expectLater(
        f.stage(), throwsA(isA<DedaStaleSessionTransition>()));
    for (var n = 0; n < 60 && f.io.historyReads == 0; n++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(f.io.historyReads, 1);
    f.io.asUser('another-account');
    hold.complete();
    await result;
    expect(f.local.values, isEmpty);
  });

  test('existing restored candidate never overwritten by different archive',
      () async {
    final f = _Fixture();
    await f.seed();
    f.useSecondPhone();
    f.local.values[DedaCrossDeviceRestore.pendingKey(_account)] =
        '{"original":"do-not-delete"}';
    expect((await f.stage()).status,
        DedaRecoveryStageStatus.existingRecoveryConflict);
    expect(f.local.writes, 0);
  });

  test('invalid account rejected before any Firebase read', () async {
    final f = _Fixture();
    await expectLater(
        f.recovery.stage(accountKey: '../other', isCurrent: () => true),
        throwsArgumentError);
    expect(f.io.historyReads, 0);
    expect(f.local.values, isEmpty);
  });
}
