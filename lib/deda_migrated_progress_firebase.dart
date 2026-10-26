import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'deda_auth_session_runtime.dart';
import 'deda_backend.dart';
import 'deda_migrated_progress.dart';
import 'deda_section_operation_context.dart';
import 'deda_session_transition_gate.dart';
import 'main.dart' show DedaPreferences;

// Independent from the premium-ID feature. Requires approved cutover rules,
// deployed handlers and real attestation before activation in any APK.
const dedaMigratedProgressEnabled = bool.fromEnvironment('DEDA_STABILITY_MIGRATED_PROGRESS', defaultValue: false);
class DedaFirebaseMigratedProgressIo implements DedaMigratedProgressIo {
  static Future<void>? _attestation;
  @override
  DedaMigratedScope? get current {
    DedaSectionOperationContext.checkCurrent();
    if (!dedaMigratedProgressEnabled || !DedaPreferences.isLoggedIn || Firebase.apps.isEmpty) return null;
    final principal = DedaAuthRuntime.capture();
    if (principal == null || principal.kind != DedaSessionAuthKind.anonymous) return null;
    return DedaMigratedScope(DedaBackend.accountKeyForPhone(DedaPreferences.phone),
        DedaBackend.personalShareIdForPhone(DedaPreferences.phone).trim(),
        (principal.uid, principal.kind, principal.epoch, DedaPreferences.stabilityAccountEpoch));
  }
  Future<void> _ready() async {
    if (!dedaMigratedProgressEnabled) throw StateError('migrated-progress-not-approved');
    final pending = _attestation ??= _activate();
    try { await pending; } catch (_) { _attestation = null; rethrow; }
  }
  static Future<void> _activate() async {
    await FirebaseAppCheck.instance.activate(androidProvider:
        kReleaseMode ? AndroidProvider.playIntegrity : AndroidProvider.debug);
    final token = await FirebaseAppCheck.instance.getToken();
    if (token == null || token.isEmpty) throw StateError('migrated-attestation-required');
  }
  @override
  Future<Object?> call(String name, Map<String, Object?> data) async {
    final before = current;
    if (before == null) throw StateError('migrated-owner-required');
    await _ready();
    if (!before.matches(current)) throw StateError('migrated-account-changed');
    final result = await FirebaseFunctions.instance.httpsCallable(name,
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30))).call<Object?>(data);
    if (!before.matches(current)) throw StateError('migrated-account-changed');
    return result.data;
  }
}
class DedaMigratedProgressBridge {
  static final service = DedaMigratedProgressService(DedaFirebaseMigratedProgressIo());
  static Future<int> purchaseBalance(String original) async => (await service.read(original)).purchasableDiamonds;
  static Future<void> buyFrame(String original, String frame) async {
    await service.purchaseFrame(original, frame);
  }
}
