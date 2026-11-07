import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_step2_existing_account_signin_page.dart';

void main() {
  testWidgets('replacement Google button stays absent by default',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: DedaExistingAccountSignInPage(
      enabled: true,
      verifiedGoogleLogin: () async => true,
    )));
    expect(find.byKey(const ValueKey('deda-existing-owner-google-login')),
        findsNothing);
  });

  testWidgets('Google button needs explicit consent, not phone or PIN',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: DedaExistingAccountSignInPage(
      enabled: true, googleEnabled: true,
      verifiedGoogleLogin: () async { calls++; return true; },
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
  });

  testWidgets('failed Google identity shows safe error, no restore claim',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: DedaExistingAccountSignInPage(
      enabled: true, googleEnabled: true,
      verifiedGoogleLogin: () async {
        calls++;
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
  });

  testWidgets('cancelled Google choice never claims account restoration',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: DedaExistingAccountSignInPage(
      enabled: true, googleEnabled: true,
      verifiedGoogleLogin: () async => false,
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
