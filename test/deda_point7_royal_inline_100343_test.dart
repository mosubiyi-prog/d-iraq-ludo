import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/main.dart';
import '../lib/deda_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Navy-and-gold compact real ID; inline editor never navigates',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'deda_phone_v1': '07712345678',
    });
    await DedaPreferences.load();
    final id = DedaBackend.personalShareIdForPhone(DedaPreferences.phone);
    await tester.pumpWidget(const MaterialApp(home: DedaAccountInfoPage()));
    final cardFinder =
        find.byKey(const Key('deda_point7_compact_owned_ids_card'));
    expect(cardFinder, findsOneWidget);
    expect(tester.getSize(cardFinder).height, lessThanOrEqualTo(126));
    final card = tester.widget<Container>(cardFinder);
    final decoration = card.decoration! as BoxDecoration;
    expect(decoration.gradient, isA<LinearGradient>());
    expect((decoration.gradient! as LinearGradient).colors.first,
        const Color(0xFF101D45));
    final chip = tester.widget<Container>(
        find.byKey(const Key('deda_point7_current_id_chip')));
    expect((chip.decoration! as BoxDecoration).color,
        const Color(0xFF304369)); // Not white.

    final detail = find.byKey(const Key('deda_identifier_management_inline'));
    expect(detail, findsNothing);
    await tester.tap(find.byKey(const Key('deda_point7_edit_profile_action')));
    await tester.pumpAndSettle();
    expect(detail, findsOneWidget);
    expect(find.text(id), findsWidgets);
    expect(find.byType(DedaEditProfilePage), findsNothing);
    expect(find.byKey(const Key('deda_identifier_management_sheet')),
        findsNothing);
    expect(find.text('معرّفاتي المملوكة'), findsOneWidget);

    final change = tester.widget<TextButton>(
      find.byKey(const Key('deda_point7_change_id_requires_verified_registry')));
    expect(change.onPressed, isNull);
    await tester.tap(find.byKey(const Key('deda_point7_edit_profile_action')));
    await tester.pumpAndSettle();
    expect(detail, findsNothing);
  });
}
