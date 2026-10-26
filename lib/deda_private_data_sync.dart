import 'dart:async';
import 'dart:convert';

/// Nonfinancial records only. Native JSON text and malformed legacy entries
/// remain byte-for-byte intact; no wallet, role, ID ownership or reward enters.
class DedaPrivateDataPayload {
  DedaPrivateDataPayload(Map<String, Object?> fields)
      : fields = Map.unmodifiable(jsonDecode(jsonEncode(fields)) as Map<String, dynamic>) {
    for (final entry in this.fields.entries) {
      if (!validKey(entry.key)) throw const FormatException('unsupported-private-data-key');
      final value = entry.value;
      final list = const {'favorites', 'recent', 'quizSeen'}.contains(entry.key) || entry.key.startsWith('quiz:ids:');
      final boolean = entry.key.startsWith('quiz:completed:');
      if (value != null && (list ? !(value is List && value.every((v) => v is String))
          : boolean ? value is! bool : value is! String)) {
        throw const FormatException('invalid-private-data-value');
      }
    }
    if (utf8.encode(encode()).length > 200000) {
      throw const FormatException('private-data-too-large');
    }
  }
  final Map<String, Object?> fields;
  static bool validKey(String key) =>
      const {'favorites', 'recent', 'personalPlaces', 'contactDraft', 'quizSeen'}.contains(key) ||
      RegExp(r'^quiz:(ids|progress|completed):[0-9]{4}-[0-9]{2}-[0-9]{2}$').hasMatch(key);
  String encode() {
    final names = fields.keys.toList()..sort();
    return jsonEncode({for (final key in names) key: fields[key]});
  }
  static DedaPrivateDataPayload decode(String text) {
    final value = jsonDecode(text);
    if (value is! Map<String, dynamic>) throw const FormatException('invalid-private-data-payload');
    return DedaPrivateDataPayload(value);
  }
}

class DedaPrivateDataRevision {
  const DedaPrivateDataRevision(this.version, this.mutationId, this.payload);
  final int version;
  final String? mutationId;
  final DedaPrivateDataPayload? payload;
  void validate() {
    if (version < 0 || version > 9007199254740990 ||
        (version == 0 && (mutationId != null || payload != null)) ||
        (version > 0 && (payload == null || mutationId == null ||
          !RegExp(r'^[a-f0-9]{48}$').hasMatch(mutationId!)))) {
      throw const FormatException('invalid-private-data-revision');
    }
  }
}
class DedaPrivateDataConflict implements Exception { const DedaPrivateDataConflict(); }
class DedaPrivateDataStale implements Exception { const DedaPrivateDataStale(); }
enum DedaPrivateDataStatus { saved, pending, conflict, absent }
class DedaPrivateDataResult {
  const DedaPrivateDataResult(this.status, this.revision);
  final DedaPrivateDataStatus status;
  final DedaPrivateDataRevision revision;
}
abstract class DedaPrivateDataIo {
  Future<String?> readJournal(String account);
  Future<void> writeJournal(String account, String text);
  Future<void> preserveJournal(String account, String text);
  Future<void> verifyOwner(String account, String original, void Function() check);
  Future<DedaPrivateDataRevision> readServer(String account, String original, void Function() check);
  Future<DedaPrivateDataRevision> compareAndSet(String account, String original,
      int baseVersion, String mutationId, DedaPrivateDataPayload payload, void Function() check);
  String newMutationId();
}

class _PrivateJournal {
  _PrivateJournal(this.base, {this.pendingId, this.pending});
  DedaPrivateDataRevision base;
  String? pendingId;
  DedaPrivateDataPayload? pending;
  String encode(String account, String original) => jsonEncode({
    'format': 1, 'account': account, 'original': original,
    'version': base.version, 'mutationId': base.mutationId, 'payload': base.payload?.encode(),
    'pendingId': pendingId, 'pending': pending?.encode(),
  });
  static _PrivateJournal decode(String text, String account, String original) {
    final d = jsonDecode(text);
    const keys = {'format', 'account', 'original', 'version', 'mutationId', 'payload', 'pendingId', 'pending'};
    if (d is! Map || d.length != keys.length || !keys.every(d.containsKey) ||
        d['format'] != 1 || d['account'] != account || d['original'] != original ||
        d['version'] is! int || (d['mutationId'] != null && d['mutationId'] is! String) ||
        (d['payload'] != null && d['payload'] is! String) ||
        (d['pending'] != null && d['pending'] is! String) ||
        ((d['pending'] == null) != (d['pendingId'] == null)) ||
        (d['pendingId'] != null && (d['pendingId'] is! String ||
          !RegExp(r'^[a-f0-9]{48}$').hasMatch(d['pendingId'] as String)))) {
      throw const FormatException('invalid-private-data-journal');
    }
    final base = DedaPrivateDataRevision(d['version'] as int, d['mutationId'] as String?,
        d['payload'] == null ? null : DedaPrivateDataPayload.decode(d['payload'] as String));
    base.validate();
    return _PrivateJournal(base, pendingId: d['pendingId'] as String?,
        pending: d['pending'] == null ? null : DedaPrivateDataPayload.decode(d['pending'] as String));
  }
}

