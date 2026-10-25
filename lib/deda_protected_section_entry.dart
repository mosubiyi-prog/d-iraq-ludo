import 'deda_auth_session_runtime.dart';
import 'deda_session_transition_gate.dart' show DedaSessionAuthKind;

const dedaProtectedSectionEntryEnabled = bool.fromEnvironment(
  'DEDA_STABILITY_SECTION_ENTRY', defaultValue: false,
);

/// Uses the existing full auth lane, never a second gate or a read retry.
/// Account/epoch observations only guard concurrency; server proof remains
/// inside the original preparation operation. No result or permission cache.
Future<T> runDedaProtectedSectionEntry<T>({
  required DedaAuthSessionController controller,
  required String Function() accountKey,
  required int Function() accountEpoch,
  required bool Function() isMounted,
  required Future<T> Function() prepare,
}) {
  final account = accountKey();
  final epoch = accountEpoch();
  return controller.run<T>(
    kind: controller.current().kind == DedaSessionAuthKind.none
        ? DedaSessionTransitionKind.anonymousPreparation
        : DedaSessionTransitionKind.ownerRestore,
    origin: DedaSessionTransitionOrigin.activeSection,
    isCurrent: () => isMounted() && account.isNotEmpty &&
        accountKey() == account && accountEpoch() == epoch,
    action: prepare,
  );
}
