import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'deda_auth_session_runtime.dart';

/// DEDA unified room — genuinely wired SDK read-only bridge.
/// THIS IS NOT a production recovery switch. The server callable is held OFF
/// until separately verified historical owner proof and audited deployment.
/// No new auth user, sign out, SharedPreferences, or Firestore writes.
const bool dedaUnifiedRoomReadOnlyEnabled = bool.fromEnvironment(
  'DEDA_UNIFIED_ROOM_READ_ONLY_LIVE', defaultValue: false);

class DedaUnifiedRoomReadResult {
  const DedaUnifiedRoomReadResult._(
    this.status, this.domain, this.payload,
  );
  final String status;
  final String? domain;
  final Map<String, dynamic>? payload;

  bool get verifiedReadOnly => status == 'VERIFIED_READ_ONLY';
  static const hold = DedaUnifiedRoomReadResult._('HOLD', null, null);
}

class DedaUnifiedRoomRuntimeReadOnly {
  const DedaUnifiedRoomRuntimeReadOnly._();

  static const Set<String> _domains = {
    'profile', 'original_id', 'premium_id', 'friends',
    'league', 'gifts', 'wallet', 'places',
  };
  static const Map<String, Set<String>> _allow = {
    'profile': {'displayName', 'level'},
    'original_id': {'publicId'},
    'premium_id': {'displayId', 'color'},
    'friends': {'friendCount'},
    'league': {'weeklyPoints'},
    'gifts': {'giftCount'},
    'wallet': {'balanceDisplay', 'giftWalletBalance'},
    'places': {'publishedPlaceCount'},
  };
  static const Set<String> _ints = {
    'level', 'friendCount', 'weeklyPoints', 'giftCount',
    'balanceDisplay', 'giftWalletBalance', 'publishedPlaceCount',
  };

  static bool _validPayload(String domain, Object? raw) {
    if (raw is! Map || raw.isEmpty ||
        raw.length > (_allow[domain]?.length ?? 0)) return false;
    for (final entry in raw.entries) {
      if (entry.key is! String || !_allow[domain]!.contains(entry.key)) {
        return false;
      }
      final key = entry.key as String;
      final value = entry.value;
      if (_ints.contains(key)) {
        if (value is! int || value < 0 || value > 1000000000) return false;
      } else if (value is! String || value.isEmpty || value.length > 96) {
        return false;
      } else if (key == 'publicId' &&
          !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(value)) {
        return false;
      } else if (key == 'displayId' &&
          !RegExp(r'^@DEDA-[A-Z0-9]{4,12}$').hasMatch(value)) {
        return false;
      } else if (key == 'color' &&
          !{'gold', 'diamond', 'royal', 'pink'}.contains(value)) {
        return false;
      } else if (key == 'displayName' &&
          (value.contains('<') || value.contains('>'))) {
        return false;
      }
    }
    return true;
  }

  /// Pure policy check for the callable response, testable without Firebase.
  /// Missing historical data is HOLD, never fabricated level/coins/diamonds.
  static DedaUnifiedRoomReadResult acceptServerReply(
    String domain, Map<String, dynamic> data,
  ) {
    if (!_domains.contains(domain) ||
        data['status'] != 'VERIFIED_READ_ONLY' ||
        data['domain'] != domain ||
        data['authorized'] != true ||
        data['accountRestored'] != false ||
        data['financialRestore'] != false ||
        data['uidChanged'] != false ||
        !_validPayload(domain, data['payload'])) {
      return DedaUnifiedRoomReadResult.hold;
    }
    return DedaUnifiedRoomReadResult._(
      'VERIFIED_READ_ONLY',
      domain,
      Map<String, dynamic>.unmodifiable(
        Map<String, dynamic>.from(data['payload'] as Map),
      ),
    );
  }

  /// Accept the server's fixed-size single-snapshot home read. A held
  /// domain cannot fabricate an empty list, zero score or replacement ID.
  /// Any malformed outer contract discards the entire batch.
  static Map<String, DedaUnifiedRoomReadResult> acceptHomeBatchReply(
    Object? raw,
  ) {
    if (raw is! Map ||
        raw['status'] != 'SCOPED_HOME_READ_ONLY' ||
        raw['authorized'] != true ||
        raw['accountRestored'] != false ||
        raw['financialRestore'] != false ||
        raw['uidChanged'] != false ||
        raw['results'] is! Map) {
      return const <String, DedaUnifiedRoomReadResult>{};
    }
    final results = raw['results'] as Map;
    if (results.length != homeSectionDomains.length ||
        results.keys.any((key) => !homeSectionDomains.contains(key))) {
      return const <String, DedaUnifiedRoomReadResult>{};
    }
    final parsed = <String, DedaUnifiedRoomReadResult>{};
    for (final domain in homeSectionDomains) {
      final reply = results[domain];
      if (reply is! Map || reply['status'] is! String) {
        return const <String, DedaUnifiedRoomReadResult>{};
      }
      if (reply['status'] == 'HOLD') {
        if (reply['authorized'] != false ||
            reply['accountRestored'] != false ||
            reply['financialRestore'] != false ||
            reply['uidChanged'] != false ||
            reply.containsKey('payload')) {
          return const <String, DedaUnifiedRoomReadResult>{};
        }
        parsed[domain] = DedaUnifiedRoomReadResult.hold;
      } else {
        final accepted = acceptServerReply(
          domain, Map<String, dynamic>.from(reply),
        );
        if (!accepted.verifiedReadOnly) {
          return const <String, DedaUnifiedRoomReadResult>{};
        }
        parsed[domain] = accepted;
      }
    }
    return Map<String, DedaUnifiedRoomReadResult>.unmodifiable(parsed);
  }

