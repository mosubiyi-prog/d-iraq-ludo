import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Bootstraps real Firebase App Check for premium alias backend calls only.
/// OFF until Play Integrity is registered for the EXACT DEDA Android package
/// and production signing certificate, and the private owner can verify a
/// token. Enforced backend callables must NEVER be switched on without this.
/// Not a wallet grant, UID migration, purchase, or Firestore write.
class DedaQa32PremiumAppCheck {
  DedaQa32PremiumAppCheck._();

  static const bool enabled =
      bool.fromEnvironment('DEDA_PREMIUM_IDS_SERVER_LIVE', defaultValue: false);
  static Future<void>? _initializing;

  static Future<void> ensureReady() async {
    if (!enabled) throw StateError('premium-app-check-not-approved');
    final pending = _initializing ??= _activate();
    try {
      await pending;
    } catch (_) {
      // App Check provider registration/attestation must never be silently
      // treated as success or cached forever after a failed startup.
      _initializing = null;
      rethrow;
    }
  }

  static Future<void> _activate() async {
    if (Firebase.apps.isEmpty) throw StateError('firebase-not-ready');
    await FirebaseAppCheck.instance.activate(
      androidProvider: kReleaseMode
          ? AndroidProvider.playIntegrity
          : AndroidProvider.debug,
    );
    // Fail closed before any protected callable if no token was actually
    // issued. A release sideload may not pass Play Integrity attestation.
    final token = await FirebaseAppCheck.instance.getToken();
    if (token == null || token.isEmpty) {
      throw StateError('premium-app-check-no-attested-token');
    }
  }
}
