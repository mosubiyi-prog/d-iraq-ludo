import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Exact legacy local sources, not a new wallet or a server balance proof.
enum DedaLegacyProgressPart { taskPoints, socialCoinsAndXp, earnedDiamonds }

String _account(String value) {
  if (!RegExp(r'^[0-9]+$').hasMatch(value)) {
    throw ArgumentError('invalid-legacy-account-key');
  }
  return value;
}
String _key(DedaLegacyProgressPart part, String account) {
  switch (part) {
    case DedaLegacyProgressPart.taskPoints: return 'deda_task_points_state_v1_$account';
    case DedaLegacyProgressPart.socialCoinsAndXp: return 'deda_social_progress_v1_$account';
    case DedaLegacyProgressPart.earnedDiamonds: return 'deda_diamonds_wallet_v1_$account';
  }
}

abstract class DedaLegacyProgressReadStore {
  /// Read only these keys. No clear, set, migration or zero-default operation.
  Future<Map<String,String?>> readStrings(List<String> keys);
}

class DedaSharedPreferencesProgressReadStore implements DedaLegacyProgressReadStore {
  @override
  Future<Map<String,String?>> readStrings(List<String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    // Deliberately propagate wrong native types, instead of replacing them
    // with empty/zero state. The original preferences remain unchanged.
    return {for (final key in keys) key:prefs.getString(key)};
  }
}

/// Private, UNTRUSTED local evidence for future reconciliation. Lossless text
/// includes spends, reservations and claim IDs, even malformed legacy JSON.
/// Do not upload/use this as spendable balance, ownership or reward authority.
class DedaLegacyProgressCapture {
  DedaLegacyProgressCapture._(this.accountKey, Map<DedaLegacyProgressPart,String?> raw)
      : raw = Map.unmodifiable(raw);
  final String accountKey;
  final Map<DedaLegacyProgressPart,String?> raw;

  bool get hasAnyLocalRecord => raw.values.any((value)=>value != null);

  /// A non-object or malformed legacy payload stays preserved for review.
  /// This structural check does not validate amounts, claims or provenance.
  bool hasObjectPayload(DedaLegacyProgressPart part) {
    final text = raw[part];
    if (text == null) return false;
    try { return jsonDecode(text) is Map; } catch (_) { return false; }
  }

  String encode() => jsonEncode({
    'format':1,'accountKey':accountKey,
    'records':{for(final part in DedaLegacyProgressPart.values) part.name:raw[part]},
  });

  /// Decode only for the already verified SAME canonical account. Account
  /// matching alone is not authentication; the caller supplies server proof.
  static DedaLegacyProgressCapture decodeForAccount(String encoded,{required String expectedAccountKey}) {
    _account(expectedAccountKey);
    final dynamic value = jsonDecode(encoded);
    if (value is! Map || value.length != 3 || value['format'] != 1 ||
        value['accountKey'] != expectedAccountKey || value['records'] is! Map) {
      throw const FormatException('invalid-legacy-progress-envelope');
    }
    final records = value['records'] as Map;
    if (records.length != DedaLegacyProgressPart.values.length) {
      throw const FormatException('invalid-legacy-progress-records');
    }
    final raw = <DedaLegacyProgressPart,String?>{};
    for(final part in DedaLegacyProgressPart.values) {
      if (!records.containsKey(part.name) || (records[part.name] != null && records[part.name] is! String)) {
        throw const FormatException('invalid-legacy-progress-record');
      }
      raw[part] = records[part.name] as String?;
    }
    return DedaLegacyProgressCapture._(expectedAccountKey,raw);
  }
}

class DedaLegacyProgressCaptureStale implements Exception {
  const DedaLegacyProgressCaptureStale();
}

/// Unwired read-only capture. isCurrent must include the account-intent epoch
/// (A -> B -> A), not merely equality of the final phone or SDK UID.
class DedaLegacyProgressReader {
  DedaLegacyProgressReader(this.store);
  final DedaLegacyProgressReadStore store;

  Future<DedaLegacyProgressCapture> capture({required String accountKey,
    required bool Function() isCurrent}) async {
    _account(accountKey);
    void check() { if (!isCurrent()) throw const DedaLegacyProgressCaptureStale(); }
    check();
    final keys = [for(final part in DedaLegacyProgressPart.values) _key(part,accountKey)];
    final values = await store.readStrings(List.unmodifiable(keys));
    check();
    // A missing value is explicit null; a missing key is an incomplete read,
    // never a new account/zero balance. Unexpected keys cannot enter a bundle.
    if (values.length != keys.length || keys.any((key)=>!values.containsKey(key))) {
      throw const FormatException('incomplete-legacy-progress-read');
    }
    final raw = <DedaLegacyProgressPart,String?>{
      for(final part in DedaLegacyProgressPart.values) part:values[_key(part,accountKey)],
    };
    check();
    return DedaLegacyProgressCapture._(accountKey,raw);
  }
}
