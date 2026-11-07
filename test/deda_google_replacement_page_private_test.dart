import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_step2_existing_account_signin_page.dart';
import 'package:d_iraq_ludo/deda_google_recovery_progress_100439.dart';

void main() {
  testWidgets('replacement Google button stays absent by default',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: DedaExistingAccountSignInPage(
      enabled: true,
      verifiedGoogleLogin: (_) async => DedaGoogleRecoveryOutcome.identityVerifiedOnly,
    )));
    expect(find.byKey(const ValueKey('deda-existing-owner-google-login')),
        findsNothing);
  });

  testWidgets('Google button needs explicit consent, not phone or PIN',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: DedaExistingAccountSignInPage(
      enabled: true, googleEnabled: true,
      verifiedGoogleLogin: (report) async {
        calls++;
        report(DedaGoogleRecoveryStage.accountChosen);
        report(DedaGoogleRecoveryStage.googleTokenReceived);
        report(DedaGoogleRecoveryStage.existingGoogleProviderResolved);
        report(DedaGoogleRecoveryStage.firebaseOriginalUidSignedIn);
        report(DedaGoogleRecoveryStage.originalUserReadFromServer);
        report(DedaGoogleRecoveryStage.ownerDocumentsReadFromServer);
        report(DedaGoogleRecoveryStage.originalOwnerVerified);
        return DedaGoogleRecoveryOutcome.identityVerifiedOnly;
      },
    )));
    expect(find.byKey(const ValueKey('deda-existing-owner-google-login')),
        findsOneWidget);
    final btn = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('deda-existing-owner-google-login')));
    expect(btn.onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    final active = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('deda-existing-owner-google-login')));
    expect(active.onPressed, isNotNull);
    await tester.ensureVisible(
        find.byKey(const ValueKey('deda-existing-owner-google-login')));
    await tester.tap(
        find.byKey(const ValueKey('deda-existing-owner-google-login')));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.textContaining('استرجاع البيانات والممتلكات لم يكتمل بعد'),
        findsOneWidget);
    expect(find.text('85%'), findsOneWidget);
    expect(find.byKey(const ValueKey('deda-google-recovery-complete')),
        findsNothing);
  });

  testWidgets('failed Google identity shows safe error, no restore claim',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: DedaExistingAccountSignInPage(
      enabled: true, googleEnabled: true,
      verifiedGoogleLogin: (report) async {
        calls++;
        report(DedaGoogleRecoveryStage.accountChosen);
        report(DedaGoogleRecoveryStage.googleTokenReceived);
        throw StateError('unlinked-or-foreign-owner');
      },
    )));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.ensureVisible(
        find.byKey(const ValueKey('deda-existing-owner-google-login')));
    await tester.tap(
        find.byKey(const ValueKey('deda-existing-owner-google-login')));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.textContaining('لم تُسترجع أي بيانات'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    expect(find.byKey(const ValueKey('deda-google-retry')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('deda-google-recovery-complete')),
        findsNothing);
  });

  testWidgets('failure freezes progress red and explicit retry starts from 0',
      (tester) async {
    var calls = 0;
    DedaGoogleRecoveryProgress? secondReport;
    await tester.pumpWidget(MaterialApp(home: DedaExistingAccountSignInPage(
      enabled: true, googleEnabled: true,
      verifiedGoogleLogin: (report) async {
        calls++;
        if (calls == 1) {
          report(DedaGoogleRecoveryStage.accountChosen);
          report(DedaGoogleRecoveryStage.googleTokenReceived);
          throw StateError('network-probe-failed');
        }
        secondReport = report;
        // Keep future pending to inspect retry zero and real stage updates.
        return DedaGoogleRecoveryOutcome.cancelled;
      },
    )));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.ensureVisible(
        find.byKey(const ValueKey('deda-existing-owner-google-login')));
    await tester.tap(
        find.byKey(const ValueKey('deda-existing-owner-google-login')));
    await tester.pumpAndSettle();
    expect(find.text('25%'), findsOneWidget);
    expect(find.textContaining('توقف التحقق'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('deda-google-retry')));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(secondReport, isNotNull);
    expect(find.text('0%'), findsOneWidget);
    expect(find.byKey(const ValueKey('deda-google-recovery-complete')),
        findsNothing);
  });

  testWidgets('100 percent checkmark only after separate full-account result',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: DedaExistingAccountSignInPage(
      enabled: true, googleEnabled: true,
      verifiedGoogleLogin: (report) async {
        report(DedaGoogleRecoveryStage.originalOwnerVerified);
        return DedaGoogleRecoveryOutcome.fullAccountRestored;
      },
    )));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.ensureVisible(
        find.byKey(const ValueKey('deda-existing-owner-google-login')));
    await tester.tap(
        find.byKey(const ValueKey('deda-existing-owner-google-login')));
    await tester.pumpAndSettle();
    expect(find.text('100%'), findsOneWidget);
    expect(find.byKey(const ValueKey('deda-google-recovery-complete')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('deda-google-retry')), findsNothing);
  });

  testWidgets('cancelled Google choice never claims account restoration',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: DedaExistingAccountSignInPage(
      enabled: true, googleEnabled: true,
      verifiedGoogleLogin: (_) async => DedaGoogleRecoveryOutcome.cancelled,
    )));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.ensureVisible(
        find.byKey(const ValueKey('deda-existing-owner-google-login')));
    await tester.tap(
        find.byKey(const ValueKey('deda-existing-owner-google-login')));
    await tester.pumpAndSettle();
    expect(find.textContaining('استرجاع البيانات والممتلكات لم يكتمل بعد'),
        findsNothing);
    expect(find.textContaining('لم تُسترجع أي بيانات'), findsNothing);
  });
}