  /// Only reads the current Firebase user's independently approved,
  /// server-sanitized scope. A/C historical UIDs are NEVER user inputs.
  /// The held/absent result must not replace on-device progress with zero.
  static Future<DedaUnifiedRoomReadResult> readDomain(String domain) async {
    if (!dedaUnifiedRoomReadOnlyEnabled || !_domains.contains(domain) ||
        Firebase.apps.isEmpty || !DedaAuthRuntime.enabled) {
      return DedaUnifiedRoomReadResult.hold;
    }
    try {
      // Even an Auth observer failure must fail closed. This method may be
      // launched unawaited by HomePage, so never leak an unhandled exception.
      final before = DedaAuthRuntime.capture();
      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser == null || authUser.isAnonymous ||
          before == null || before.uid != authUser.uid) {
        return DedaUnifiedRoomReadResult.hold;
      }
      // The callable requires App Check and an existing durable Firebase UID.
      // Never send UID, PIN, accountKey, or premium-ID routing as input.
      final result = await FirebaseFunctions.instance
          .httpsCallable(
            'dedaUnifiedRoomReadOnlyV1',
            options: HttpsCallableOptions(
              timeout: const Duration(seconds: 12),
            ),
          )
          .call<Map<String, dynamic>>({'domain': domain});
      DedaAuthRuntime.checkSnapshot(before);
      if (FirebaseAuth.instance.currentUser?.uid != authUser.uid) {
        return DedaUnifiedRoomReadResult.hold;
      }
      return acceptServerReply(domain, result.data);
    } catch (_) {
      // Offline/expired proof/404/revoked AppCheck/HOLD never becomes an
      // inferred empty profile, UID replacement, retry or financial write.
      return DedaUnifiedRoomReadResult.hold;
    }
  }

  /// The same current Auth principal is required for ALL home section
  /// reads, not merely for each request independently. No source UID, phone,
  /// PIN or accountKey is sent to the callable. HOLD remains a missing value,
  /// never an empty friend list, zero weekly score, or replacement ID.
  static const List<String> homeSectionDomains = <String>[
    'profile', 'original_id', 'premium_id', 'friends', 'league',
  ];

  static Future<Map<String, DedaUnifiedRoomReadResult>>
      readHomeSections() async {
    if (!dedaUnifiedRoomReadOnlyEnabled ||
        Firebase.apps.isEmpty || !DedaAuthRuntime.enabled) {
      return const <String, DedaUnifiedRoomReadResult>{};
    }
    try {
      final before = DedaAuthRuntime.capture();
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.isAnonymous || before?.uid != user.uid) {
        return const <String, DedaUnifiedRoomReadResult>{};
      }
      // One App Check-protected callable and one server snapshot replace
      // five independent network calls on every HomePage entry.
      // The HomePage hook remains unawaited: navigation never waits on it.
      final reply = await FirebaseFunctions.instance
          .httpsCallable(
            'dedaUnifiedRoomReadOnlyV1',
            options: HttpsCallableOptions(
              timeout: const Duration(seconds: 12),
            ),
          )
          .call<Map<String, dynamic>>({'domains': homeSectionDomains});
      DedaAuthRuntime.checkSnapshot(before);
      if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
        return const <String, DedaUnifiedRoomReadResult>{};
      }
      return acceptHomeBatchReply(reply.data);
    } catch (_) {
      return const <String, DedaUnifiedRoomReadResult>{};
    }
  }

  /// Existing HomePage hook in the assembled DEDA 100447 app. A disabled
  /// build performs ZERO network calls and never mutates visible UI state.
  /// A future approved rollout can consume only individually verified scopes.
  static Future<void> preflightOnHome() async {
    if (!dedaUnifiedRoomReadOnlyEnabled) return;
    await readHomeSections();
  }
}
