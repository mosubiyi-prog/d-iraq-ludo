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
import 'deda_step2_level_points_restore.dart';
import 'deda_step2_linked_published_place_recovery.dart';
import 'deda_step2_original_backup_readback.dart';
import 'deda_step2_purchase_backup_readback.dart';
import 'deda_step2_vault_worker_adapters.dart';
import 'deda_step2_account_domains_recovery_readback.dart';
import 'deda_step2_assets_readback.dart';
import 'deda_step2_diamond_reconciliation_readonly.dart';
import 'deda_100432_quiz_cloud_continuity.dart';
import 'deda_step2_visual_prefs_continuity.dart';
import 'deda_step2_global_places_settings_archive.dart';
import 'deda_step2_global_places_settings_restore.dart';

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
    // Each adapter wraps the EXISTING owner-scoped source code.
    // A readback receipt never grants diamonds, paid frames, gifts or XP.
    final original = DedaStep2OriginalBackupReadback.firebase();
    final purchase = DedaStep2PurchaseSourceReadback.firebase();
    final level = DedaStep2LevelPointsRestore.firebase();
    const levelLocal = DedaStep2PrefsLevelLocalIo();
    final place = DedaStep2LinkedPublishedPlaceRecovery.firebase();
    const placeIo = DedaStep2FirebaseLinkedPlaceIo();
    final guardian = DedaStep2RecoveryGuardian(
      journal: journal,
      adapters: <DedaVaultCode, DedaVaultWorkerAdapter>{
        DedaVaultCode.originalBackupReadback:
          DedaVaultOriginalEvidenceAdapter(original),
        DedaVaultCode.purchaseBackupReadback:
          DedaVaultPurchaseEvidenceAdapter(original, purchase),
        DedaVaultCode.levelPointsRestore:
          DedaVaultLevelPointsAdapter(level, original, levelLocal),
        DedaVaultCode.publishedPlaceRecovery:
          DedaVaultPublishedPlaceAdapter(place, placeIo),
      });
    return DedaLinkedOwnerGuardianBridge(
      handoff: DedaLoginHandoff(port),
      guardian: guardian,
      domainReadback: const DedaStep2AccountDomainsRecoveryReadback(
        io: DedaFirebaseDomainSourceIo(),
      ),
      // Explicit recovery only, and OFF unless the audited source gate is
      // deliberately enabled. Never called during a normal app startup.
      assetReadback: DedaStep2AssetsReadback.firebase(),
      // Private source-only financial observations. No account or wallet
      // writes; the original phone's AdMob JSON remains UNTRUSTED.
      diamondReadback: const DedaStep2DiamondReconciliationReader(
        io: DedaFirebaseDomainSourceIo(),
      ),
      originalPairedFinancialSource: (scope) async {
        // Exactly the archived old-phone pair; not SharedPreferences of the
        // replacement device. This existing readback verifies same UID,
        // captureId and original installation, and returns only source data.
        await scope.checkOwner();
        final progress = await original.readOriginalEvidence(
          accountKey: scope.accountKey,
          originalUid: scope.originalUid,
          isCurrent: scope.isCurrentIntent,
        );
        await scope.checkOwner();
        final purchaseSnapshot = await purchase.inspectPairedWithProgress(
          accountKey: scope.accountKey,
          originalId: scope.originalId,
          originalUid: scope.originalUid,
          progress: progress,
          isCurrent: scope.isCurrentIntent,
        );
        await scope.checkOwner();
        if (purchaseSnapshot.captureId != progress.captureId ||
            purchaseSnapshot.sourceUid != progress.sourceUid ||
            purchaseSnapshot.sourceInstallId != progress.sourceInstallId) {
          throw StateError('old-phone-financial-archives-not-paired');
        }
        return DedaStep2ArchivedDiamondFinancialSource(
          accountKey: scope.accountKey,
          originalUid: scope.originalUid,
          originalId: scope.originalId,
          captureId: progress.captureId,
          sourceInstallId: progress.sourceInstallId,
          audit: purchaseSnapshot.financialSourceAudit,
        );
      },
      restoreFreeAppearance: dedaStep2VisualPrefsMigrationEnabled
        ? (scope) => DedaStep2VisualPrefsContinuity.firebase()
            .restoreReplacementPhone(
              accountKey: scope.accountKey,
              originalId: scope.originalId,
              originalUid: scope.originalUid,
              isCurrent: scope.isCurrentIntent,
            )
        : null,
      restoreQuizUi: dedaQuizCloudSyncEnabled
        ? (scope, iraqDay) => DedaQuizCloudContinuity.firebase()
            .restoreNewPhoneQuiz(
              uid: scope.originalUid,
              accountKey: scope.accountKey,
              originalId: scope.originalId,
              iraqDay: iraqDay,
              isCurrent: scope.isCurrentIntent,
            )
        : null,
      restoreGlobalPlacesSettings:
          dedaStep2GlobalPlacesSettingsArchiveEnabled &&
          dedaStep2GlobalPlacesSettingsRestoreEnabled
          ? (scope) => DedaStep2GlobalPlacesReplacementRestore.firebase()
              .restoreExplicit(
                accountKey: scope.accountKey,
                originalId: scope.originalId,
                originalUid: scope.originalUid,
                isCurrent: scope.isCurrentIntent,
              )
          : null,
    );
  }
}
