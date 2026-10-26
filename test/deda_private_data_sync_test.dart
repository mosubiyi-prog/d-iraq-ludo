import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_private_data_sync.dart';

const account = '07700000000', original = '@DEDA-ABC234';
DedaPrivateDataPayload data(String name) => DedaPrivateDataPayload({
  'favorites': <String>['{"name":"$name"}', 'malformed saved item'],
  'recent': <String>[], 'personalPlaces': '[{"name":"$name"}]',
  'contactDraft': '{unparsed legacy draft', 'quizSeen': <String>['q1'],
  'quiz:ids:2026-10-26': <String>['q1', 'q2'],
  'quiz:progress:2026-10-26': '{"index":1,"answers":{"q1":2}}',
  'quiz:completed:2026-10-26': true,
});
class Server {
  final values = <String, DedaPrivateDataRevision>{};
  int writes = 0;
}
class Io implements DedaPrivateDataIo {
  Io(this.server, this.device);
  final Server server;
  final int device;
  final journals = <String, String>{}, archives = <String>[];
  int ids = 0, proofs = 0;
  bool deny = false, offline = false, loseReply = false, failLocal = false;
  Future<void> Function()? beforeProof, beforeWrite;
  @override String newMutationId() => '${device.toRadixString(16).padLeft(24, '0')}${(++ids).toRadixString(16).padLeft(24, '0')}';
  @override Future<String?> readJournal(String a) async => journals[a];
  @override Future<void> writeJournal(String a, String text) async {
    if (failLocal) throw StateError('local persistence unavailable');
    journals[a] = text;
  }
  @override Future<void> preserveJournal(String a, String text) async { archives.add(text); }
  @override Future<void> verifyOwner(String a, String o, void Function() check) async {
    proofs++; await beforeProof?.call(); check();
    if (deny || offline) throw StateError('owner/network unavailable');
  }
  @override Future<DedaPrivateDataRevision> readServer(String a, String o, void Function() check) async {
    check(); if (offline) throw StateError('network unavailable');
    return server.values[a] ?? const DedaPrivateDataRevision(0, null, null);
  }
  @override Future<DedaPrivateDataRevision> compareAndSet(String a, String o, int version,
      String id, DedaPrivateDataPayload payload, void Function() check) async {
    await beforeWrite?.call(); check();
    final old = server.values[a] ?? const DedaPrivateDataRevision(0, null, null);
    if (old.version != version) throw const DedaPrivateDataConflict();
    final next = DedaPrivateDataRevision(version + 1, id, payload);
    server.values[a] = next; server.writes++;
    if (loseReply) { loseReply = false; throw StateError('reply lost after commit'); }
    return next;
  }
}
Future<DedaPrivateDataResult> save(DedaPrivateDataSync sync, DedaPrivateDataPayload value,
    {bool Function()? current}) => sync.backup(account: account, original: original,
      payload: value, isCurrent: current ?? () => true);
Future<DedaPrivateDataResult> restore(DedaPrivateDataSync sync, {bool discard = false}) =>
    sync.restore(account: account, original: original, isCurrent: () => true, discardPending: discard);

