import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const phone = '07712345678';
  const key = 'deda_profile_avatar_v1_07712345678';
  const migration = 'deda_royal_avatar_choice_migrated_v1_07712345678';

  for (var oldStyle = 0; oldStyle <= 5; oldStyle++) {
    test('old user avatar $oldStyle remains unchanged after upgrade', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'deda_phone_v1': phone,
        key: oldStyle,
      });
      await DedaPreferences.load();
      final expected = oldStyle <= 2 ? oldStyle + 6 : oldStyle;
      expect(DedaPreferences.profileAvatarStyle, expected);
      var prefs = await SharedPreferences.getInstance();
      // 100346: existing choice is mapped in memory without any storage
      // write during app startup. The old raw value is not destroyed.
      expect(prefs.getInt(key), oldStyle);
      expect(prefs.getBool(migration), isNull);

      // On next start the same original choice remains visible.
      await DedaPreferences.load();
      prefs = await SharedPreferences.getInstance();
      expect(DedaPreferences.profileAvatarStyle, expected);
      expect(prefs.getInt(key), oldStyle);
      expect(prefs.getBool(migration), isNull);
    });
  }

  test('explicit appearance save persists the resolved classic avatar once', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'deda_phone_v1': phone,
      key: 1,
    });
    await DedaPreferences.load();
    expect(DedaPreferences.profileAvatarStyle, 7);
    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(key), 1);
    expect(prefs.getBool(migration), isNull);
    await DedaPreferences.setProfileAppearance(
      avatarStyle: DedaPreferences.profileAvatarStyle,
      frameStyle: 0,
      backgroundStyle: 0,
    );
    prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(key), 7);
    expect(prefs.getBool(migration), isTrue);
    await DedaPreferences.load();
    expect(DedaPreferences.profileAvatarStyle, 7);
  });

  test('fresh account defaults to new royalty, then persists its choice', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'deda_phone_v1': phone,
    });
    await DedaPreferences.load();
    expect(DedaPreferences.profileAvatarStyle, 0);
    await DedaPreferences.setProfileAppearance(
      avatarStyle: 2, frameStyle: 0, backgroundStyle: 0);
    await DedaPreferences.load();
    expect(DedaPreferences.profileAvatarStyle, 2);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(migration), isTrue);
  });

  test('switching an old avatar to royalty never remigrates', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'deda_phone_v1': phone,
      key: 0,
    });
    await DedaPreferences.load();
    expect(DedaPreferences.profileAvatarStyle, 6);
    await DedaPreferences.setProfileAppearance(
      avatarStyle: 1, frameStyle: 0, backgroundStyle: 0);
    await DedaPreferences.load();
    expect(DedaPreferences.profileAvatarStyle, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(key), 1);
  });

  testWidgets('royal portrait uses an actual asset image layer', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DedaAvatarPortrait(style: 0, size: 100))));
    expect(find.byType(Image), findsOneWidget);
    final img = tester.widget<Image>(find.byType(Image));
    // Image.asset may wrap AssetImage in ResizeImage for cacheWidth; both
    // representations still load the approved JPEG from Flutter assets.
    final provider = img.image is ResizeImage
        ? (img.image as ResizeImage).imageProvider
        : img.image;
    expect(provider, isA<AssetImage>());
    expect((provider as AssetImage).assetName, contains('deda_avatar_male_royal.jpg'));
    expect(img.fit, BoxFit.cover);
  });

  testWidgets('retained classic portrait is not replaced by a royal picture', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DedaAvatarPortrait(style: 6, size: 100))));
    expect(find.byType(Image), findsNothing);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}