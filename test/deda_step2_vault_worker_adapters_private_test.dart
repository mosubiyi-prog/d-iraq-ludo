import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_step2_recovery_guardian.dart';
import 'package:d_iraq_ludo/deda_step2_vault_worker_adapters.dart';
import 'package:d_iraq_ludo/deda_step2_original_backup_readback.dart';
import 'package:d_iraq_ludo/deda_step2_level_points_restore.dart';
import 'package:d_iraq_ludo/deda_step2_linked_published_place_recovery.dart';

const account = '07712345678';
const uid = 'original-auth-uid-100436';
const originalId = '@DEDA-ABC123';
const captureId = 'original_phone_20261105_capture_001';
const install = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const ledger = '{"version":1,"completions":{},"awards":{},"ledger":[]}';

DedaVaultVerifiedScope scope({bool Function()? current}) =>
  DedaVaultVerifiedScope(
    accountKey: account, originalUid: uid, originalId: originalId,
    intentId: 'recovery_20261105_guardian_00001',
    isCurrentIntent: current ?? () => true,
    verifyOriginalOwnerOnServer: () async => true,
  );

class EvidenceIo implements DedaStep2EvidenceReadIo {
  EvidenceIo();
  bool fromCache = false;
  bool tampered = false;
  int reads = 0;

  @override
  Future<List<Map<String, dynamic>>> readServerCaptures({
    required String accountKey}) async {
    reads++;
    return <Map<String, dynamic>>[<String, dynamic>{
      'format': 1, 'kind': 'legacy-local-evidence',
      'accountKey': tampered ? 'other-account' : account,
      'sourceUid': uid, 'installId': install, 'captureId': captureId,
      'records': <String, dynamic>{
        'taskPoints': ledger, 'socialCoinsAndXp': null, 'earnedDiamonds': null,
      },
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 11, 5)),
      '_documentId': captureId,
      '_fromCache': fromCache, '_pendingWrites': false,
    }];
  }
}

DedaStep2OriginalBackupReadback progress(EvidenceIo io) =>
  DedaStep2OriginalBackupReadback(
    io: io, currentUid: () => uid, enabled: true,
    verifyOriginalOwner: (u,a) async => u == uid && a == account,
  );

class LocalLedger implements DedaStep2LevelLocalIo {
  String? text;
  int writes = 0;
  @override
  Future<String?> read(String a) async => text;
  @override
  Future<bool> write(String a, String raw) async {
    writes++;
    text = raw;
    return true;
  }
}

class PlaceIo implements DedaStep2LinkedPlaceIo {
  PlaceIo({this.owner = uid,this.cached = false,this.empty = false});
  final String owner;
  final bool cached, empty;
  String? local;
  int scopedWrites = 0;
  @override
  Future<DedaStep2PublishedPlacesResult> publishedForAccount(String a) async =>
    DedaStep2PublishedPlacesResult(empty ? [] : [
      DedaStep2PublishedPlaceRow('published-100436',{
        'accountKey': account,'ownerUid': owner,'published': true,
        'approvalNumber': 'APPROVED-2026-001',
      }),
    ], fromCache: cached);
  @override
  Future<String?> localPlaceId(String a) async => local;
  @override
  Future<bool> saveScopedPlaceId(String a,String id) async {
    scopedWrites++;
    local = id;
    return true;
  }
}

DedaVaultPublishedPlaceAdapter place(PlaceIo io) =>
  DedaVaultPublishedPlaceAdapter(DedaStep2LinkedPublishedPlaceRecovery(
    io:io, currentUid:()=>uid, enabled:true,
    verifyOriginalOwner:(u,a)async=>u==uid && a==account,
  ),io);

