import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_stage6_new_account_google_handoff_PRIVATE_NOT_WIRED.dart';

const String accountKey = '07111111111';
const String originalId = '@DEDA-ABC123';
const String ownerUid = 'realistic-synthetic-original-uid';

const DedaStage6NewOwnerSnapshot google = DedaStage6NewOwnerSnapshot(
  uid: ownerUid,
  isAnonymous: false,
  firebaseProviderId: 'google.com',
  isCurrentOriginalUid: true,
  registrationVersion: 2,
  intentEpoch: 7,
);

DedaStage6NewOwnerChoice assess({
  bool pilotEnabled = true,
  bool explicitCreateNewAccount = true,
  bool userConsentedToGoogle = true,
  bool isCurrentIntent = true,
  int expectedEpoch = 7,
  String account = accountKey,
  String id = originalId,
  DedaStage6NewOwnerSnapshot? snapshot = google,
  bool serverPhoneReviewed = true,
  bool existingDedaAccount = false,
  bool hasPriorAccountUid = false,
  bool accountSplitSuspected = false,
  bool adminPrincipal = false,
}) =>
    DedaStage6NewOwnerGoogleHandoff.assess(
      pilotEnabled: pilotEnabled,
      explicitCreateNewAccount: explicitCreateNewAccount,
      userConsentedToGoogle: userConsentedToGoogle,
      isCurrentIntent: isCurrentIntent,
      expectedEpoch: expectedEpoch,
      accountKey: account,
      originalId: id,
      auth: snapshot,
      hasIndependentServerPhoneReview: serverPhoneReviewed,
      existingDedaAccount: existingDedaAccount,
      hasPriorAccountUid: hasPriorAccountUid,
      accountSplitSuspected: accountSplitSuspected,
      adminPrincipal: adminPrincipal,
    );

void main() {
  test('new Google-first UI pilot is OFF in all normal Flutter APKs', () {
    expect(dedaStage6NewGoogleOwnerEnabled, isFalse);
    expect(assess(pilotEnabled: false),
        DedaStage6NewOwnerChoice.hold);
  });

  test('even complete new-account input only requests server review', () {
    expect(assess(),
        DedaStage6NewOwnerChoice.serverEnrollmentReviewOnly);
  });

  test('explicit create-new-account action and Google consent required', () {
    expect(assess(explicitCreateNewAccount: false),
        DedaStage6NewOwnerChoice.hold);
    expect(assess(userConsentedToGoogle: false),
        DedaStage6NewOwnerChoice.hold);
  });

  test('existing or split A/B/C account cannot enter new-account lane', () {
    expect(assess(existingDedaAccount: true),
        DedaStage6NewOwnerChoice.hold);
    expect(assess(accountSplitSuspected: true),
        DedaStage6NewOwnerChoice.hold);
    expect(assess(hasPriorAccountUid: true),
        DedaStage6NewOwnerChoice.hold);
  });

  test('admin identity remains entirely separate from owner creation', () {
    expect(assess(adminPrincipal: true),
        DedaStage6NewOwnerChoice.hold);
  });

  test('anonymous or PIN-only auth cannot make a new identity owner', () {
    for (final value in [
      const DedaStage6NewOwnerSnapshot(
        uid: 'anonymous-uid',
        isAnonymous: true,
        firebaseProviderId: 'anonymous',
        isCurrentOriginalUid: true,
        registrationVersion: 2,
        intentEpoch: 7,
      ),
      const DedaStage6NewOwnerSnapshot(
        uid: ownerUid,
        isAnonymous: false,
        firebaseProviderId: 'password',
        isCurrentOriginalUid: true,
        registrationVersion: 2,
        intentEpoch: 7,
      ),
      const DedaStage6NewOwnerSnapshot(
        uid: null,
        isAnonymous: false,
        firebaseProviderId: null,
        isCurrentOriginalUid: true,
        registrationVersion: 2,
        intentEpoch: 7,
      ),
    ]) {
      expect(assess(snapshot: value),
          DedaStage6NewOwnerChoice.googleFirstRequired);
    }
  });

  test('Google identity alone never certifies a typed Iraqi phone number', () {
    expect(assess(serverPhoneReviewed: false),
        DedaStage6NewOwnerChoice.independentPhoneReviewRequired);
  });

  test('auth switch while waiting for consent invalidates current intent', () {
    expect(assess(isCurrentIntent: false),
        DedaStage6NewOwnerChoice.hold);
    expect(assess(expectedEpoch: 8),
        DedaStage6NewOwnerChoice.hold);
    expect(assess(snapshot: const DedaStage6NewOwnerSnapshot(
      uid: 'new-user-uid',
      isAnonymous: false,
      firebaseProviderId: 'google.com',
      isCurrentOriginalUid: false,
      registrationVersion: 2,
      intentEpoch: 7,
    )), DedaStage6NewOwnerChoice.hold);
  });

  test('legacy 100340 registration is never upgraded implicitly', () {
    expect(assess(snapshot: const DedaStage6NewOwnerSnapshot(
      uid: ownerUid,
      isAnonymous: false,
      firebaseProviderId: 'google.com',
      isCurrentOriginalUid: true,
      registrationVersion: 1,
      intentEpoch: 7,
    )), DedaStage6NewOwnerChoice.hold);
  });

  test('premium alias or untrusted phone identifier cannot bind identity', () {
    expect(assess(id: '@DEDA-GOLD'),
        DedaStage6NewOwnerChoice.hold);
    expect(assess(account: '07111111111/../../admins'),
        DedaStage6NewOwnerChoice.hold);
    expect(assess(account: '070'),
        DedaStage6NewOwnerChoice.hold);
  });

  test('null Flutter Auth state never authorizes account registration', () {
    expect(assess(snapshot: null),
        DedaStage6NewOwnerChoice.hold);
  });

  test('no Flutter gate outcome authorizes account or Finance write', () {
    for (final choice in DedaStage6NewOwnerChoice.values) {
      expect(choice.name, isNot('authorized'));
      expect(choice.name, isNot('createAccount'));
      expect(choice.name, isNot('restoreWallet'));
      expect(choice.name, isNot('signIn'));
    }
  });
}
