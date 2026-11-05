import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'deda_100431_linked_owner_session_policy.dart';
import 'deda_auth_session_runtime.dart';
import 'deda_step2_linked_owner_flutter_handoff.dart';
import 'deda_step2_linked_owner_firebase_port.dart';
import 'deda_step2_linked_owner_guardian_bridge.dart';
import 'deda_step2_recovery_guardian.dart';
import 'deda_step2_recovery_journal_firestore.dart';

/// Inert SDK wiring candidate, not called from main.dart or background code.
/// Server Functions/rules are NOT deployed; reviewed real worker adapters
/// are NOT supplied, so no full account recovery can happen through this.
class DedaLinkedOwnerGuardianAssembly {
  const DedaLinkedOwnerGuardianAssembly._();

  static DedaLinkedOwnerGuardianBridge prepare() {
    if (!dedaLinkedOwnerGuardianBridgeEnabled ||
        !dedaLinkedFlutterHandoffEnabled ||
        !dedaStep2RecoveryGuardianEnabled ||
        !dedaStep2RecoveryJournalEnabled ||
        !dedaLinkedOwnerCompatEnabled ||
        !DedaAuthRuntime.enabled ||
        Firebase.apps.isEmpty) {
      throw StateError('linked-guardian-not-activated');
    }
    final auth = FirebaseAuth.instance;
    final db = FirebaseFirestore.instance;
    final functions = FirebaseFunctions.instance;
    final port = DedaLinkedOwnerFirebasePortCandidate(
      auth: auth, db: db, functions: functions);
    final journal = DedaStep2FirestoreRecoveryJournal(
      auth: auth, firestore: db, functions: functions);
    final guardian = DedaStep2RecoveryGuardian(
      journal: journal,
      adapters: const <DedaVaultCode, DedaVaultWorkerAdapter>{});
    return DedaLinkedOwnerGuardianBridge(
      handoff: DedaLoginHandoff(port),
      guardian: guardian,
    );
  }
}