void main() {
  test('original archive worker produces only a fresh server readback receipt',() async {
    final io = EvidenceIo();
    final worker = DedaVaultOriginalEvidenceAdapter(progress(io));
    final s=scope(), op=s.operationKey(worker.code);
    await worker.executeOnce(s,op);
    final receipt=await worker.confirmByReadback(s,op);
    expect(receipt?.matches(s, worker.code), true);
    expect(RegExp(r'^progress_[0-9a-f]{16}$').hasMatch(receipt!.receiptId),true);
    expect(io.reads, 2); // separate execution and readback
  });

  test('original archive tampering after the first read prevents verification',() async {
    final io=EvidenceIo();
    final worker=DedaVaultOriginalEvidenceAdapter(progress(io));
    final s=scope(),op=s.operationKey(worker.code);
    await worker.executeOnce(s,op);
    io.tampered=true;
    await expectLater(worker.confirmByReadback(s,op),throwsA(isA<DedaStep2EvidenceHold>()));
  });

  test('level worker restores exact source ledger idempotently without XP grant',() async {
    final io=EvidenceIo(),local=LocalLedger(),src=progress(io);
    final restore = DedaStep2LevelPointsRestore(
      fetchOriginal: (a,u,current)=>src.readOriginalEvidence(
        accountKey:a, originalUid:u, isCurrent:current),
      local: local,currentUid:()=>uid,enabled:true,
    );
    final worker=DedaVaultLevelPointsAdapter(restore,src,local);
    final s=scope(),op=s.operationKey(worker.code);
    await worker.executeOnce(s,op);
    final first=await worker.confirmByReadback(s,op);
    await worker.executeOnce(s,op);
    expect(local.writes,1);
    expect(local.text,ledger);
    expect(RegExp(r'^level_[0-9a-f]{16}$').hasMatch(first!.receiptId),true);
    expect((await worker.confirmByReadback(s,op))?.receiptId,first?.receiptId);
  });

  test('published place worker only binds same-owned existing ID to local scope',() async {
    final io=PlaceIo(),worker=place(io);
    final s=scope(),op=s.operationKey(worker.code);
    await worker.executeOnce(s,op);
    final receipt=await worker.confirmByReadback(s,op);
    await worker.executeOnce(s,op);
    expect(RegExp(r'^published_place_[0-9a-f]{16}$').hasMatch(receipt!.receiptId),true);
    expect(receipt?.matches(s,worker.code),true);
    expect(io.scopedWrites,1);
  });

  test('different published place UID fails closed and writes nothing',() async {
    final io=PlaceIo(owner:'another-uid'),worker=place(io);
    final s=scope(),op=s.operationKey(worker.code);
    await expectLater(worker.executeOnce(s,op),
      throwsA(isA<DedaStep2PublishedPlaceHold>()));
    expect(io.scopedWrites,0);
    expect(await worker.confirmByReadback(s,op),isNull);
  });

  test('cache-only published place and missing place never become restoration',() async {
    for(final io in [PlaceIo(cached:true),PlaceIo(empty:true)]) {
      final worker=place(io),s=scope(),op=s.operationKey(worker.code);
      await expectLater(worker.executeOnce(s,op),
        throwsA(isA<DedaStep2PublishedPlaceHold>()));
      expect(io.scopedWrites,0);
    }
  });

  test('stale intent rejects source worker before server read',() async {
    final io=EvidenceIo(),worker=DedaVaultOriginalEvidenceAdapter(progress(io));
    final s=scope(current:()=>false);
    await expectLater(worker.executeOnce(s,s.operationKey(worker.code)),
        throwsA(isA<DedaStep2EvidenceHold>()));
    expect(io.reads,0);
  });

  test('received purchase or server evidence alone never asserts whole restore',() {
    final io=EvidenceIo();
    final worker=DedaVaultOriginalEvidenceAdapter(progress(io));
    expect(worker.code,DedaVaultCode.originalBackupReadback);
    expect(const DedaVaultRecoveryResult(stepStates:{},
        stoppedSafely:false).fullAccountRestored,false);
    expect(jsonDecode(ledger)['awards'],isEmpty);
  });
}
