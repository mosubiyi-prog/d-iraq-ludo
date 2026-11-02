import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_step2_original_source_continuity.dart';
import 'package:d_iraq_ludo/deda_step2_original_backup_readback.dart';
import 'package:d_iraq_ludo/deda_legacy_progress_capture.dart';
import 'package:d_iraq_ludo/deda_progress_backup_coordinator.dart';
import 'package:d_iraq_ludo/deda_progress_evidence_store.dart';

import 'deda_progress_backup_coordinator_test.dart' as fixture;

const uid = 'old-device';
const account = fixture.account;
const captureId = 'original_phone_snapshot_00000001';

/// Simulates a 100340 installation without any of the three legacy
/// progress keys. An empty archive must NEVER be acknowledged as recoverable.
class EmptyOriginalPhoneSource implements DedaLegacyProgressReadStore {
  @override
  Future<Map<String, String?>> readStrings(List<String> keys) async =>
      {for (final key in keys) key: null};
}

DedaStep2OriginalSourceContinuity emptyOriginalPhoneFlow(Scenario s) =>
    DedaStep2OriginalSourceContinuity(
      backup: DedaProgressBackupCoordinator(
        reader: DedaLegacyProgressReader(EmptyOriginalPhoneSource()),
        archive: s.h.backup.archive,
        journal: s.h.journal,
      ),
      readback: s.flow.readback,
      currentUid: () => s.currentUid,
      enabled: true,
    );

class ArchiveReader implements DedaStep2EvidenceReadIo {
  ArchiveReader(this.h);
  final fixture.Harness h;
  int reads = 0;

  @override
  Future<List<Map<String, dynamic>>> readServerCaptures({
    required String accountKey,
  }) async {
    reads++;
    final prefix = 'deda_progress_evidence/$accountKey/captures/';
    final docs = h.io.docs.entries.where((e) => e.key.startsWith(prefix));
    return [
      for (final doc in docs)
        {
          ...doc.value,
          '_documentId': doc.key.substring(prefix.length),
          '_fromCache': false,
          '_pendingWrites': false,
        }
    ];
  }
}

class Scenario {
  final fixture.Harness h = fixture.Harness();
  late final ArchiveReader reader = ArchiveReader(h);
  String currentUid = uid;
  bool isCurrent = true;
  late final DedaStep2OriginalSourceContinuity flow =
      DedaStep2OriginalSourceContinuity(
    backup: h.backup,
    readback: DedaStep2OriginalBackupReadback(
      io: reader,
      currentUid: () => currentUid,
      verifyOriginalOwner: (u, key) async => u == uid && key == account,
      enabled: true,
    ),
    currentUid: () => currentUid,
    enabled: true,
  );
  Future<DedaStep2OriginalSourceReceipt> save({String id = captureId}) =>
      flow.archiveOnOriginalPhone(
        accountKey: account,
        originalUid: uid,
        captureId: id,
        isCurrent: () => isCurrent,
      );
  Future<DedaStep2OriginalEvidence> inspect() =>
      flow.inspectOnReplacementPhone(
        accountKey: account,
        originalUid: uid,
        isCurrent: () => isCurrent,
      );
}

