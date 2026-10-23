import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/main.dart';
import '../lib/deda_owner18_frame_purchase_action.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (var slot = 3; slot <= 5; slot++) {
    testWidgets(
        'approved lower-row portrait $slot uses the original circular geometry',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: DedaAvatarPortrait(style: slot, size: 111))));
      final portrait = find.byType(DedaAvatarPortrait);
      expect(tester.getSize(portrait), const Size(111, 111));
      final image = tester.widget<Image>(find.byType(Image));
      final provider = image.image is ResizeImage
          ? (image.image as ResizeImage).imageProvider
          : image.image;
      expect((provider as AssetImage).assetName,
          contains('deda_owner_avatars_20261023/'));
      expect(image.fit, BoxFit.cover);
      expect(find.byType(ClipOval), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('live paid frame controls stay finite inside a narrow gallery',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Wrap(children: [
      DedaOwner18FramePurchaseAction(
          originalId: '@DEDA-AB3C5D',
          frameId: 'FRAME_03',
          width: 96,
          onVerifiedOwned: () {})
    ]))));
    await tester.pump();
    expect(find.text('شراء — 1000 💎'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'editor preserves sticky preview and six free choices after new assets',
      (tester) async {
    SharedPreferences.setMockInitialValues({'deda_phone_v1': '07712345678'});
    await DedaPreferences.load();
    await tester.pumpWidget(const MaterialApp(home: DedaEditProfilePage()));
    final preview = find.byKey(const Key('deda_sticky_preview_avatar_card'));
    final y = tester.getTopLeft(preview).dy;
    await tester.drag(find.byKey(const Key('deda_edit_profile_scroll_choices')),
        const Offset(0, -520));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getTopLeft(preview).dy, closeTo(y, 0.5));
    // Dispose the editor, then let the original wallet's bounded 220ms
    // readiness retry finish. Do not change production wallet timing for QA.
    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(tester.takeException(), isNull);
  });
}
