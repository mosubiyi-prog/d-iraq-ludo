import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_forward_healthy_account_guard.dart';

void main() {
  test('forward guard is OFF until reviewed release', () {
    expect(dedaForwardHealthyAccountGuardEnabled, isFalse);
  });

  test('no UID minted by existing-account helper on fresh phone', () {
    expect(DedaForwardHealthyAccountGuard.mayCreateAnonymousPrincipal(
      hasCurrentPrincipal: false, explicitNewEnrollment: false,
      explicitRecoveryRequest: false,
    ), isFalse);
    expect(DedaForwardHealthyAccountGuard.mayCreateAnonymousPrincipal(
      hasCurrentPrincipal: false, explicitNewEnrollment: true,
      explicitRecoveryRequest: false,
    ), isTrue);
  });

  test('recovery requester is not an existing-account owner grant', () {
    expect(DedaForwardHealthyAccountGuard.mayCreateAnonymousPrincipal(
      hasCurrentPrincipal: false, explicitNewEnrollment: false,
      explicitRecoveryRequest: true,
    ), isTrue);
  });

  test('no implicit logout of signed-in Firebase principal', () {
    expect(DedaForwardHealthyAccountGuard.mayReplaceExistingPrincipalImplicitly(
      hasCurrentPrincipal: true,
    ), isFalse);
  });

  test('anonymous healthy user cannot be logged out by accident', () {
    expect(DedaForwardHealthyAccountGuard.maySignOutAfterServerCheck(
      isAnonymous: true, uidUnchanged: true, serverReadFresh: true,
      hasOwnerSessionDocument: true, hasUserDocument: true,
    ), isFalse);
    expect(DedaForwardHealthyAccountGuard.maySignOutAfterServerCheck(
      isAnonymous: true, uidUnchanged: true, serverReadFresh: true,
      hasOwnerSessionDocument: false, hasUserDocument: true,
    ), isFalse);
    expect(DedaForwardHealthyAccountGuard.maySignOutAfterServerCheck(
      isAnonymous: true, uidUnchanged: true, serverReadFresh: true,
      hasOwnerSessionDocument: true, hasUserDocument: false,
    ), isFalse);
  });

  test('offline, stale or changed UID never allows anonymous logout', () {
    for (final stale in <bool>[true, false]) {
      expect(DedaForwardHealthyAccountGuard.maySignOutAfterServerCheck(
        isAnonymous: true, uidUnchanged: !stale,
        serverReadFresh: stale,
        hasOwnerSessionDocument: false, hasUserDocument: false,
      ), isFalse);
    }
  });

  test('verified empty guest can sign out; durable account can sign out', () {
    expect(DedaForwardHealthyAccountGuard.maySignOutAfterServerCheck(
      isAnonymous: true, uidUnchanged: true, serverReadFresh: true,
      hasOwnerSessionDocument: false, hasUserDocument: false,
    ), isTrue);
    expect(DedaForwardHealthyAccountGuard.maySignOutAfterServerCheck(
      isAnonymous: false, uidUnchanged: true, serverReadFresh: false,
      hasOwnerSessionDocument: true, hasUserDocument: true,
    ), isTrue);
  });
}
