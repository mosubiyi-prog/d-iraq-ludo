import 'package:flutter/foundation.dart';

import 'deda_auth_session_runtime.dart';
import 'deda_backend.dart';
import 'deda_pin_auth.dart';
import 'deda_session_recovery_coordinator.dart';
import 'deda_session_rescue_stage3_core.dart';
import 'deda_stage71_free_owned_use_profile.dart';
import 'deda_unified_active_id_100410.dart';
import 'deda_verified_active_id_store.dart';

export 'deda_session_rescue_stage3_core.dart' show DedaRescueStage3Result;

/// Stage3 remains default OFF until future owner-approved signed build.
const bool dedaSessionRescueStage3Enabled = bool.fromEnvironment(
  'DEDA_SESSION_RESCUE_STAGE3', defaultValue: false,
);

class DedaFirebaseRescueStage3Port implements DedaRescueStage3Port {
  DedaFirebaseRescueStage3Port()
      : _coordinator = DedaSessionRecoveryCoordinator(
          port: const DedaFirebaseRescuePort(),
        );

  final DedaSessionRecoveryCoordinator _coordinator;

  @override
  DedaRescueSnapshot? capture() {
    if (!DedaAuthRuntime.enabled) return null;
    try {
      return const DedaFirebaseRescuePort().snapshot();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<DedaRescueResult> verifyOwner(
      String accountKey, String originalId) =>
      _coordinator.inspectOwner(
        accountKey: accountKey,
        expectedOriginalId: originalId,
      );

  @override
  Future<String?> readVerifiedOwnerDisplay(
      String uid, String originalId) async {
    if (capture()?.uid != uid ||
        !DedaStage71OwnedIdentifierService.enabled) return null;

    // Existing Stage71 checks server account ownership, grant and gift receipt
    // before saving anything for display. No new alias registry is invented.
    await DedaUnifiedActiveId100410.ensureOwner(originalId);
    if (capture()?.uid != uid) return null;
    final record = DedaVerifiedActiveIdStore.read(uid, originalId);
    return record != null && record.wellFormed
        ? record.displayId
        : null;
  }

  @override
  void notifyVerifiedOwnerViews() {
    // The existing profile/ID widgets already listen to this single event.
    // League, friends and public labels retain their own server checks.
    DedaStage71ActiveIdRefresh.changed();
  }
}

/// Shared app hook; disabled unless the owner approves inclusion in a later
/// signed APK. Home/settings/Google receive one coherent readiness event.
class DedaSessionRescueStage3Bridge {
  DedaSessionRescueStage3Bridge._();

  static final DedaRescueStage3Controller _shared =
      DedaRescueStage3Controller(DedaFirebaseRescueStage3Port());

  static ValueListenable<DedaRescueStage3Result?> get updates =>
      _shared.updates;

  static Future<DedaRescueStage3Result?> runForPhone(String phone) {
    if (!dedaSessionRescueStage3Enabled) {
      return Future<DedaRescueStage3Result?>.value(null);
    }
    final originalId = DedaBackend.personalShareIdForPhone(phone);
    final accountKey = DedaPinAuth.accountKeyForPhone(phone);
    return _shared.rescue(accountKey: accountKey, originalId: originalId);
  }
}
