import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_auth_session_runtime.dart';
import 'package:d_iraq_ludo/deda_100430_owner_uid_continuity.dart';
import 'package:d_iraq_ludo/deda_100431_linked_owner_session_policy.dart';
import 'package:d_iraq_ludo/deda_step2_before_uid_link_evidence_checkpoint.dart';
import 'package:d_iraq_ludo/deda_step2_spark_linked_uid_readonly.dart';
import 'package:d_iraq_ludo/deda_step2_google_replacement_login_100439.dart';
import 'package:d_iraq_ludo/deda_step2_completion_gate.dart';

void main() {
  test('private 100444 original-phone QA enables BOTH guardians and Google only for verified owner', () {
    expect(dedaAuthSessionRuntimeEnabled, isTrue);
    expect(dedaStep2PreLinkEvidenceCheckpointEnabled, isTrue);
    expect(dedaLinkedOwnerCompatEnabled, isTrue);
    expect(dedaStep1GoogleOwnerLinkEnabled, isTrue);
    expect(() => DedaStep2SparkLegacyPrelinkPolicy.requireEvidenceBeforeLink(
      sparkPilotEnabled: true,
      linkedOwnerCompatEnabled: dedaLinkedOwnerCompatEnabled,
      prelinkCheckpointEnabled: dedaStep2PreLinkEvidenceCheckpointEnabled,
      hasArchiveCallback: false,
    ), throwsStateError);
    expect(() => DedaStep2SparkLegacyPrelinkPolicy.requireEvidenceBeforeLink(
      sparkPilotEnabled: true,
      linkedOwnerCompatEnabled: dedaLinkedOwnerCompatEnabled,
      prelinkCheckpointEnabled: dedaStep2PreLinkEvidenceCheckpointEnabled,
      hasArchiveCallback: true,
    ), returnsNormally);
  });

  test('new-phone credential login is OFF until creation-race is resolved; no restored-money claim', () {
    expect(dedaStep2GoogleReplacementLoginEnabled, isFalse);
    expect(dedaStep2SparkLinkedUidReadOnlyEnabled, isFalse);
    const report = DedaStep2CompletionReport({});
    expect(report.canPrepareFullRecoveryApk, isFalse);
    expect(report.canIssueFinancialRewards, isFalse);
    expect(report.canDeleteOldPhoneData, isFalse);
  });
}
