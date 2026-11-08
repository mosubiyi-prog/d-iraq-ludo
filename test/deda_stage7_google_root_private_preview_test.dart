import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_stage6_new_account_google_handoff_PRIVATE_NOT_WIRED.dart';
import 'package:d_iraq_ludo/deda_stage7_google_root_private_preview_NOT_WIRED.dart';

const google = DedaStage6NewOwnerSnapshot(
  uid: 'new-google-sandbox-owner-uid',
  isAnonymous: false,
  firebaseProviderId: 'google.com',
  isCurrentOriginalUid: true,
  registrationVersion: 2,
  intentEpoch: 22,
);
DedaStage7GoogleRootStep gate({
  bool enabled = true,
  DedaStage6NewOwnerSnapshot? auth = google,
  bool existingAccount = false,
  bool priorUid = false,
  bool admin = false,
  bool consent = true,
  bool chosenNew = true,
  bool active = true,
  int epoch = 22,
  bool phoneProved = false,
}) =>
    DedaStage7GoogleRootPreview.assess(
      enabled: enabled,
      accountKey: '07111111111',
      originalId: '@DEDA-ABC123',
      auth: auth,
      explicitNewAccountChoice: chosenNew,
      googleConsent: consent,
      currentIntent: active,
      expectedEpoch: epoch,
      existingPhoneAccount: existingAccount,
      priorUidProvenance: priorUid,
      adminPrincipal: admin,
      phoneIndependentlyVerified: phoneProved,
    );

void main() {
  test('stage7 is disabled in every normal Android app', () {
    expect(dedaStage7GoogleRootPreviewEnabled, isFalse);
    expect(gate(enabled: false), DedaStage7GoogleRootStep.hold);
  });
  test('correct Google UID means reservation review, NEVER phone owner', () {
    expect(gate(), DedaStage7GoogleRootStep.reserveGoogleUidReviewOnly);
  });
  test('even client phone-review checkbox never authorizes ownership', () {
    expect(gate(phoneProved: true),
        DedaStage7GoogleRootStep.independentPhoneVerificationRequired);
  });
  test('existing phone/legacy A-B-C/admin principal cannot enter lane', () {
    expect(gate(existingAccount: true), DedaStage7GoogleRootStep.hold);
    expect(gate(priorUid: true), DedaStage7GoogleRootStep.hold);
    expect(gate(admin: true), DedaStage7GoogleRootStep.hold);
  });
  test('anonymous auth demands Google first; never reserves a phone', () {
    const anon = DedaStage6NewOwnerSnapshot(
      uid: 'anonymous-test-uid',
      isAnonymous: true,
      firebaseProviderId: 'anonymous',
      isCurrentOriginalUid: true,
      registrationVersion: 2,
      intentEpoch: 22,
    );
    expect(gate(auth: anon), DedaStage7GoogleRootStep.requireGoogleFirst);
  });
  test('stale UI intent, no Google consent and prior mode are blocked', () {
    expect(gate(active: false), DedaStage7GoogleRootStep.hold);
    expect(gate(epoch: 23), DedaStage7GoogleRootStep.hold);
    expect(gate(consent: false), DedaStage7GoogleRootStep.hold);
    expect(gate(chosenNew: false), DedaStage7GoogleRootStep.hold);
  });
  test('legacy registrationVersion 1 is never silently upgraded', () {
    const old = DedaStage6NewOwnerSnapshot(
      uid: 'legacy-old-account-uid',
      isAnonymous: false,
      firebaseProviderId: 'google.com',
      isCurrentOriginalUid: true,
      registrationVersion: 1,
      intentEpoch: 22,
    );
    expect(gate(auth: old), DedaStage7GoogleRootStep.hold);
  });
  test('no stage7 result permits creation or sign in', () {
    for (final mode in DedaStage7GoogleRootStep.values) {
      expect(mode.name, isNot('accountCreated'));
      expect(mode.name, isNot('phoneVerified'));
      expect(mode.name, isNot('ownerAuthorized'));
    }
  });
}
