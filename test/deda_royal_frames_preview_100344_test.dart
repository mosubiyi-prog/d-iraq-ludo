import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Original royal WebP frames allow preview without ownership or save',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'deda_phone_v1': '07712345678',
      'deda_user_name_v1': 'Demo Owner',
    });
    await DedaPreferences.load();
    final originallySaved = DedaPreferences.profileFrameStyle;
    await tester.pumpWidget(const MaterialApp(home: DedaEditProfilePage()));

    final locked = find.byKey(const Key('deda_royal_frame_tile_3'));
    expect(locked, findsOneWidget);
    await tester.ensureVisible(locked);
    await tester.pumpAndSettle();
    await tester.tap(locked);
    await tester.pump();
    expect(find.byKey(const Key('deda_royal_frame_preview_only_badge')),
        findsOneWidget);
    expect(find.byType(DedaRoyalFrameSparkle), findsOneWidget);
    final topAvatar = find.descendant(
      of: find.byKey(const Key('deda_sticky_preview_avatar_card')),
      matching: find.byType(DedaFramedAvatar),
    );
    expect(tester.widget<DedaFramedAvatar>(topAvatar).frameStyle, 3);
    expect(DedaPreferences.profileFrameStyle, originallySaved);
    // No wallet, purchase or local inventory write from a preview tap.
    final free = find.byKey(const Key('deda_royal_frame_tile_1'));
    await tester.ensureVisible(free);
    await tester.pump();
    await tester.tap(free);
    await tester.pump();
    expect(find.byKey(const Key('deda_royal_frame_preview_only_badge')),
        findsNothing);
    expect(tester.widget<DedaFramedAvatar>(topAvatar).frameStyle, 1);
  });
}
