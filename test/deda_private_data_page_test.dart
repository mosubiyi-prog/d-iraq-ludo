import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/main.dart' as app;
import '../lib/deda_private_data_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