void main() {
  test('a second device restores every allowlisted record without parsing damaged native text', () async {
    final server = Server(), first = Io(Server(), 1);
    final a = Io(server, 1), b = Io(server, 2);
    expect((await save(DedaPrivateDataSync(a), data('A'))).status, DedaPrivateDataStatus.saved);
    final result = await restore(DedaPrivateDataSync(b));
    expect(result.revision.payload!.encode(), data('A').encode());
    expect(server.writes, 1); expect(first.server.writes, 0);
    expect(result.revision.payload!.fields['contactDraft'], '{unparsed legacy draft');
  });
  test('missing remote data is absence, never an empty write or local wipe', () async {
    final io = Io(Server(), 1), sync = DedaPrivateDataSync(Io(Server(), 2));
    expect((await restore(sync)).status, DedaPrivateDataStatus.absent);
    expect(io.server.writes, 0); expect(io.journals, isEmpty);
  });
  test('deletions and empty lists survive recovery and an old device cannot resurrect them', () async {
    final server = Server(), a = Io(Server(), 1);
    final first = Io(server, 1), second = Io(server, 2);
    final x = DedaPrivateDataSync(first), y = DedaPrivateDataSync(second);
    await save(x, data('A')); await restore(y);
    final deleted = DedaPrivateDataPayload({'favorites': <String>[], 'personalPlaces': null});
    await save(y, deleted);
    expect((await save(x, data('stale'))).status, DedaPrivateDataStatus.conflict);
    expect(server.values[account]!.payload!.encode(), deleted.encode());
    expect(a.server.writes, 0);
  });
  test('lost response reuses the exact request ID and never writes a second version', () async {
    final server = Server(), io = Io(Server(), 1);
    final actual = Io(server, 2)..loseReply = true, sync = DedaPrivateDataSync(io);
    final owner = DedaPrivateDataSync(actual);
    expect((await save(owner, data('A'))).status, DedaPrivateDataStatus.pending);
    final id = server.values[account]!.mutationId;
    expect((await save(owner, data('A'))).status, DedaPrivateDataStatus.saved);
    expect(server.values[account]!.mutationId, id); expect(server.writes, 1);
    expect((await restore(sync)).status, DedaPrivateDataStatus.absent);
  });
  test('offline backup keeps a durable pending snapshot and later explicit retry succeeds', () async {
    final io = Io(Server(), 1)..offline = true, sync = DedaPrivateDataSync(Io(Server(), 2));
    final pending = DedaPrivateDataSync(io);
    expect((await save(pending, data('A'))).status, DedaPrivateDataStatus.pending);
    expect(io.journals[account], contains('malformed saved item'));
    expect(io.server.writes, 0); io.offline = false;
    expect((await save(pending, data('A'))).status, DedaPrivateDataStatus.saved);
    expect((await restore(sync)).status, DedaPrivateDataStatus.absent);
  });
  test('foreign account cannot read another account or publish a copied snapshot', () async {
    final io = Io(Server(), 1)..deny = true, sync = DedaPrivateDataSync(Io(Server(), 2));
    await expectLater(restore(DedaPrivateDataSync(io)), throwsStateError);
    expect((await save(DedaPrivateDataSync(io), data('A'))).status, DedaPrivateDataStatus.pending);
    expect(io.server.writes, 0); expect((await restore(sync)).status, DedaPrivateDataStatus.absent);
  });
  test('pending data cannot be discarded implicitly by Restore', () async {
    final server = Server(), a = Io(Server(), 1);
    final io = Io(server, 1), sync = DedaPrivateDataSync(io);
    await save(sync, data('A')); io.offline = true; await save(sync, data('pending'));
    io.offline = false;
    expect((await restore(sync)).status, DedaPrivateDataStatus.conflict);
    expect(io.journals[account], contains('pending'));
    expect((await restore(sync, discard: true)).revision.payload!.encode(), data('A').encode());
    expect(io.archives.any((s) => s.contains('pending')), isTrue);
    expect(server.writes, 1); expect(a.server.writes, 0);
  });
  test('local journal persistence failure performs no owner read or server write', () async {
    final io = Io(Server(), 1)..failLocal = true;
    await expectLater(save(DedaPrivateDataSync(io), data('A')), throwsStateError);
    expect(io.proofs, 0); expect(io.server.writes, 0);
  });
  test('account selection changes before a delayed proof prevent the server write', () async {
    final io = Io(Server(), 1), hold = Completer<void>(); var current = true;
    io.beforeProof = () => hold.future;
    final future = save(DedaPrivateDataSync(io), data('A'), current: () => current);
    final assertion = expectLater(future, throwsA(isA<DedaPrivateDataStale>()));
    await Future<void>.delayed(Duration.zero); current = false; hold.complete(); await assertion;
    expect(io.server.writes, 0);
  });
  test('transaction race preserves the other device and keeps local pending data', () async {
    final server = Server(), a = Io(server, 1), b = Io(server, 2);
    a.beforeWrite = () async { await save(DedaPrivateDataSync(b), data('B')); };
    expect((await save(DedaPrivateDataSync(a), data('A'))).status, DedaPrivateDataStatus.conflict);
    expect(server.values[account]!.payload!.encode(), data('B').encode());
    expect(a.journals[account], contains('pending')); expect(server.writes, 1);
  });
  test('account journals are isolated and malformed journals are preserved instead of reset', () async {
    final io = Io(Server(), 1); io.journals[account] = '{bad journal';
    await expectLater(save(DedaPrivateDataSync(io), data('A')), throwsFormatException);
    expect(io.journals[account], '{bad journal'); expect(io.server.writes, 0);
  });
  for (final key in ['points', 'coins', 'xp', 'earnedDiamonds', 'role', 'ownedFrames', 'identifiers', 'uid']) {
    test('private backup cannot contain $key', () {
      expect(() => DedaPrivateDataPayload({key: '1000000'}), throwsFormatException);
    });
  }
  for (final pair in <(String, Object)>[
    ('favorites', 'not a native string list'), ('personalPlaces', <String>[]),
    ('quiz:completed:2026-10-26', 'true'), ('quiz:ids:2026-10-26', <int>[1]),
  ]) {
    test('native value type is checked for ${pair.$1}', () {
      expect(() => DedaPrivateDataPayload({pair.$1: pair.$2}), throwsFormatException);
    });
  }
  test('oversized backup fails without truncating source records', () {
    expect(() => DedaPrivateDataPayload({'contactDraft': 'x' * 200001}), throwsFormatException);
  });
  test('alias is not an account recovery identity', () async {
    final io = Io(Server(), 1);
    await expectLater(DedaPrivateDataSync(io).backup(account: account, original: '@DEDA-2020',
      payload: data('A'), isCurrent: () => true), throwsArgumentError);
    expect(io.proofs, 0);
  });
}
