import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'deda_step2_owner_place_local_archive.dart';

/// This is only a durable old-phone SOURCE archive. Not restoration of
/// published map ownership, rewards, purchases, or an account login.
class DedaStep2OwnerPlacePending {
  DedaStep2OwnerPlacePending({
    required this.accountKey,
    required this.originalUid,
    required this.captureId,
    required this.source,
  }) {
    if (!RegExp(r'^[0-9]{8,16}$').hasMatch(accountKey) ||
        originalUid.isEmpty || originalUid.length > 128 ||
        !RegExp(r'^[A-Za-z0-9_-]{20,80}$').hasMatch(captureId) ||
        source.accountKey != accountKey || !source.hasAnyEvidence) {
      throw const DedaStep2OwnerPlaceArchiveHold('invalid-pending-place-intent');
    }
  }

  final String accountKey, originalUid, captureId;
  final DedaStep2OwnerPlaceSource source;

  String encode() => jsonEncode({
    'format': 1,
    'accountKey': accountKey,
    'originalUid': originalUid,
    'captureId': captureId,
    'records': source.toRecords(),
  });

  static DedaStep2OwnerPlacePending decode(
      String encoded, String accountKey) {
    final Object? json;
    try {
      json = jsonDecode(encoded);
    } catch (_) {
      throw const DedaStep2OwnerPlaceArchiveHold('malformed-place-journal');
    }
    if (json is! Map ||
        json.length != 5 ||
        !['format','accountKey','originalUid','captureId','records']
            .every(json.containsKey) ||
        json['format'] != 1 || json['accountKey'] != accountKey ||
        json['originalUid'] is! String ||
        json['captureId'] is! String ||
        json['records'] is! Map) {
      throw const DedaStep2OwnerPlaceArchiveHold('invalid-place-journal');
    }
    try {
      final source = DedaStep2OwnerPlaceSource.checked(accountKey,
          Map<String, dynamic>.from(json['records'] as Map));
      return DedaStep2OwnerPlacePending(
        accountKey: accountKey,
        originalUid: json['originalUid'] as String,
        captureId: json['captureId'] as String,
        source: source,
      );
    } catch (_) {
      throw const DedaStep2OwnerPlaceArchiveHold('invalid-place-journal');
    }
  }
}

abstract class DedaStep2OwnerPlacePendingJournal {
  Future<String?> read(String accountKey);
  Future<void> writeOnce(
      String accountKey, String encoded, void Function() check);
  Future<bool> removeIfSame(
      String accountKey, String encoded, void Function() check);
}

class DedaStep2OwnerPlacePrefsJournal
    implements DedaStep2OwnerPlacePendingJournal {
  const DedaStep2OwnerPlacePrefsJournal();
  static final Set<String> _mutating = {};

  String _key(String accountKey) {
    if (!RegExp(r'^[0-9]{8,16}$').hasMatch(accountKey)) {
      throw const DedaStep2OwnerPlaceArchiveHold('invalid-place-journal-scope');
    }
    return 'deda_step2_owner_place_pending_v1_$accountKey';
  }

  Future<T> _change<T>(String accountKey,
      Future<T> Function(SharedPreferences prefs, String key) action) async {
    final key = _key(accountKey);
    if (!_mutating.add(key)) {
      throw const DedaStep2OwnerPlaceArchiveHold('place-journal-busy');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      return await action(prefs, key);
    } finally {
      _mutating.remove(key);
    }
  }

  @override
  Future<String?> read(String accountKey) async =>
      (await SharedPreferences.getInstance()).getString(_key(accountKey));

  @override
  Future<void> writeOnce(String accountKey, String encoded,
      void Function() check) => _change(accountKey, (prefs, key) async {
    check();
    final old = prefs.getString(key);
    if (old != null) {
      if (old != encoded) {
        throw const DedaStep2OwnerPlaceArchiveHold(
            'place-journal-existing-different-intent');
      }
      return;
    }
    if (!await prefs.setString(key, encoded)) {
      throw const DedaStep2OwnerPlaceArchiveHold('place-journal-write-failed');
    }
    check();
    if (prefs.getString(key) != encoded) {
      throw const DedaStep2OwnerPlaceArchiveHold('place-journal-not-durable');
    }
  });

  @override
  Future<bool> removeIfSame(String accountKey, String encoded,
      void Function() check) => _change(accountKey, (prefs, key) async {
    check();
    if (prefs.getString(key) != encoded) return false;
    final removed = await prefs.remove(key);
    check();
    return removed && prefs.getString(key) == null;
  });
}

