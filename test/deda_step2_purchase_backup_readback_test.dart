import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_legacy_progress_capture.dart';
import 'package:d_iraq_ludo/deda_legacy_purchase_evidence.dart';
import 'package:d_iraq_ludo/deda_step2_original_backup_readback.dart';
import 'package:d_iraq_ludo/deda_step2_purchase_backup_readback.dart';

const account = '9647712345678';
const id = '@DEDA-ABC123';
const uid = 'original_uid_100340';
const install = 'old-original-install';
const captureId = 'original_phone_capture_000001';

DedaStep2OriginalEvidence progress({
  String sourceUid = uid,
  String sourceInstall = install,
  String key = account,
}) {
  final capture = DedaLegacyProgressCapture.decodeForAccount(jsonEncode({
    'format': 1,
    'accountKey': key,
    'records': {
      'taskPoints': '{"historical":5}',
      'socialCoinsAndXp': '{"xp":200}',
      'earnedDiamonds': '{"earned":1234}',
    }
  }), expectedAccountKey: key);
  return DedaStep2OriginalEvidence(
    captureId: captureId, sourceUid: sourceUid,
    sourceInstallId: sourceInstall, capture: capture,
  );
}

String oldPurchaseBytes() => jsonEncode({
  'format': 1, 'accountKey': account, 'originalId': id,
  'inventory': '{"owned":["FRAME_03"]}',
  'frameJournals': {
    for (final frame in dedaLegacyPurchaseFrames) frame: null,
  },
});

Map<String, dynamic> validRow() => {
  'format': 1, 'kind': 'legacy-purchase-evidence',
  'accountKey': account, 'sourceUid': uid, 'installId': install,
  'captureId': captureId,
  'createdAt': Timestamp.fromMillisecondsSinceEpoch(1762027200000),
  'records': {
    'originalId': id, 'progressCaptureId': captureId,
    'localSnapshot': oldPurchaseBytes(),
  },
};

class FakePurchaseIo implements DedaStep2PurchaseSourceIo {
  FakePurchaseIo(this.document);
  final DedaStep2PurchaseSourceDocument document;
  int calls = 0;
  @override
  Future<DedaStep2PurchaseSourceDocument> server({
    required String accountKey,
    required String captureId,
  }) async {
    calls++;
    expect(accountKey, account);
    expect(captureId, globalsCaptureId);
    return document;
  }
}
const globalsCaptureId = captureId;

DedaStep2PurchaseSourceReadback service(
  FakePurchaseIo io, {
  bool enabled = true,
  String? Function()? currentUid,
  Future<bool> Function(String,String)? verify,
}) => DedaStep2PurchaseSourceReadback(
  io: io, enabled: enabled,
  currentUid: currentUid ?? () => uid,
  verifyOriginalOwner: verify ?? (u, a) async => u == uid && a == account,
);

Future<DedaStep2PurchaseSourceEvidence> inspect(
  DedaStep2PurchaseSourceReadback read, {
  DedaStep2OriginalEvidence? paired,
  bool Function()? current,
}) => read.inspectPairedWithProgress(
  accountKey: account, originalId: id, originalUid: uid,
  progress: paired ?? progress(),
  isCurrent: current ?? () => true,
);

