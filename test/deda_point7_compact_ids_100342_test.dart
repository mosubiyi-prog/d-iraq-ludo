import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/main.dart';
import '../lib/deda_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Point7 shows a compact card with the real account ID',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'deda_phone_v1': '07712345678',
    });
    await DedaPreferences.load();
    final personalId =
        DedaBackend.personalShareIdForPhone(DedaPreferences.phone).trim();
    expect(personalId, isNotEmpty);

    await tester.pumpWidget(
      const MaterialApp(home: DedaAccountInfoPage()),
    );
    final card = find.byKey(const Key('deda_point7_compact_owned_ids_card'));
    expect(card, findsOneWidget);
    expect(find.byKey(const Key('deda_point7_current_id_chip')),
        findsOneWidget);
    expect(find.text(personalId), findsOneWidget);
    expect(tester.getSize(card).height, lessThanOrEqualTo(126.0));
    expect(find.byKey(const Key('deda_point7_edit_profile_action')),
        findsOneWidget);
  });

  testWidgets('Point7 cannot activate an unverified premium ID',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'deda_phone_v1': '07712345678',
    });
    await DedaPreferences.load();
    await tester.pumpWidget(
      const MaterialApp(home: DedaAccountInfoPage()),
    );
    final switchButton = tester.widget<TextButton>(
      find.byKey(
          const Key('deda_point7_change_id_requires_verified_registry')),
    );
    expect(switchButton.onPressed, isNull,
        reason: 'No client-only fake switch or Firebase mutation allowed');
  });
}
