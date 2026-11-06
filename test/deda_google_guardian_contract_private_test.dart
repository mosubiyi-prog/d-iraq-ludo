import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_100430_owner_uid_continuity.dart';
import 'package:d_iraq_ludo/deda_auth_session_runtime.dart';
import 'package:d_iraq_ludo/deda_step2_recovery_guardian.dart';
import 'package:d_iraq_ludo/deda_step2_linked_owner_guardian_bridge.dart';

void main() {
  test('Google identity card cannot activate owner or recovery automatically', () {
    expect(dedaStep1GoogleOwnerLinkEnabled, false);
    expect(dedaAuthSessionRuntimeEnabled, false);
    expect(dedaStep2RecoveryGuardianEnabled, false);
    expect(dedaLinkedOwnerGuardianBridgeEnabled, false);
  });

  test('all twelve archived codes keep their restricted dispatch roles', () {
    expect(DedaVaultManifest.all.length, 12);
    expect(DedaVaultManifest.spec(DedaVaultCode.ownerUidContinuity).mode,
        DedaVaultWorkerMode.ownerActionOnly);
    expect(DedaVaultManifest.spec(DedaVaultCode.ownerConfirmationUi).mode,
        DedaVaultWorkerMode.ownerActionOnly);
    expect(DedaVaultManifest.replacementPhoneCandidates,
        isNot(contains(DedaVaultCode.ownerUidContinuity)));
  });

  test('Google identity confirmation cannot claim restored finances or data', () {
    const result = DedaVaultRecoveryResult(
        stepStates: {}, stoppedSafely: false);
    expect(result.fullAccountRestored, false);
    expect(result.mayGrantDiamonds, false);
    expect(result.mayGrantRewards, false);
    expect(result.mayPublishNewPlace, false);
  });
}