class DedaStep2OwnerPlaceBackupReceipt {
  const DedaStep2OwnerPlaceBackupReceipt({
    required this.captureId,
    required this.source,
    required this.journalCleared,
  });
  final String captureId;
  final DedaStep2OwnerPlaceSource source;
  final bool journalCleared;
  bool get canTransferPlaceOwnership => false;
  bool get allAccountDataRestored => false;
}

/// Freeze the exact old-phone values in a local journal BEFORE any cloud call.
/// Uncertain responses preserve the same source bytes and capture ID. A newer
/// old-phone draft can be captured only after the prior snapshot is resolved.
class DedaStep2OwnerPlaceDurableBackup {
  DedaStep2OwnerPlaceDurableBackup({
    required this.archive,
    required this.journal,
    this.enabled = dedaStep2OwnerPlaceLocalArchiveEnabled,
  });

  final DedaStep2OwnerPlaceLocalArchive archive;
  final DedaStep2OwnerPlacePendingJournal journal;
  final bool enabled;
  bool _busy = false;

  static String newCaptureId() {
    final random = Random.secure();
    return List.generate(24, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  void _check(bool Function() isCurrent) {
    if (!enabled || !archive.enabled || !isCurrent()) {
      throw const DedaStep2OwnerPlaceArchiveHold(
          'place-durable-backup-not-authorized');
    }
  }

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    if (_busy) {
      throw const DedaStep2OwnerPlaceArchiveHold('place-backup-busy');
    }
    _busy = true;
    try {
      return await action();
    } finally {
      _busy = false;
    }
  }

  Future<DedaStep2OwnerPlacePending> prepare({
    required String accountKey,
    required String originalUid,
    required bool Function() isCurrent,
    String? captureId,
  }) => _exclusive(() async {
    _check(isCurrent);
    await archive.proveOriginalOwner(
        accountKey: accountKey, originalUid: originalUid,
        isCurrent: isCurrent);
    _check(isCurrent);
    final pending = await journal.read(accountKey);
    _check(isCurrent);
    if (pending != null) {
      final previous = DedaStep2OwnerPlacePending.decode(
          pending, accountKey);
      if (previous.originalUid != originalUid) {
        throw const DedaStep2OwnerPlaceArchiveHold(
            'place-journal-original-owner-changed');
      }
      return previous;
    }

    final source = await DedaStep2OwnerPlaceSource.readOriginal(
      archive.local, accountKey: accountKey,
      isCurrent: isCurrent,
    );
    _check(isCurrent);
    // A place-owner account with no original local place data must not
    // acquire an empty, unrecoverable pending journal. Do not invent place
    // ownership or create a cloud receipt that can never be acknowledged.
    if (!source.hasAnyEvidence) {
      throw const DedaStep2OwnerPlaceArchiveHold(
          'no-original-place-source-to-archive');
    }
    final intent = DedaStep2OwnerPlacePending(
      accountKey: accountKey, originalUid: originalUid,
      captureId: captureId ?? newCaptureId(), source: source,
    );
    await journal.writeOnce(accountKey, intent.encode(),
        () => _check(isCurrent));
    _check(isCurrent);
    if (await journal.read(accountKey) != intent.encode()) {
      throw const DedaStep2OwnerPlaceArchiveHold(
          'place-journal-readback-mismatch');
    }
    _check(isCurrent);
    return intent;
  });

  Future<DedaStep2OwnerPlaceBackupReceipt> uploadPending({
    required String accountKey,
    required String originalUid,
    required bool Function() isCurrent,
  }) => _exclusive(() async {
    _check(isCurrent);
    await archive.proveOriginalOwner(
        accountKey: accountKey, originalUid: originalUid,
        isCurrent: isCurrent);
    _check(isCurrent);
    final encoded = await journal.read(accountKey);
    _check(isCurrent);
    if (encoded == null) {
      throw const DedaStep2OwnerPlaceArchiveHold('place-journal-missing');
    }
    final intent = DedaStep2OwnerPlacePending.decode(encoded, accountKey);
    if (intent.originalUid != originalUid) {
      throw const DedaStep2OwnerPlaceArchiveHold(
          'place-journal-original-owner-changed');
    }
    final confirmed = await archive.archivePreparedOriginal(
      source: intent.source, accountKey: accountKey,
      originalUid: originalUid, captureId: intent.captureId,
      isCurrent: isCurrent,
    );
    _check(isCurrent);
    // Do not retire an unresolved (or replaced) pending entry.
    final cleared = await journal.removeIfSame(
        accountKey, encoded, () => _check(isCurrent));
    _check(isCurrent);
    return DedaStep2OwnerPlaceBackupReceipt(
      captureId: intent.captureId,
      source: confirmed,
      journalCleared: cleared,
    );
  });
}
