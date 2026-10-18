import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('edit preview stays pinned when gallery scrolls',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'deda_phone_v1': '07712345678',
    });
    await DedaPreferences.load();
    await tester.pumpWidget(
      const MaterialApp(home: DedaEditProfilePage()),
    );

    final preview =
        find.byKey(const Key('deda_sticky_preview_avatar_card'));
    final gallery =
        find.byKey(const Key('deda_edit_profile_scroll_choices'));
    expect(preview, findsOneWidget);
    expect(gallery, findsOneWidget);
    final initialY = tester.getTopLeft(preview).dy;

    await tester.drag(gallery, const Offset(0, -520));
    // Ornamental animation keeps producing frames by design; check the
    // fixed card after bounded layout pumps rather than pumpAndSettle().
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    expect(find.byKey(const Key('deda_sticky_preview_avatar_card')),
        findsOneWidget);
    expect(tester.getTopLeft(preview).dy, closeTo(initialY, 0.5));
    expect(tester.getSize(preview).height, lessThanOrEqualTo(160));
  });
}
