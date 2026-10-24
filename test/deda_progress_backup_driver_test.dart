import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_owner_session_firebase_port.dart';
import 'package:d_iraq_ludo/deda_session_flow_prototype.dart';
import 'package:d_iraq_ludo/deda_progress_backup_coordinator.dart';
import 'package:d_iraq_ludo/deda_progress_backup_runtime.dart';
import 'package:d_iraq_ludo/deda_progress_evidence_store.dart';
import 'package:d_iraq_ludo/deda_legacy_progress_capture.dart';

import 'deda_progress_backup_coordinator_test.dart' as fixture;

/// Any attempt to use owner IO for auth or writes fails this composition test.
class ObservedSession implements DedaOwnerSessionIo {
  ObservedSession(this.io);
  final fixture.Io io;
  @override
  bool get ready => io.ready;
  @override
  DedaFlowSdkUser? get currentUser => io.currentUser;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('unexpected-session-mutation');
}
void main() {
  late fixture.Io io;
  late fixture.Source source;
  late fixture.Journal journal;
  late DedaProgressBackupCoordinator coordinator;
  late DedaFirebaseProgressBackupDriver driver;
  setUp(() {
    io = fixture.Io(); source = fixture.Source(); journal = fixture.Journal();
    coordinator = DedaProgressBackupCoordinator(reader: DedaLegacyProgressReader(source),
      archive: DedaProgressEvidenceStore(io), journal: journal);
    driver = DedaFirebaseProgressBackupDriver.forTesting(session: ObservedSession(io),
      coordinator: coordinator, dispose: () async {});
  });
  tearDown(() => driver.dispose());
  test('driver archives original capture, then skips unchanged text after fresh owner proof', () async {
    expect(await driver.backup(fixture.account, () => true), isTrue);
    expect(io.writes, 1); expect(journal.values, isEmpty);
    final reads = io.readEvents.length;
    expect(await driver.backup(fixture.account, () => true), isFalse);
    expect(io.writes, 1); expect(io.readEvents.length, greaterThan(reads));
    expect(io.docs.keys.where((p) => p.startsWith('deda_progress_evidence/')).length, 1);
  });
  test('changed source produces a fresh immutable 48-hex capture without modifying source', () async {
    await driver.backup(fixture.account, () => true);
    source.points = ' {"awards":{"new":5,"spent":-2}} ';
    await driver.backup(fixture.account, () => true);
    expect(io.writes, 2);
    final paths = io.docs.keys.where((p) => p.startsWith('deda_progress_evidence/')).toList();
    expect(paths.length, 2);
    for (final path in paths) { expect(path.split('/').last, matches(RegExp(r'^[a-f0-9]{48}$'))); }
    expect(source.points, ' {"awards":{"new":5,"spent":-2}} ');
  });
  test('acknowledgement cache cannot bypass missing users ownership proof', () async {
    await driver.backup(fixture.account, () => true);
    io.docs.remove('users/old-device');
    await expectLater(driver.backup(fixture.account, () => true), throwsA(isA<DedaSessionProofRejected>()));
    expect(io.writes, 1);
  });
  test('pending older capture wins over cache and current local changes', () async {
    await driver.backup(fixture.account, () => true);
    source.points = '{"pending":"original"}';
    final intent = await coordinator.prepare(accountKey: fixture.account,
      captureId: 'runtime_pending_original_00001', isCurrent: () => true);
    source.points = '{"current":"do not overwrite"}';
    await driver.backup(fixture.account, () => true);
    final document = io.docs['deda_progress_evidence/${fixture.account}/captures/${intent.captureId}']!;
    expect((document['records'] as Map)['taskPoints'], '{"pending":"original"}');
    expect(source.points, '{"current":"do not overwrite"}');
    expect(journal.values, isEmpty);
    await driver.backup(fixture.account, () => true); expect(io.writes, 3);
  });
  test('lost acknowledgement reuses server capture and retained journal rather than new upload', () async {
    io.throwAfterCommit = true;
    await expectLater(driver.backup(fixture.account, () => true), throwsA(anything));
    final encoded = journal.values[fixture.account];
    expect(encoded, isNotNull); expect(io.writes, 1);
    io.throwAfterCommit = false;
    expect(await driver.backup(fixture.account, () => true), isTrue);
    expect(io.writes, 1); expect(journal.values, isEmpty);
    expect(await driver.backup(fixture.account, () => true), isFalse);
  });
  test('replacement UID cannot relabel a missing old pending capture', () async {
    await coordinator.prepare(accountKey: fixture.account,
      captureId: 'runtime_old_origin_pending_00001', isCurrent: () => true);
    final encoded = journal.values[fixture.account];
    io.user('new-device');
    await expectLater(driver.backup(fixture.account, () => true), throwsA(isA<DedaProgressBackupOriginChanged>()));
    expect(journal.values[fixture.account], encoded); expect(io.writes, 0);
  });
}
