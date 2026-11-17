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

  /// Called from the already-existing HomePage life cycle in the verified
  /// assembled DEDA app. Gate is OFF: zero network and zero UI side effects.
  /// Enabling requires a separate approved server-side rollout.
  static Future<void> preflightOnHome() async {
    if (!dedaUnifiedRoomReadOnlyEnabled) return;
    await readDomain('profile');
  }
}
