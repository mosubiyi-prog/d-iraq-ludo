import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/main.dart' as app;
import '../lib/deda_private_data_page.dart';
import '../lib/deda_private_data_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('account-scoped local data stays readable and writable without a ready SDK', () async {
    const bundle = 'deda_private_data_bundle_v1_07700000000';
    SharedPreferences.setMockInitialValues({
      'deda_favorites_v1': <String>['untouched device list'],
      bundle: jsonEncode({'favorites': <String>['account saved item']}),
    });
    app.DedaPreferences.phone = '07700000000'; app.DedaPreferences.isLoggedIn = true;
    final prefs = await SharedPreferences.getInstance();
    expect(await DedaPrivateDataBridge.readList(prefs, 'deda_favorites_v1'), ['account saved item']);
    expect(await DedaPrivateDataBridge.write(prefs, 'deda_favorites_v1', <String>['offline edit']), isTrue);
    expect(jsonDecode(prefs.getString(bundle)!)['favorites'], ['offline edit']);
    expect(prefs.getStringList('deda_favorites_v1'), ['untouched device list']);
    await Future<void>.delayed(Duration.zero);
  });
  testWidgets('actual backup page asks before adopting device data and retains it when SDK is unavailable', (tester) async {
    SharedPreferences.setMockInitialValues({'deda_favorites_v1': <String>['original-device-item']});
    app.DedaPreferences.phone = '07700000000';
    app.DedaPreferences.isLoggedIn = true;
    await tester.pumpWidget(const MaterialApp(home: DedaPrivateDataPage()));
    await tester.tap(find.byKey(const Key('deda_private_data_backup')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('deda_favorites_v1'), ['original-device-item']);
    expect(prefs.getKeys().where((k) => k.startsWith('deda_private_data_')), isEmpty);
    await tester.tap(find.byKey(const Key('deda_private_data_backup')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.textContaining('تعذّر إكمال العملية'), findsOneWidget);
    expect(prefs.getStringList('deda_favorites_v1'), ['original-device-item']);
    expect(prefs.getKeys().where((k) => k.startsWith('deda_private_data_')), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