/// One journal and lane per account. A failed response retains the same request
/// ID. An old handset cannot overwrite a newer revision or resurrect deletions.
/// This class never applies records to native preferences; the caller must first
/// obtain a verified restore and preserve existing local records separately.
class DedaPrivateDataSync {
  DedaPrivateDataSync(this.io);
  final DedaPrivateDataIo io;
  final Map<String, Future<void>> _lanes = {};
  Future<T> _run<T>(String account, String original, bool Function() current,
      Future<T> Function(void Function() check) action) async {
    if (!RegExp(r'^[0-9]+$').hasMatch(account) ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(original)) {
      throw ArgumentError('invalid-private-data-account');
    }
    void check() { if (!current()) throw const DedaPrivateDataStale(); }
    check();
    final before = _lanes[account], complete = Completer<void>();
    _lanes[account] = complete.future;
    try {
      if (before != null) await before;
      check();
      return await action(check);
    } finally {
      complete.complete();
      if (identical(_lanes[account], complete.future)) _lanes.remove(account);
    }
  }
  Future<_PrivateJournal> _journal(String account, String original, void Function() check) async {
    final text = await io.readJournal(account); check();
    return text == null ? _PrivateJournal(const DedaPrivateDataRevision(0, null, null))
        : _PrivateJournal.decode(text, account, original);
  }
  Future<void> _save(String account, String original, _PrivateJournal journal,
      void Function() check) async {
    check(); final text = journal.encode(account, original);
    _PrivateJournal.decode(text, account, original);
    await io.writeJournal(account, text); check();
  }
  Future<DedaPrivateDataResult> backup({required String account, required String original,
      required DedaPrivateDataPayload payload, required bool Function() isCurrent}) =>
    _run(account, original, isCurrent, (check) async {
      final journal = await _journal(account, original, check);
      // Do not create a new request ID for an unchanged uncertain save.
      if (journal.pending?.encode() != payload.encode()) {
        if (journal.pending != null) {
          await io.preserveJournal(account, journal.encode(account, original)); check();
        }
        journal.pending = payload; journal.pendingId = io.newMutationId();
        await _save(account, original, journal, check);
      }
      try {
        await io.verifyOwner(account, original, check); check();
        final remote = await io.readServer(account, original, check); check(); remote.validate();
        if (remote.mutationId == journal.pendingId) {
          if (remote.payload?.encode() != journal.pending!.encode()) {
            throw const FormatException('private-data-replay-conflict');
          }
          journal.base = remote; journal.pending = null; journal.pendingId = null;
          await _save(account, original, journal, check);
          return DedaPrivateDataResult(DedaPrivateDataStatus.saved, remote);
        }
        if (remote.version != journal.base.version ||
            remote.mutationId != journal.base.mutationId ||
            remote.payload?.encode() != journal.base.payload?.encode()) {
          return DedaPrivateDataResult(DedaPrivateDataStatus.conflict, remote);
        }
        final next = await io.compareAndSet(account, original, journal.base.version,
            journal.pendingId!, journal.pending!, check); check(); next.validate();
        if (next.version != journal.base.version + 1 || next.mutationId != journal.pendingId ||
            next.payload?.encode() != journal.pending!.encode()) {
          throw const FormatException('private-data-write-not-confirmed');
        }
        journal.base = next; journal.pendingId = null; journal.pending = null;
        await _save(account, original, journal, check);
        return DedaPrivateDataResult(DedaPrivateDataStatus.saved, next);
      } on DedaPrivateDataConflict {
        check(); return DedaPrivateDataResult(DedaPrivateDataStatus.conflict, journal.base);
      } on DedaPrivateDataStale { rethrow; }
      on FormatException { rethrow; }
      catch (_) {
        check(); return DedaPrivateDataResult(DedaPrivateDataStatus.pending, journal.base);
      }
    });
  Future<DedaPrivateDataResult> restore({required String account, required String original,
      required bool Function() isCurrent, bool discardPending = false}) =>
    _run(account, original, isCurrent, (check) async {
      final journal = await _journal(account, original, check);
      await io.verifyOwner(account, original, check); check();
      final remote = await io.readServer(account, original, check); check(); remote.validate();
      if (remote.version == 0) return DedaPrivateDataResult(DedaPrivateDataStatus.absent, remote);
      if (remote.version < journal.base.version || (remote.version == journal.base.version &&
          (remote.mutationId != journal.base.mutationId ||
            remote.payload?.encode() != journal.base.payload?.encode()))) {
        throw const FormatException('private-data-server-regressed');
      }
      if (journal.pending != null && !discardPending) {
        return DedaPrivateDataResult(DedaPrivateDataStatus.conflict, remote);
      }
      // Even a deliberate replacement retains the previous local intent.
      await io.preserveJournal(account, journal.encode(account, original)); check();
      journal.base = remote; journal.pending = null; journal.pendingId = null;
      await _save(account, original, journal, check);
      return DedaPrivateDataResult(DedaPrivateDataStatus.saved, remote);
    });
}
