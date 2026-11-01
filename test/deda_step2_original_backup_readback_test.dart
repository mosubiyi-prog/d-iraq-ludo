import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_step2_original_backup_readback.dart';

const account = '07712345678';
const originalUid = 'original-firebase-auth-uid';
const captureId = 'legacyCaptureId_12345678901234567890';

Map<String, dynamic> record({
  String uid = originalUid,
  String key = account,
  String? points = '{"awards":{"original":5}}',
  String? social = '{"xp":200}',
  String? diamonds = '{"balance":1000}',
}) => {
  'format': 1,
  'kind': 'legacy-local-evidence',
  'accountKey': key,
  'sourceUid': uid,
  'installId': 'original-phone-install',
  'captureId': captureId,
  'records': {
    'taskPoints': points,
    'socialCoinsAndXp': social,
    'earnedDiamonds': diamonds,
  },
  'createdAt': Timestamp.fromMillisecondsSinceEpoch(1762027200000),
  '_documentId': captureId,
  '_fromCache': false,
  '_pendingWrites': false,
};

class ReadIo implements DedaStep2EvidenceReadIo {
  ReadIo(this.rows);
  final List<Map<String, dynamic>> rows;
  int calls = 0;
  @override
  Future<List<Map<String, dynamic>>> readServerCaptures({
    required String accountKey,
  }) async {
    calls++;
    return rows;
  }
}

DedaStep2OriginalBackupReadback reader(
  ReadIo io, {
  bool enabled = true,
  String? Function()? uid,
  Future<bool> Function(String, String)? proof,
}) => DedaStep2OriginalBackupReadback(
  io: io,
  currentUid: uid ?? () => originalUid,
  verifyOriginalOwner: proof ?? (u, k) async => u == originalUid && k == account,
  enabled: enabled,
);

void main() {
  test('verified same UID can read exact original evidence but never credit', () async {
    final io = ReadIo([record()]);
    final evidence = await reader(io).readOriginalEvidence(
      accountKey: account, originalUid: originalUid, isCurrent: () => true,
    );
    expect(evidence.sourceUid, originalUid);
    expect(evidence.captureId, captureId);
    expect(evidence.capture.hasAnyLocalRecord, isTrue);
    expect(evidence.canRestoreBalances, isFalse);
    expect(evidence.canAwardPoints, isFalse);
    expect(evidence.canReissueGiftsOrPrizes, isFalse);
    expect(evidence.fullAccountRestored, isFalse);
    expect(io.calls, 1);
  });

  test('same immutable evidence can be read twice without mutations', () async {
    final io = ReadIo([record(), record()]);
    final service = reader(io);
    final first = await service.readOriginalEvidence(
      accountKey: account, originalUid: originalUid, isCurrent: () => true,
    );
    final second = await service.readOriginalEvidence(
      accountKey: account, originalUid: originalUid, isCurrent: () => true,
    );
    expect(first.capture.encode(), second.capture.encode());
    expect(io.calls, 2);
  });

  test('feature is off by default and cannot read server', () async {
    final io = ReadIo([record()]);
    final service = reader(io, enabled: false);
    await expectLater(
      service.readOriginalEvidence(
        accountKey: account, originalUid: originalUid,
        isCurrent: () => true,
      ),
      throwsA(isA<DedaStep2EvidenceHold>()),
    );
    expect(io.calls, 0);
  });

  test('foreign Firebase uid fails before any archive read', () async {
    final io = ReadIo([record()]);
    await expectLater(
      reader(io, uid: () => 'wrong').readOriginalEvidence(
        accountKey: account, originalUid: originalUid,
        isCurrent: () => true,
      ),
      throwsA(isA<DedaStep2EvidenceHold>()),
    );
    expect(io.calls, 0);
  });

  test('server original-owner proof is mandatory', () async {
    final io = ReadIo([record()]);
    await expectLater(
      reader(io, proof: (_, __) async => false).readOriginalEvidence(
        accountKey: account, originalUid: originalUid,
        isCurrent: () => true,
      ),
      throwsA(isA<DedaStep2EvidenceHold>()),
    );
    expect(io.calls, 0);
  });

  test('account switch mid-read refuses old user data', () async {
    final io = ReadIo([record()]);
    var checked = 0;
    await expectLater(
      reader(io).readOriginalEvidence(
        accountKey: account, originalUid: originalUid,
        isCurrent: () => ++checked < 3,
      ),
      throwsA(isA<DedaStep2EvidenceHold>()),
    );
  });

  test('source uid and account key must match the proven original', () async {
    for (final row in [
      record(uid: 'someone-else'),
      record(key: '07700000000'),
    ]) {
      await expectLater(
        reader(ReadIo([row])).readOriginalEvidence(
          accountKey: account, originalUid: originalUid,
          isCurrent: () => true,
        ),
        throwsA(isA<DedaStep2EvidenceHold>()),
      );
    }
  });

  test('missing archive, all-null source and ambiguous captures block', () async {
    for (final rows in <List<Map<String, dynamic>>>[
      [],
      [record(points: null, social: null, diamonds: null)],
      [record(), record(points: '{"awards":{"original":999}}')],
    ]) {
      await expectLater(
        reader(ReadIo(rows)).readOriginalEvidence(
          accountKey: account, originalUid: originalUid,
          isCurrent: () => true,
        ),
        throwsA(isA<DedaStep2EvidenceHold>()),
      );
    }
  });

  test('only live server immutable complete archive schema is accepted', () async {
    final forged = [
      {...record(), '_fromCache': true},
      {...record(), '_pendingWrites': true},
      {...record(), '_documentId': 'a-different-document'},
      {...record(), 'createdAt': 'from-client'},
      {...record(), 'walletCredit': 999999},
      {...record(), 'installId': ''},
      {...record(), 'records': {'taskPoints': '1'}},
    ];
    for (final row in forged) {
      await expectLater(
        reader(ReadIo([row])).readOriginalEvidence(
          accountKey: account, originalUid: originalUid,
          isCurrent: () => true,
        ),
        throwsA(anything),
      );
    }
  });

  test('more than bounded snapshot page refuses incomplete history', () async {
    await expectLater(
      reader(ReadIo(List.generate(26, (_) => record()))).readOriginalEvidence(
        accountKey: account, originalUid: originalUid,
        isCurrent: () => true,
      ),
      throwsA(isA<DedaStep2EvidenceHold>()),
    );
  });
}