void main() {
  test('normal Play build has purchase readback OFF by default', () {
    expect(dedaStep2PurchaseSourceReadbackEnabled, isFalse);
  });

  test('same original UID, installation, and capture can inspect raw purchases only', () async {
    final io = FakePurchaseIo(DedaStep2PurchaseSourceDocument(validRow()));
    final result = await inspect(service(io));
    expect(result.captureId, captureId);
    expect(result.sourceUid, uid);
    expect(result.sourceInstallId, install);
    expect(result.localPurchaseSnapshot.accountKey, account);
    expect(result.localPurchaseSnapshot.originalId, id);
    expect(result.localPurchaseSnapshot.encode(), oldPurchaseBytes());
    expect(result.canRestoreDiamonds, isFalse);
    expect(result.canGrantPaidFrames, isFalse);
    expect(result.canActivatePremiumId, isFalse);
    expect(result.canReissueGiftsOrPrizes, isFalse);
    expect(result.fullAccountRestored, isFalse);
    expect(result.allowPhoneCutover, isFalse);
    expect(io.calls, 1);
  });

  test('feature disabled, wrong UID, wrong install, stale scope never read backend', () async {
    for (final tuple in [
      (enabled: false, principal: uid, paired: progress(), active: true),
      (enabled: true, principal: 'other-uid', paired: progress(), active: true),
      (enabled: true, principal: uid,
          paired: progress(sourceUid: 'other-uid'), active: true),
      (enabled: true, principal: uid,
          paired: progress(sourceInstall: ''), active: true),
      (enabled: true, principal: uid,
          paired: progress(key: '9647712340000'), active: true),
      (enabled: true, principal: uid, paired: progress(), active: false),
    ]) {
      final io = FakePurchaseIo(DedaStep2PurchaseSourceDocument(validRow()));
      await expectLater(inspect(service(io,
        enabled: tuple.enabled, currentUid: () => tuple.principal),
        paired: tuple.paired, current: () => tuple.active),
        throwsA(isA<DedaStep2PurchaseSourceHold>()));
      expect(io.calls, 0);
    }
  });

  test('cannot read before verified server owner proof', () async {
    final io = FakePurchaseIo(DedaStep2PurchaseSourceDocument(validRow()));
    await expectLater(inspect(service(io, verify: (_, __) async => false)),
      throwsA(isA<DedaStep2PurchaseSourceHold>()));
    expect(io.calls, 0);
  });

  test('missing purchase and cache/pending sources are never considered empty wallet', () async {
    for (final doc in [
      const DedaStep2PurchaseSourceDocument(null),
      DedaStep2PurchaseSourceDocument(validRow(), fromCache: true),
      DedaStep2PurchaseSourceDocument(validRow(), pendingWrites: true),
    ]) {
      await expectLater(inspect(service(FakePurchaseIo(doc))),
        throwsA(isA<DedaStep2PurchaseSourceHold>()));
    }
  });

  test('forged UID, account, capture, installation and JSON all fail closed', () async {
    final baseline = validRow();
    final altered = [
      {...baseline, 'sourceUid': 'foreign_uid'},
      {...baseline, 'accountKey': 'other_account'},
      {...baseline, 'installId': 'other_phone'},
      {...baseline, 'captureId': 'other_capture'},
      {...baseline, 'format': 2},
      {...baseline, 'kind': 'paid-frame-receipt'},
      {...baseline, 'createdAt': 'local_timestamp'},
      {...baseline, 'issuedDiamonds': 500000},
      {...baseline, 'records': {
        ...baseline['records'] as Map, 'originalId': '@DEDA-OTHER1',
      }},
      {...baseline, 'records': {
        ...baseline['records'] as Map, 'progressCaptureId': 'wrong'},
      },
      {...baseline, 'records': {
        ...baseline['records'] as Map, 'localSnapshot': '{corrupted'},
      },
      {...baseline, 'records': {
        ...baseline['records'] as Map,
        'localSnapshot': oldPurchaseBytes().replaceFirst('"accountKey":"$account"', '"accountKey":"other"'),
      }},
      {...baseline, 'records': {
        ...baseline['records'] as Map, 'extraReceipt': 'fake',
      }},
    ];
    for (final row in altered) {
      await expectLater(inspect(service(FakePurchaseIo(
        DedaStep2PurchaseSourceDocument(row)))),
        throwsA(isA<DedaStep2PurchaseSourceHold>()));
    }
  });

  test('if user switches account after network read, no original evidence accepted', () async {
    var active = true;
    final io = _SwitchingIo(() => active = false);
    await expectLater(inspect(service(io), current: () => active),
      throwsA(isA<DedaStep2PurchaseSourceHold>()));
    expect(io.calls, 1);
  });

  test('different session during server proof prevents accepting an archive', () async {
    var current = uid;
    final io = FakePurchaseIo(DedaStep2PurchaseSourceDocument(validRow()));
    final reader = service(io, currentUid: () => current,
      verify: (_, __) async { current = 'different-uid'; return true; });
    await expectLater(inspect(reader),
      throwsA(isA<DedaStep2PurchaseSourceHold>()));
    expect(io.calls, 0);
  });
}

class _SwitchingIo implements DedaStep2PurchaseSourceIo {
  _SwitchingIo(this.changeSession);
  final void Function() changeSession;
  int calls = 0;
  @override
  Future<DedaStep2PurchaseSourceDocument> server({
    required String accountKey, required String captureId,
  }) async {
    calls++;
    changeSession();
    return DedaStep2PurchaseSourceDocument(validRow());
  }
}
