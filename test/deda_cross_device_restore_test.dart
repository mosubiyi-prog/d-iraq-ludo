import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_cross_device_restore.dart';
import 'package:d_iraq_ludo/deda_legacy_progress_capture.dart';
import 'package:d_iraq_ludo/deda_owner_session_firebase_port.dart';
import 'package:d_iraq_ludo/deda_progress_evidence_store.dart';
import 'package:d_iraq_ludo/deda_session_flow_prototype.dart';
import 'package:d_iraq_ludo/deda_session_principal_tracker.dart';
import 'package:d_iraq_ludo/deda_session_transition_gate.dart';

const _account = '07700000000';
const _captureId = 'legacy_progress_original_000001';
const _path = 'deda_progress_evidence/$_account/captures/$_captureId';

class _Legacy implements DedaLegacyProgressReadStore {
  @override
  Future<Map<String, String?>> readStrings(List<String> keys) async => {
    keys[0]: '{"awards":{"earned":{"points":85}}}',
    keys[1]: '{"coins":10,"xp":85}',
    keys[2]: '{"diamonds":110,"spendIds":["purchase-1"]}',
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
  _Io() { asUser('old-phone'); }
  final tracker = DedaSessionPrincipalTracker();
  final docs = <String, Map<String, dynamic>>{};
  Completer<void>? listHold;
  int historyReads = 0;
  bool ready = true;
  String install = 'old-phone-install';
  @override
  DedaFlowSdkUser? currentUser;
  void asUser(String uid, {String account = _account}) {
    currentUser = tracker.observe(uid, DedaSessionAuthKind.anonymous);
    docs['deda_sessions/$uid'] = {
      'uid': uid, 'accountKey': account, 'installId': install,
    };
    docs['users/$uid'] = {'accountKey': account};
  }
  @override
  Future<String> installId(void Function() check) async {
    check(); return install;
  }
  @override
  Future<DedaOwnerServerDocument> readServer(String path) async =>
      DedaOwnerServerDocument(docs[path]);
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
  late final recovery = DedaCrossDeviceRestore(archive: archive, local: local);
  Future<void> seed() async {
    final capture = await DedaLegacyProgressReader(_Legacy()).capture(
        accountKey: _account, isCurrent: () => true);
    await archive.save(
        captureId: _captureId, capture: capture, isCurrent: () => true);
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
    expect((data['records'] as Map)['earnedDiamonds'],
        '{"diamonds":110,"spendIds":["purchase-1"]}');
    expect((data['records'] as Map)['taskPoints'],
        '{"awards":{"earned":{"points":85}}}');
    expect(f.local.values.keys, hasLength(1));
    expect(f.local.values.keys.single, contains('untrusted_recovery'));
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

  test('no old archive does not invent a zero balance', () async {
    final f = _Fixture();
    f.useSecondPhone();
    expect((await f.stage()).status,
        DedaRecoveryStageStatus.noPreviousDeviceArchive);
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
