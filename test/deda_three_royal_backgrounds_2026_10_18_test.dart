import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all six legacy colors remain in their original positions', () {
    expect(dedaProfileBackgroundColors(0),
        <Color>[const Color(0xFFF4FBF2), const Color(0xFFDCEEDD)]);
    expect(dedaProfileBackgroundColors(1),
        <Color>[const Color(0xFFF2FAFC), const Color(0xFFDCEEF3)]);
    expect(dedaProfileBackgroundColors(2),
        <Color>[const Color(0xFFFFF9EF), const Color(0xFFF0E1C9)]);
    expect(dedaProfileBackgroundColors(3),
        <Color>[const Color(0xFFFAF6FD), const Color(0xFFE7DDF1)]);
    expect(dedaProfileBackgroundColors(4),
        <Color>[const Color(0xFFF1FBF8), const Color(0xFFD6ECE5)]);
    expect(dedaProfileBackgroundColors(5),
        <Color>[const Color(0xFFFFF5F6), const Color(0xFFF0DBDE)]);
    expect(dedaProfileBackgroundColors(6), isNotEmpty);
    expect(dedaProfileBackgroundColors(7), isNotEmpty);
    expect(dedaProfileBackgroundColors(8), isNotEmpty);
  });

  test('royal selection persists in the same account-local background key',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'deda_phone_v1': '07712345678',
      'deda_user_name_v1': 'DEDA Test',
    });
    await DedaPreferences.load();
    for (final style in <int>[6, 7, 8]) {
      await DedaPreferences.setProfileAppearance(
        avatarStyle: 0,
        frameStyle: 0,
        backgroundStyle: style,
      );
      expect(DedaPreferences.profileBackgroundStyle, style);
      await DedaPreferences.load();
      expect(DedaPreferences.profileBackgroundStyle, style);
    }
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getInt('deda_profile_background_v1_07712345678'),
      8,
    );
  });

  testWidgets('all nine options use the same edit page and live pinned preview',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'deda_phone_v1': '07712345678',
      'deda_user_name_v1': 'DEDA Test',
    });
    await DedaPreferences.load();
    await tester.pumpWidget(
      const MaterialApp(home: DedaEditProfilePage()),
    );
    final pinned = find.byKey(const Key('deda_sticky_preview_avatar_card'));
    final choices = find.byKey(const Key('deda_edit_profile_scroll_choices'));
    expect(pinned, findsOneWidget);
    expect(choices, findsOneWidget);
    final initialY = tester.getTopLeft(pinned).dy;

    // Scroll to the last row; the sticky avatar never scrolls away.
    final last = find.byKey(const ValueKey<String>('deda_background_tile_8'));
    for (var attempt = 0; attempt < 14 && last.evaluate().isEmpty; attempt++) {
      await tester.drag(choices, const Offset(0, -180));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 190));
    }
    await tester.pump(const Duration(milliseconds: 170));
    expect(last, findsOneWidget);
    await tester.ensureVisible(last);
    await tester.tap(last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    expect(tester.getTopLeft(pinned).dy, closeTo(initialY, 0.5));
    expect(
      find.descendant(
        of: pinned,
        matching: find.byKey(const Key('deda_edit_live_royal_background')),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('deda_royal_background_art_8')),
      findsWidgets,
    );

    // Selection only changes local preview; not stored before Save.
    expect(DedaPreferences.profileBackgroundStyle, 0);
    expect(DedaRoyalBackgroundArtwork.assetFor(7),
        'assets/deda_royal_backgrounds/deda_royal_bg_emerald.webp');
    expect(DedaRoyalBackgroundArtwork.assetFor(8),
        'assets/deda_royal_backgrounds/deda_royal_bg_burgundy.webp');
  });
}
