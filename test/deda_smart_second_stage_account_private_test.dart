import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_step2_smart_second_stage_account_page_100439.dart';

DedaSmartSecondStageAccountPage makePage({
  required DedaCreateNewAccountVerified create,
  WidgetBuilder? existing,
  String name = 'سالم',
  String phone = '+9647701234567',
}) => DedaSmartSecondStageAccountPage(
  initialName: name,
  initialPhone: phone,
  onCreateNew: create,
  existingAccountBuilder: existing ??
      (_) => const Text('حارس الاسترجاع الأصلي', key: ValueKey('existing-guardian')),
);

Future<void> scrollToAccountConfirmation(WidgetTester tester) async {
  await tester.drag(
      find.byKey(const ValueKey('deda-smart-second-stage')),
      const Offset(0, -340));
  await tester.pumpAndSettle();
}

void main() {
  test('second-stage mode is OFF until explicit private approval', () {
    expect(dedaSmartSecondStageAccountEnabled, isFalse);
  });

  testWidgets('new account shows first name, number and six-digit PIN',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(home: makePage(
      create: (_, __, ___) async { attempts++; },
    )));
    expect(find.text('الاسم: سالم'), findsOneWidget);
    expect(find.byKey(const ValueKey('deda-second-stage-name')),
        findsOneWidget);
    expect(find.text('+9647701234567'), findsOneWidget);
    await scrollToAccountConfirmation(tester);
    final pin = tester.widget<SelectableText>(
        find.byKey(const ValueKey('deda-second-stage-new-pin'))).data!;
    expect(pin, matches(RegExp(r'^\d{6}$')));
    final create = tester.widget<FilledButton>(
        find.byKey(const ValueKey('deda-second-stage-confirm-create')));
    expect(create.onPressed, isNull);
    expect(attempts, 0);
    expect(find.text('حارس الاسترجاع الأصلي'), findsNothing);
  });

  testWidgets('second screen changes mode in place without a third route',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(home: makePage(
      create: (_, __, ___) async { attempts++; },
    )));
    await tester.tap(find.text('لدي حساب سابق'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('existing-guardian')), findsOneWidget);
    expect(find.byKey(const ValueKey('deda-second-stage-new-pin')), findsNothing);
    expect(find.byKey(const ValueKey('deda-smart-second-stage')), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(attempts, 0);
    await tester.tap(find.text('حساب جديد'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('deda-second-stage-name')), findsOneWidget);
  });

  testWidgets('server create delegate receives saved PIN only on consent',
      (tester) async {
    String? sentName, sentPhone, sentPin;
    var count = 0;
    await tester.pumpWidget(MaterialApp(home: makePage(
      create: (name, phone, pin) async {
        count++;
        sentName = name; sentPhone = phone; sentPin = pin;
      },
    )));
    await scrollToAccountConfirmation(tester);
    final pin = tester.widget<SelectableText>(
        find.byKey(const ValueKey('deda-second-stage-new-pin'))).data!;
    await tester.ensureVisible(find.byKey(
        const ValueKey('deda-second-stage-pin-saved')));
    await tester.tap(find.byKey(const ValueKey('deda-second-stage-pin-saved')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(
        const ValueKey('deda-second-stage-confirm-create')));
    await tester.tap(find.byKey(
        const ValueKey('deda-second-stage-confirm-create')));
    await tester.pumpAndSettle();
    expect(count, 1);
    expect(sentName, 'سالم');
    expect(sentPhone, '+9647701234567');
    expect(sentPin, pin);
  });

  testWidgets('duplicate phone never commits a new account',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(home: makePage(
      create: (_, __, ___) async {
        attempts++;
        throw StateError('existing-owner-number');
      },
    )));
    await scrollToAccountConfirmation(tester);
    await tester.ensureVisible(find.byKey(
        const ValueKey('deda-second-stage-pin-saved')));
    await tester.tap(find.byKey(const ValueKey('deda-second-stage-pin-saved')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(
        const ValueKey('deda-second-stage-confirm-create')));
    await tester.tap(find.byKey(const ValueKey('deda-second-stage-confirm-create')));
    await tester.pumpAndSettle();
    expect(attempts, 1);
    await tester.drag(
        find.byKey(const ValueKey('deda-smart-second-stage')),
        const Offset(0, -260));
    await tester.pumpAndSettle();
    expect(find.textContaining('هذا الرقم عنده حساب ديدا سابق'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('deda-second-stage-error')),
        findsOneWidget);
  });

  testWidgets('regenerated six-digit PIN needs fresh acknowledgement',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: makePage(
      create: (_, __, ___) async {},
    )));
    await scrollToAccountConfirmation(tester);
    await tester.ensureVisible(find.byKey(
        const ValueKey('deda-second-stage-pin-saved')));
    await tester.tap(find.byKey(const ValueKey('deda-second-stage-pin-saved')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(
        const ValueKey('deda-second-stage-new-pin-regenerate')));
    await tester.tap(find.byKey(
        const ValueKey('deda-second-stage-new-pin-regenerate')));
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(
        find.byKey(const ValueKey('deda-second-stage-pin-saved'))).value,
        isFalse);
    expect(tester.widget<FilledButton>(
        find.byKey(const ValueKey('deda-second-stage-confirm-create'))).onPressed,
        isNull);
  });

  testWidgets('invalid normalized phone cannot create a new account',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(home: makePage(
      phone: '+964770', create: (_, __, ___) async { attempts++; },
    )));
    await scrollToAccountConfirmation(tester);
    await tester.ensureVisible(find.byKey(
        const ValueKey('deda-second-stage-pin-saved')));
    await tester.tap(find.byKey(const ValueKey('deda-second-stage-pin-saved')));
    await tester.pump();
    expect(tester.widget<FilledButton>(
        find.byKey(const ValueKey('deda-second-stage-confirm-create'))).onPressed,
        isNull);
    expect(attempts, 0);
  });
}
