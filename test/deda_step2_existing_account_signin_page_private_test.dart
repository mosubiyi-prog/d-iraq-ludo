import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_step2_existing_account_signin_page.dart';

void main() {
  testWidgets('existing-account UI is OFF by default and cannot authenticate',
      (tester) async {
    expect(dedaStep2ExistingAccountEntryEnabled, false);
    await tester.pumpWidget(const MaterialApp(
        home: DedaExistingAccountSignInPage()));
    expect(find.text('لدي حساب'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('phone and PIN alone are displayed, not original ID input',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: DedaExistingAccountSignInPage()));
    final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields.length, 2);
    expect(fields[1].obscureText, true);
    expect(find.textContaining('آيدي'), findsNothing);
  });

  testWidgets('invalid phone or 6-digit PIN never calls login',
      (tester) async {
    var submitted = 0;
    await tester.pumpWidget(MaterialApp(home: DedaExistingAccountSignInPage(
      enabled: true,
      verifiedLogin: (phone, pin) async { submitted++; },
    )));
    await tester.enterText(find.byType(TextField).at(0), '078123');
    await tester.enterText(find.byType(TextField).at(1), '123456');
    await tester.pump();
    expect(tester.widget<FilledButton>(
      find.byType(FilledButton)).onPressed, isNull);
    expect(submitted, 0);
  });

  testWidgets('phone and PIN cannot submit without explicit recovery consent',
      (tester) async {
    var submitted = false;
    await tester.pumpWidget(MaterialApp(home: DedaExistingAccountSignInPage(
      enabled: true,
      verifiedLogin: (phone, pin) async { submitted = true; },
    )));
    await tester.enterText(find.byType(TextField).at(0), '07712345678');
    await tester.enterText(find.byType(TextField).at(1), '123456');
    await tester.pump();
    expect(tester.widget<FilledButton>(
      find.byType(FilledButton)).onPressed, isNull);
    expect(submitted, false);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(tester.widget<FilledButton>(
      find.byType(FilledButton)).onPressed, isNotNull);
  });

  testWidgets('explicit valid submit calls only the supplied safe delegate',
      (tester) async {
    String? submittedPhone;
    String? submittedPin;
    await tester.pumpWidget(MaterialApp(home: DedaExistingAccountSignInPage(
      enabled: true,
      verifiedLogin: (phone, pin) async {
        submittedPhone = phone;
        submittedPin = pin;
      },
    )));
    await tester.enterText(find.byType(TextField).at(0), '07712345678');
    await tester.enterText(find.byType(TextField).at(1), '123456');
    await tester.pump();
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(submittedPhone, '07712345678');
    expect(submittedPin, '123456');
  });

  testWidgets('failed delegate gives generic notice and no local success',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: DedaExistingAccountSignInPage(
      enabled: true,
      verifiedLogin: (phone, pin) async {
        throw StateError('private-server-detail-no-display');
      },
    )));
    await tester.enterText(find.byType(TextField).at(0), '07712345678');
    await tester.enterText(find.byType(TextField).at(1), '123456');
    await tester.pump();
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.textContaining('لم تُغيّر بياناتك'), findsOneWidget);
    expect(find.textContaining('private-server-detail'), findsNothing);
  });
}
