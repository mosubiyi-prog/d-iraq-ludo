import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_owner_diamond_provenance_preview_stage25.dart';

void main() {
  const firstAccount = 'accountA_original_verified';

  DedaDiamondProvenancePreview preview({
    int visible = 63,
    String account = firstAccount,
    String? serverAccount = firstAccount,
    int? recorded = 15,
    bool serverVerified = true,
    bool audited = false,
  }) =>
      DedaDiamondProvenancePreview(
        existingProfileVisibleDiamonds: visible,
        currentAccountScope: account,
        serverAccountScope: serverAccount,
        serverRecordedPersonalDiamonds: recorded,
        serverAccountVerified: serverVerified,
        independentlyAuditedRewardProvenance: audited,
      );

  test('63 diamonds from a user screenshot stay 63 when server says 0', () {
    final model = preview(recorded: 0);
    expect(model.protectedExistingDisplay, 63);
    expect(model.serverRecordedReadOnly, 0);
    expect(model.additionalDiamondsFromRemoteSnapshot, 0);
    expect(model.importedLegacyDiamonds, 0);
    expect(model.purchaseEnabled, false);
  });

  test('no server data or offline Firebase does not erase displayed 63', () {
    final model = preview(recorded: null, serverVerified: false);
    expect(model.protectedExistingDisplay, 63);
    expect(model.serverRecordedReadOnly, isNull);
    expect(model.purchaseEnabled, false);
  });

  test('63 displayed and 15 recorded must NOT become 78 automatically', () {
    final model = preview();
    expect(model.protectedExistingDisplay, 63);
    expect(model.serverRecordedReadOnly, 15);
    expect(model.historicalBalanceAutoMigrationAllowed, false);
    expect(model.additionalDiamondsFromRemoteSnapshot, 0);
  });

  test('different user account never reads a prior account server balance', () {
    final model = preview(account: 'new_account', serverAccount: firstAccount);
    expect(model.protectedExistingDisplay, 63);
    expect(model.hasAccountScopedServerEvidence, false);
    expect(model.serverRecordedReadOnly, isNull);
    expect(model.purchaseEnabled, false);
  });

  test('server recorded wallet is never proof of every historic ad', () {
    final model = preview(visible: 1000, recorded: 500);
    expect(model.serverRecordedReadOnly, 500);
    expect(model.historicalRewardProvenanceApproved, false);
    expect(model.purchaseEnabled, false);
  });

  test('separate genuine independent audit still does not activate shop', () {
    final model = preview(visible: 63, recorded: 5000, audited: true);
    expect(model.historicalRewardProvenanceApproved, true);
    expect(model.purchaseEnabled, false);
    expect(model.protectedExistingDisplay, 63);
  });

  test('GM older large visible balance stays untouched by remote failure', () {
    final model = preview(visible: 999603, recorded: null);
    expect(model.protectedExistingDisplay, 999603);
    expect(model.serverRecordedReadOnly, isNull);
    expect(model.purchaseEnabled, false);
  });

  test('client negative/invalid server-recorded amount cannot unlock purchase', () {
    final model = preview(visible: -1, recorded: -8);
    expect(model.protectedExistingDisplay, 0);
    expect(model.serverRecordedReadOnly, isNull);
    expect(model.purchaseEnabled, false);
  });

  test('blank account scope is not sufficient verification', () {
    final model = preview(
        account: '', serverAccount: '', serverVerified: true, recorded: 60);
    expect(model.serverRecordedReadOnly, isNull);
    expect(model.protectedExistingDisplay, 63);
  });

  testWidgets('owner-only QA preview shows 63 and disables purchase',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: DedaOwnerDiamondSafetyPreview(
              snapshot: DedaDiamondProvenancePreview(
                existingProfileVisibleDiamonds: 63,
                currentAccountScope: firstAccount,
                serverAccountScope: firstAccount,
                serverRecordedPersonalDiamonds: 0,
                serverAccountVerified: true,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('63 💎'), findsOneWidget);
    expect(find.textContaining('0 💎'), findsOneWidget);
    expect(find.textContaining('الشراء غير مفعّل'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('missing server record cannot replace existing profile diamonds',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: DedaOwnerDiamondSafetyPreview(
              snapshot: DedaDiamondProvenancePreview(
                existingProfileVisibleDiamonds: 63,
                currentAccountScope: firstAccount,
                serverAccountScope: 'other_person',
                serverRecordedPersonalDiamonds: 1000000,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('63 💎'), findsOneWidget);
    expect(find.textContaining('غير مؤكد'), findsOneWidget);
    expect(find.textContaining('1000000'), findsNothing);
    expect(find.textContaining('الشراء غير مفعّل'), findsOneWidget);
  });
}
