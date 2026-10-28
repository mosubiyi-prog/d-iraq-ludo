import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_stage39_task_writer_fence.dart';

void main() {
  const account = '07701234567';
  test('default production build retains local DEDA task behavior', () {
    expect(DedaStage39TaskWriterFence.privatePilot, isFalse);
    expect(DedaStage39TaskWriterFence.allowOriginalLocalAward, isTrue);
    expect(
      DedaStage39TaskWriterFence.route(
        pilotEnabled: false,
        canonicalAccount: account,
        authenticatedAccount: null,
        verifiedMigrationComplete: false,
        oldWriterFenceEnforced: false,
        trustedTaskClaimIssuerAvailable: false,
      ),
      DedaTaskClaimWriteRoute.legacyLocal,
    );
  });

  test('pilot cannot fall back to local points during missing server', () {
    expect(DedaStage39TaskWriterFence.route(
      pilotEnabled: true,
      canonicalAccount: account,
      authenticatedAccount: account,
      verifiedMigrationComplete: false,
      oldWriterFenceEnforced: false,
      trustedTaskClaimIssuerAvailable: false,
    ), DedaTaskClaimWriteRoute.blockedPendingServer);
  });

  test('separately approved migration without enforced old APK fence is blocked', () {
    expect(DedaStage39TaskWriterFence.route(
      pilotEnabled: true,
      canonicalAccount: account,
      authenticatedAccount: account,
      verifiedMigrationComplete: true,
      oldWriterFenceEnforced: false,
      trustedTaskClaimIssuerAvailable: true,
    ), DedaTaskClaimWriteRoute.blockedPendingServer);
  });

  test('pilot cannot accept a different or invalid account', () {
    for (final key in [null, '07707654321', '', 'abc']) {
      expect(DedaStage39TaskWriterFence.route(
        pilotEnabled: true,
        canonicalAccount: account,
        authenticatedAccount: key,
        verifiedMigrationComplete: true,
        oldWriterFenceEnforced: true,
        trustedTaskClaimIssuerAvailable: true,
      ), DedaTaskClaimWriteRoute.blockedPendingServer);
    }
    expect(DedaStage39TaskWriterFence.route(
      pilotEnabled: true,
      canonicalAccount: 'not-an-account',
      authenticatedAccount: 'not-an-account',
      verifiedMigrationComplete: true,
      oldWriterFenceEnforced: true,
      trustedTaskClaimIssuerAvailable: true,
    ), DedaTaskClaimWriteRoute.blockedPendingServer);
  });

  test('all reviewed preconditions select server ONLY, never local writer', () {
    expect(DedaStage39TaskWriterFence.route(
      pilotEnabled: true,
      canonicalAccount: account,
      authenticatedAccount: account,
      verifiedMigrationComplete: true,
      oldWriterFenceEnforced: true,
      trustedTaskClaimIssuerAvailable: true,
    ), DedaTaskClaimWriteRoute.serverOnly);
  });
}
