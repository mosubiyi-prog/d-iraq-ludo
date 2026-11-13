import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_100430_owner_uid_continuity.dart';
import 'package:d_iraq_ludo/deda_100431_linked_owner_session_policy.dart';
import 'package:d_iraq_ludo/deda_step2_before_uid_link_evidence_checkpoint.dart';
import 'package:d_iraq_ludo/deda_step2_completion_gate.dart';

const account = '9647712345678';
const originalUid = 'immutable-owner-uid';

void main() {
  test('Google original UID link is OFF in normal signed APK', () {
    expect(dedaStep1GoogleOwnerLinkEnabled, false);
  });

  test('original anonymous UID needs confirmed progress and purchase readback before conversion', () async {
    String? uid=originalUid;
    var anonymous=true;
    var archiveCalls=0;
    final gate=DedaStep2PreLinkCheckpoint(
      enabled:true,
      currentUid:()=>uid,
      currentIsAnonymous:()=>anonymous,
      archive:(accountKey,sourceUid) async {
        archiveCalls++;
        expect(accountKey,account);
        expect(sourceUid,originalUid);
        return const DedaStep2PreLinkEvidenceReceipt(
          captureId:'canonical_original_capture_00001',
          sourceUid:originalUid,
          progressReadback:true,
          purchaseReadback:true,
        );
      },
    );
    final receipt=await gate.run(accountKey:account,originalUid:originalUid);
    expect(receipt.progressReadback,isTrue);
    expect(receipt.purchaseReadback,isTrue);
    expect(receipt.allowPhoneCutover,isFalse);
    expect(archiveCalls,1);
    uid='another-uid';
    await expectLater(gate.run(accountKey:account,originalUid:originalUid),
        throwsA(isA<DedaStep2PreLinkCheckpointHold>()));
    anonymous=false;
    uid=originalUid;
    await expectLater(gate.run(accountKey:account,originalUid:originalUid),
        throwsA(isA<DedaStep2PreLinkCheckpointHold>()));
    expect(archiveCalls,1);
  });

  test('prelink rejects stale/wrong-owner or incomplete cloud archive readback', () async {
    String? current=originalUid;
    Future<void> denied({
      required String sourceUid,
      required bool progress,
      required bool purchases,
      bool switchDuringArchive=false,
    }) async {
      current=originalUid;
      final gate=DedaStep2PreLinkCheckpoint(
        enabled:true,
        currentUid:()=>current,
        currentIsAnonymous:()=>true,
        archive:(accountKey,uid) async {
          if(switchDuringArchive) current='changed-owner-uid';
          return DedaStep2PreLinkEvidenceReceipt(
            captureId:'canonical_original_capture_00001',
            sourceUid:sourceUid,
            progressReadback:progress,
            purchaseReadback:purchases,
          );
        },
      );
      await expectLater(gate.run(accountKey:account,originalUid:originalUid),
          throwsA(isA<DedaStep2PreLinkCheckpointHold>()));
    }
    await denied(sourceUid:'wrong-owner-uid',progress:true,purchases:true);
    await denied(sourceUid:originalUid,progress:false,purchases:true);
    await denied(sourceUid:originalUid,progress:true,purchases:false);
    await denied(sourceUid:originalUid,progress:true,purchases:true,
        switchDuringArchive:true);
  });

  test('only a linked original owner may attach Google credentials', () {
    void approve({
      bool enabled = true,
      bool compat = true,
      String? storedUid = originalUid,
      String? liveUid = originalUid,
      bool anonymous = false,
      String provider = 'google.com',
      bool admin = false,
    }) => DedaOwnerUidContinuity.requireSameUidGoogleLink(
      featureEnabled: enabled,
      ownerCompatEnabled: compat,
      originalUid: storedUid,
      liveUid: liveUid,
      anonymous: anonymous,
      providerId: provider,
      adminDocumentExists: admin,
    );

    expect(approve, returnsNormally);
    expect(() => approve(enabled: false), throwsStateError);
    expect(() => approve(compat: false), throwsStateError);
    expect(() => approve(storedUid: null), throwsStateError);
    expect(() => approve(liveUid: 'replacement-new-uid'), throwsStateError);
    expect(() => approve(anonymous: true), throwsStateError);
    expect(() => approve(provider: 'password'), throwsStateError);
    expect(() => approve(provider: 'facebook.com'), throwsStateError);
    expect(() => approve(admin: true), throwsStateError);
  });

  test('original password account remains valid before Google link', () {
    expect(DedaLinkedOwnerSessionPolicy.providerIdentityMatches(
      accountKey: account,
      primaryEmail: '$account@deda-login.invalid',
    ), true);
  });

  test('Google primary email requires original password provider too', () {
    const linked = <({String providerId, String? email})>[
      (providerId: 'password', email: '$account@deda-login.invalid'),
      (providerId: 'google.com', email: 'owner@gmail.com'),
    ];
    expect(DedaLinkedOwnerSessionPolicy.providerIdentityMatches(
      accountKey: account,
      primaryEmail: 'owner@gmail.com',
      providers: linked,
    ), true);
    expect(DedaLinkedOwnerSessionPolicy.providerIdentityMatches(
      accountKey: account,
      primaryEmail: 'owner@gmail.com',
      providers: const [(providerId: 'google.com', email: 'owner@gmail.com')],
    ), false);
    expect(DedaLinkedOwnerSessionPolicy.providerIdentityMatches(
      accountKey: account,
      primaryEmail: 'manager@gmail.com',
      providers: const [
        (providerId: 'password', email: 'other@deda-login.invalid'),
        (providerId: 'google.com', email: 'manager@gmail.com'),
      ],
    ), false);
  });

  test('a foreign Google user cannot borrow a different owner account', () {
    expect(DedaLinkedOwnerSessionPolicy.providerIdentityMatches(
      accountKey: '9647800000000',
      primaryEmail: 'owner@gmail.com',
      providers: const [
        (providerId: 'password', email: '$account@deda-login.invalid'),
        (providerId: 'google.com', email: 'owner@gmail.com'),
      ],
    ), false);
  });

  test('100445 update guard never treats a missing or different UID as the original owner', () {
    expect(DedaLinkedOwnerSessionPolicy.mayImplicitlyPrepareOwnerSession(
      linkedOwnerPilotEnabled: true, hasCurrentPrincipal: false), isFalse);
    expect(DedaLinkedOwnerSessionPolicy.mayUseUnverifiedLocalLogin(
      linkedOwnerPilotEnabled: true,
      hasStoredOriginalUid: true, hasStoredAccountKey: true), isFalse);
    bool canResume({String? uid = originalUid, String? storedUid = originalUid,
      bool anonymous = false, String email = '$account@deda-login.invalid'}) =>
        DedaLinkedOwnerSessionPolicy.mayResumeLinkedLocalLogin(
          savedOriginalUid: storedUid, savedAccountKey: account,
          localPhone: account, currentUid: uid, currentEmail: email,
          currentIsAnonymous: anonymous);
    expect(canResume(), isTrue);
    expect(canResume(uid: 'replacement-uid'), isFalse);
    expect(canResume(uid: null), isFalse);
    expect(canResume(storedUid: 'foreign-saved-uid'), isFalse);
    expect(canResume(anonymous: true), isFalse);
    expect(canResume(email: 'unknown@gmail.com'), isFalse);
  });

  test('a checkpoint or source readback must never claim complete recovery or grant finances', () {
    const evidence = DedaStep2PreLinkEvidenceReceipt(
      captureId: 'capture_original_source_00001',
      sourceUid: originalUid,
      progressReadback: true, purchaseReadback: true,
    );
    expect(evidence.fullAccountRestored, isFalse);
    expect(evidence.canRestoreDiamonds, isFalse);
    expect(evidence.canRestoreXp, isFalse);
    expect(evidence.allowPhoneCutover, isFalse);
    const report = DedaStep2CompletionReport({
      'originalOwnerUid': DedaStep2CompletionState.verifiedExistingSource,
      'levelPoints': DedaStep2CompletionState.missingHistoricalProof,
    });
    expect(report.allDomainsRestored, isFalse);
    expect(report.canPrepareFullRecoveryApk, isFalse);
    expect(report.canIssueFinancialRewards, isFalse);
    expect(report.canDeleteOldPhoneData, isFalse);
  });
}
