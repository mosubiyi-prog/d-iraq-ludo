import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:d_iraq_ludo/main.dart';
import 'package:d_iraq_ludo/deda_team_page.dart';
import 'package:d_iraq_ludo/deda_private_data_bridge.dart';

void main() {
  const legacy = 'deda_contact_draft_v1';
  String draft(String phone, String message) => jsonEncode({
    'type': 'company', 'name': 'Test owner', 'phone': phone,
    'message': message, 'imagePaths': <String>[],
  });

  Future<void> openContact(WidgetTester tester, String phone,
      {required bool signedIn}) async {
    DedaPreferences.isLoggedIn = signedIn;
    DedaPreferences.phone = phone;
    DedaPreferences.userName = signedIn ? 'Test owner' : '';
    await tester.pumpWidget(const MaterialApp(home: DedaContactPage()));
    await tester.pumpAndSettle();
  }

  String message(WidgetTester tester) =>
      tester.widgetList<EditableText>(find.byType(EditableText))
        .last.controller.text;

  tearDown(() {
    DedaPreferences.isLoggedIn = false;
    DedaPreferences.phone = '';
    DedaPreferences.userName = '';
  });

  testWidgets('guest and unrelated owner cannot read legacy contact draft',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      legacy: draft('07700000001', 'private legacy message'),
    });
    await openContact(tester, '', signedIn: false);
    expect(message(tester), isEmpty);
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await openContact(tester, '07700000002', signedIn: true);
    expect(message(tester), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('same local account keeps legacy draft unless scoped value exists',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      legacy: draft('07700000001', 'existing owner draft'),
    });
    await openContact(tester, '07700000001', signedIn: true);
    expect(message(tester), 'existing owner draft');
    await tester.pumpWidget(const SizedBox());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$legacy:account:07700000001', '');
    await openContact(tester, '07700000001', signedIn: true);
    expect(message(tester), isEmpty);
    expect(prefs.getString(legacy), contains('existing owner draft'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('scoped guest and owner drafts stay separate', (tester) async {
    SharedPreferences.setMockInitialValues({
      '$legacy:guest': draft('', 'guest message'),
      '$legacy:account:07700000001': draft('07700000001', 'owner message'),
    });
    await openContact(tester, '', signedIn: false);
    expect(message(tester), 'guest message');
    await tester.pumpWidget(const SizedBox());
    await openContact(tester, '07700000001', signedIn: true);
    expect(message(tester), 'owner message');
    await tester.pumpWidget(const SizedBox());
  });

  test('existing bridge writes and clears only the current scoped draft', () async {
    SharedPreferences.setMockInitialValues({
      legacy: draft('07700000001', 'legacy retained'),
    });
    final prefs = await SharedPreferences.getInstance();
    DedaPreferences.isLoggedIn = true;
    DedaPreferences.phone = '07700000001';
    expect(await DedaPrivateDataBridge.readString(prefs, legacy), contains('legacy retained'));
    expect(await DedaPrivateDataBridge.write(prefs, legacy, draft('07700000001', 'new draft')), isTrue);
    DedaPreferences.phone = '07700000002';
    expect(await DedaPrivateDataBridge.readString(prefs, legacy), isNull);
    await DedaPrivateDataBridge.write(prefs, legacy, draft('07700000002', 'second owner'));
    DedaPreferences.phone = '07700000001';
    await DedaPrivateDataBridge.write(prefs, legacy, null);
    expect(await DedaPrivateDataBridge.readString(prefs, legacy), '');
    expect(prefs.getString(legacy), contains('legacy retained'));
    expect(prefs.getString('$legacy:account:07700000002'), contains('second owner'));
  });

  testWidgets('original team shows seven cards at phone and tablet widths',
      (tester) async {
    for (final size in [const Size(360, 800), const Size(900, 1200)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(const MaterialApp(home: DedaTeamPage()));
      await tester.pumpAndSettle();
      expect(find.text('فريق DEDA'), findsOneWidget);
      expect(find.text('المدير والمنفذ للتطبيق'), findsOneWidget);
      expect(find.text('منفذ الألوان'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.pumpWidget(const SizedBox());
  });
}
