import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DedaSixUserRecord {
  const DedaSixUserRecord(this.id, this.fields);
  final String id;
  final Map<String, dynamic> fields;
}

class DedaSixAdminUserRow {
  const DedaSixAdminUserRow({required this.accountKey, required this.ownerUid,
    required this.sourceCollection, required this.sourceId,
    required this.registeredAt, required this.profile});
  final String accountKey, ownerUid, sourceCollection, sourceId;
  final DateTime? registeredAt;
  final Map<String, dynamic> profile;
  String get id => accountKey;
  Map<String, dynamic> data() => profile;
}

/// An account directory, never a list of renewable Firebase sessions.
/// Existing session documents remain untouched because authorization uses them.
class DedaSixAdminUsers {
  static String _text(Object? value) => (value ?? '').toString().trim();
  static String _key(Map<String, dynamic> data) {
    final key = _text(data['accountKey']);
    return key.isNotEmpty ? key : _text(data['phone']).replaceAll(RegExp(r'[^0-9]'), '');
  }
  static DateTime? _date(Object? value) => value is Timestamp ? value.toDate()
      : value is DateTime ? value : null;

  static List<DedaSixAdminUserRow> rows({
    required Iterable<DedaSixUserRecord> profiles,
    required Iterable<DedaSixUserRecord> sessions,
  }) {
    final canonical = <String, DedaSixUserRecord>{};
    final groups = <String, List<DedaSixUserRecord>>{};
    for (final record in profiles) {
      final key = _key(record.fields);
      if (key.isNotEmpty && key == record.id) canonical[key] = record;
    }
    for (final record in sessions) {
      final key = _key(record.fields);
      if (key.isNotEmpty) groups.putIfAbsent(key, () => []).add(record);
    }
    final result = <DedaSixAdminUserRow>[];
    for (final key in {...canonical.keys, ...groups.keys}) {
      final master = canonical[key];
      final records = List<DedaSixUserRecord>.of(groups[key] ?? []);
      records.sort((a, b) {
        final ad = _date(a.fields['updatedAt']) ?? _date(a.fields['createdAt']);
        final bd = _date(b.fields['updatedAt']) ?? _date(b.fields['createdAt']);
        final order = (bd?.microsecondsSinceEpoch ?? -1)
            .compareTo(ad?.microsecondsSinceEpoch ?? -1);
        return order != 0 ? order : a.id.compareTo(b.id);
      });
      final latest = records.isEmpty ? null : records.first;
      final profile = Map<String, dynamic>.from(master?.fields ?? {});
      // Refresh displayed metadata from a matching session, without using
      // its last visit as the account registration time.
      if (latest != null) {
        for (final field in ['name', 'phone', 'accountType']) {
          if (_text(latest.fields[field]).isNotEmpty) profile[field] = latest.fields[field];
        }
      }
      profile['accountKey'] = key;
      final firstDates = records.map((r) => _date(r.fields['createdAt']))
          .whereType<DateTime>().toList()..sort();
      final registered = _date(master?.fields['createdAt']) ??
          (firstDates.isEmpty ? null : firstDates.first);
      result.add(DedaSixAdminUserRow(accountKey: key,
        ownerUid: latest?.id ?? '', registeredAt: registered, profile: profile,
        sourceCollection: master != null ? 'deda_account_profiles' : 'users',
        sourceId: master?.id ?? latest!.id));
    }
    result.sort((a, b) {
      final order = (b.registeredAt?.microsecondsSinceEpoch ?? -1)
          .compareTo(a.registeredAt?.microsecondsSinceEpoch ?? -1);
      return order != 0 ? order : a.accountKey.compareTo(b.accountKey);
    });
    return result;
  }

  static Stream<List<DedaSixAdminUserRow>> watch() {
    late StreamController<List<DedaSixAdminUserRow>> output;
    final subscriptions = <StreamSubscription<dynamic>>[];
    var masters = <DedaSixUserRecord>[], sessions = <DedaSixUserRecord>[];
    var mastersDone = false, sessionsDone = false, stopped = false;
    Object? mastersError, sessionsError;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    void publish() {
      if (stopped || !mastersDone || !sessionsDone) return;
      if (FirebaseAuth.instance.currentUser?.uid != uid || uid == null) {
        output.addError(StateError('admin-account-changed')); return;
      }
      if (mastersError != null && sessionsError != null) {
        output.addError(mastersError!); return;
      }
      output.add(rows(profiles: masters, sessions: sessions));
    }
    List<DedaSixUserRecord> records(QuerySnapshot<Map<String, dynamic>> s) =>
        s.docs.map((d) => DedaSixUserRecord(d.id, d.data())).toList();
    output = StreamController<List<DedaSixAdminUserRow>>(
      onListen: () {
        if (uid == null) {
          output.addError(StateError('signed-in-admin-required')); return;
        }
        // No limit on raw UIDs: duplicates must not consume a limit and hide
        // a newly registered canonical account. Existing Firestore admin rules
        // remain the access boundary; no permission or user document is changed.
        subscriptions.add(FirebaseFirestore.instance.collection('deda_account_profiles')
            .snapshots().listen((s) {
          masters = records(s); mastersDone = true; mastersError = null; publish();
        }, onError: (Object e) {
          masters = []; mastersDone = true; mastersError = e; publish();
        }));
        subscriptions.add(FirebaseFirestore.instance.collection('users')
            .snapshots().listen((s) {
          sessions = records(s); sessionsDone = true; sessionsError = null; publish();
        }, onError: (Object e) {
          sessions = []; sessionsDone = true; sessionsError = e; publish();
        }));
        subscriptions.add(FirebaseAuth.instance.authStateChanges().listen((user) {
          if (!stopped && user?.uid != uid) {
            masters = []; sessions = [];
            output.addError(StateError('admin-account-changed'));
          }
        }));
      },
      onCancel: () async {
        stopped = true;
        for (final subscription in subscriptions) { await subscription.cancel(); }
      },
    );
    return output.stream;
  }
}
