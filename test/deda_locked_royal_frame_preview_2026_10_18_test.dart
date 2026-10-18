import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Three locked royal frames replace slots, preview without owning', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'deda_phone_v1': '07712345678',
      'deda_user_name_v1': 'DEDA Test User',
    });
    await DedaPreferences.load();
    final before = DedaPreferences.profileFrameStyle;
    await tester.pumpWidget(const MaterialApp(home: DedaEditProfilePage()));

    final pinned = find.byKey(const Key('deda_sticky_preview_avatar_card'));
    final gallery = find.byKey(const Key('deda_edit_profile_scroll_choices'));
    expect(pinned, findsOneWidget);
    expect(gallery, findsOneWidget);
    final y = tester.getTopLeft(pinned).dy;

    for (var index = 0; index < 6; index++) {
      expect(find.byKey(ValueKey('deda_frame_slot_$index')), findsOneWidget);
    }
    final premium = find.byKey(const ValueKey('deda_frame_slot_3'));
    await tester.ensureVisible(premium);
    await tester.tap(premium);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('deda_locked_frame_preview_only_notice')),
        findsOneWidget);
    expect(DedaPreferences.profileFrameStyle, before,
        reason: 'Preview cannot save a locked frame or alter account state');
    final displayed = tester.widget<DedaFramedAvatar>(
      find.descendant(of: pinned, matching: find.byType(DedaFramedAvatar)).first,
    );
    expect(displayed.frameStyle, 3);
    expect(tester.getTopLeft(pinned).dy, closeTo(y, 0.5));

    final second = find.byKey(const ValueKey('deda_frame_slot_4'));
    await tester.ensureVisible(second);
    await tester.tap(second);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(pinned).dy, closeTo(y, 0.5));
    expect(DedaPreferences.profileFrameStyle, before);
  });
}
