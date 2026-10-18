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
    expect(find.byKey(const Key('deda_point7_inline_id_manager')),
        findsNothing);
    expect(tester.getSize(card).height, lessThanOrEqualTo(126.0));
    expect(find.byKey(const Key('deda_point7_edit_identifier_action')),
        findsOneWidget);
  });

  testWidgets('Point7 switch opens management but cannot activate without registry',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'deda_phone_v1': '07712345678',
    });
    await DedaPreferences.load();
    await tester.pumpWidget(
      const MaterialApp(home: DedaAccountInfoPage()),
    );
    expect(find.byType(DedaEditProfilePage), findsNothing);
    await tester.tap(
      find.byKey(const Key('deda_point7_switch_opens_id_manager')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('deda_point7_inline_id_manager')),
        findsOneWidget);
    expect(find.byType(DedaEditProfilePage), findsNothing,
        reason: 'ID management must never open frames/portrait editing');
    final activate = tester.widget<OutlinedButton>(
      find.byKey(const Key('deda_point7_activate_requires_verified_ownership')),
    );
    expect(activate.onPressed, isNull,
        reason: 'No unverified local ID activation or backend mutation');
  });

  testWidgets('Point7 edit stays on account page instead of frames',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'deda_phone_v1': '07712345678',
    });
    await DedaPreferences.load();
    await tester.pumpWidget(
      const MaterialApp(home: DedaAccountInfoPage()),
    );
    await tester.tap(
      find.byKey(const Key('deda_point7_edit_identifier_action')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('deda_point7_inline_id_manager')),
        findsOneWidget);
    expect(find.byType(DedaEditProfilePage), findsNothing);
  });
}