void main() {
  test('old phone source -> cloud acknowledgement -> same original UID new phone read', () async {
    final s = Scenario();
    await expectLater(s.inspect(), throwsA(isA<DedaStep2EvidenceHold>()));
    final sourceBefore = s.h.source.points;
    final receipt = await s.save();
    expect(receipt.serverReadbackConfirmed, isTrue);
    expect(receipt.accountKey, account);
    expect(receipt.originalUid, uid);
    expect(receipt.financialRestoreAuthorized, isFalse);
    expect(receipt.allAccountDataRestored, isFalse);
    expect(s.h.io.writes, 1);
    expect(s.h.journal.values, isEmpty);
    expect(s.h.source.points, sourceBefore);

    // The second phone can have another install ID but signs into the SAME
    // verified original Firebase Auth UID. It only receives source evidence.
    s.h.io.install = 'replacement-phone-install';
    s.h.io.user(uid);
    final read = await s.inspect();
    expect(read.capture.raw[DedaLegacyProgressPart.taskPoints], sourceBefore);
    expect(read.sourceUid, uid);
    expect(read.canRestoreBalances, isFalse);
    expect(read.canAwardPoints, isFalse);
    expect(read.canReissueGiftsOrPrizes, isFalse);
    expect(read.fullAccountRestored, isFalse);
    expect(s.h.io.writes, 1);
  });

  test('missing every old-phone source never yields a misleading backup receipt', () async {
    final s = Scenario();
    final empty = emptyOriginalPhoneFlow(s);
    await expectLater(empty.archiveOnOriginalPhone(
      accountKey: account, originalUid: uid,
      captureId: captureId, isCurrent: () => s.isCurrent,
    ), throwsA(isA<DedaProgressEvidenceMissing>()));
    expect(s.h.journal.values, isEmpty);
    expect(s.h.journal.writes, 0);
    expect(s.h.io.writes, 0);
    expect(s.reader.reads, 0);
  });

  test('legacy empty pending capture is retained but never uploaded or acknowledged', () async {
    final s = Scenario();
    final empty = emptyOriginalPhoneFlow(s);
    // Legacy prepare did not require a nonempty source. Preserve its frozen
    // intent for review rather than pretending the source was saved.
    await empty.backup.prepare(
      accountKey: account, captureId: captureId,
      isCurrent: () => s.isCurrent,
    );
    final frozen = s.h.journal.values[account];
    expect(frozen, isNotNull);
    await expectLater(empty.archiveOnOriginalPhone(
      accountKey: account, originalUid: uid,
      captureId: captureId, isCurrent: () => s.isCurrent,
    ), throwsA(isA<DedaProgressEvidenceMissing>()));
    expect(s.h.journal.values[account], frozen);
    expect(s.h.journal.removes, 0);
    expect(s.h.io.writes, 0);
  });

  test('uncertain write preserves original journal and retries without duplicate upload', () async {
    final s = Scenario();
    s.h.io.throwAfterCommit = true;
    await expectLater(s.save(), throwsStateError);
    expect(s.h.io.writes, 1);
    expect(s.h.journal.values[account], isNotNull);
    s.h.io.throwAfterCommit = false;
    final result = await s.save();
    expect(result.captureId, captureId);
    expect(s.h.io.writes, 1);
    expect(s.h.journal.values, isEmpty);
    expect((await s.inspect()).captureId, captureId);
  });

  test('wrong provider UID blocks both backup and read before server access', () async {
    final s = Scenario();
    s.currentUid = 'foreign-account-uid';
    await expectLater(s.save(), throwsA(isA<DedaStep2EvidenceHold>()));
    await expectLater(s.inspect(), throwsA(isA<DedaStep2EvidenceHold>()));
    expect(s.h.io.writes, 0);
    expect(s.reader.reads, 0);
  });

  test('account switch or stale operation blocks without deleting source data', () async {
    final s = Scenario();
    s.isCurrent = false;
    await expectLater(s.save(), throwsA(isA<DedaStep2EvidenceHold>()));
    await expectLater(s.inspect(), throwsA(isA<DedaStep2EvidenceHold>()));
    expect(s.h.source.points, isNotEmpty);
    expect(s.h.io.writes, 0);
  });

  test('missing journal acknowledgement never pretends source backup completed', () async {
    final s = Scenario();
    s.h.journal.refuseRemove = true;
    await expectLater(s.save(), throwsA(isA<DedaStep2EvidenceHold>()));
    expect(s.h.io.writes, 1);
    expect(s.h.journal.values[account], isNotNull);
  });

  test('changing source adds immutable history but cannot silently restore ambiguous balance', () async {
    final s = Scenario();
    await s.save();
    s.h.source.points = '{"ledger":["later-award"],"awards":{"new":5}}';
    await s.save(id: 'original_phone_snapshot_00000002');
    expect(s.h.io.writes, 2);
    await expectLater(s.inspect(), throwsA(isA<DedaStep2EvidenceHold>()));
    expect(s.h.source.points, contains('later-award'));
  });

  test('pilot disabled prevents both reads and archive writes', () async {
    final s = Scenario();
    final disabled = DedaStep2OriginalSourceContinuity(
      backup: s.h.backup,
      readback: DedaStep2OriginalBackupReadback(
        io: s.reader,
        currentUid: () => uid,
        verifyOriginalOwner: (_, __) async => true,
        enabled: true,
      ),
      currentUid: () => uid,
      enabled: false,
    );
    await expectLater(
      disabled.archiveOnOriginalPhone(
        accountKey: account, originalUid: uid,
        isCurrent: () => true,
      ),
      throwsA(isA<DedaStep2EvidenceHold>()),
    );
    await expectLater(
      disabled.inspectOnReplacementPhone(
        accountKey: account, originalUid: uid,
        isCurrent: () => true,
      ),
      throwsA(isA<DedaStep2EvidenceHold>()),
    );
    expect(s.h.io.writes, 0);
    expect(s.reader.reads, 0);
  });

  test('secure default capture ID is valid and never a phone number', () {
    final first = DedaStep2OriginalSourceContinuity.newCaptureId();
    final second = DedaStep2OriginalSourceContinuity.newCaptureId();
    expect(first, matches(RegExp(r'^[a-f0-9]{48}$')));
    expect(second, isNot(first));
  });
}
