import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Recovery-only, opt-in, fail-closed server PIN preflight.
/// This is NOT a login session, original-ID proof, account transfer or grant.
/// Legacy production sign-in stays unchanged until an approved server cutover.
class DedaSecurePinPreflight {
  static bool isHoldOnly(Object? response) {
    if (response is! Map) return false;
    return response['status'] == 'PIN_VERIFIED_HOLD' &&
        response['serverOwned'] == true &&
        response['productionMigrationEnabled'] == false &&
        response['canRestoreAssets'] == false &&
        response['canCreditXp'] == false &&
        response['canCreditDiamonds'] == false &&
        response['canIssueGift'] == false;
  }

  static bool validAccountAndPin(String phone, String pin) {
    final key = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return RegExp(r'^\d{8,15}
    required String phone,
    required String pin,
  }) async {
    if (Firebase.apps.isEmpty) throw StateError('firebase-not-ready');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !user.isAnonymous) {
      throw StateError('authenticated-anonymous-session-required');
    }
    final uid = user.uid;
    final key = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (!validAccountAndPin(phone, pin)) {
      throw ArgumentError('invalid-account-or-pin-format');
    }
    // Do not store PINs, account keys, receipts or tokens in SharedPreferences.
    // Callable enforces Firebase Auth, App Check and global server-side limits.
    final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('dedaSecurePinPreflightV1')
        .call(<String, Object>{'accountKey': key, 'pin': pin});
    if (FirebaseAuth.instance.currentUser?.uid != uid ||
        !isHoldOnly(result.data)) {
      throw StateError('server-recovery-preflight-not-approved');
    }
    // HOLD receipt grants no user/profile/financial read privileges.
  }
}
).hasMatch(key) &&
        RegExp(r'^\d{6}
    required String phone,
    required String pin,
  }) async {
    if (Firebase.apps.isEmpty) throw StateError('firebase-not-ready');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !user.isAnonymous) {
      throw StateError('authenticated-anonymous-session-required');
    }
    final uid = user.uid;
    final key = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (!RegExp(r'^\d{8,15}$').hasMatch(key) ||
        !RegExp(r'^\d{6}$').hasMatch(pin)) {
      throw ArgumentError('invalid-account-or-pin-format');
    }
    // Do not store PINs, account keys, receipts or tokens in SharedPreferences.
    // Callable enforces Firebase Auth, App Check and global server-side limits.
    final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('dedaSecurePinPreflightV1')
        .call(<String, Object>{'accountKey': key, 'pin': pin});
    if (FirebaseAuth.instance.currentUser?.uid != uid ||
        !isHoldOnly(result.data)) {
      throw StateError('server-recovery-preflight-not-approved');
    }
    // HOLD receipt grants no user/profile/financial read privileges.
  }
}
).hasMatch(pin);
  }

  static Future<void> verifyHoldOnly({
    required String phone,
    required String pin,
  }) async {
    if (Firebase.apps.isEmpty) throw StateError('firebase-not-ready');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !user.isAnonymous) {
      throw StateError('authenticated-anonymous-session-required');
    }
    final uid = user.uid;
    final key = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (!RegExp(r'^\d{8,15}$').hasMatch(key) ||
        !RegExp(r'^\d{6}$').hasMatch(pin)) {
      throw ArgumentError('invalid-account-or-pin-format');
    }
    // Do not store PINs, account keys, receipts or tokens in SharedPreferences.
    // Callable enforces Firebase Auth, App Check and global server-side limits.
    final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('dedaSecurePinPreflightV1')
        .call(<String, Object>{'accountKey': key, 'pin': pin});
    if (FirebaseAuth.instance.currentUser?.uid != uid ||
        !isHoldOnly(result.data)) {
      throw StateError('server-recovery-preflight-not-approved');
    }
    // HOLD receipt grants no user/profile/financial read privileges.
  }
}
