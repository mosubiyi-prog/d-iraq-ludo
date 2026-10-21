import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_social_service.dart';
import 'package:d_iraq_ludo/deda_qa32_live_friend_appearance.dart';

void main() {
  const original = DedaSocialProfile(
    publicId: '@DEDA-ABC123',
    ownerUid: 'stable-owner-uid',
    displayName: 'مصمم تطبيق ديدا',
    avatarStyle: 3,
    frameStyle: 4,
    backgroundStyle: 2,
    level: 7,
    badges: ['badge_elite'],
  );

  test('same public owner may refresh avatar frame background and level', () {
    const next = DedaSocialProfile(
      publicId: '@DEDA-ABC123', ownerUid: 'stable-owner-uid',
      displayName: 'مصمم تطبيق ديدا',
      avatarStyle: 1, frameStyle: 5, backgroundStyle: 3,
      level: 8, badges: ['badge_elite'],
    );
    final applied = DedaQa32LiveFriendAppearance.verifiedUpdate(
      original, next,
    );
    expect(applied.avatarStyle, 1);
    expect(applied.frameStyle, 5);
    expect(applied.backgroundStyle, 3);
    expect(applied.level, 8);
  });

  test('different owner UID cannot impersonate same identifier', () {
    const impostor = DedaSocialProfile(
      publicId: '@DEDA-ABC123', ownerUid: 'different-uid',
      displayName: 'مستخدم مختلف',
      avatarStyle: 0, frameStyle: 0, backgroundStyle: 0,
      level: 1, badges: <String>[],
    );
    final selected = DedaQa32LiveFriendAppearance.verifiedUpdate(
      original, impostor,
    );
    expect(identical(selected, original), true);
  });

  test('different original ID cannot replace a friend profile', () {
    const impostor = DedaSocialProfile(
      publicId: '@DEDA-DEF456', ownerUid: 'stable-owner-uid',
      displayName: 'اسم آخر',
      avatarStyle: 0, frameStyle: 0, backgroundStyle: 0,
      level: 1, badges: <String>[],
    );
    expect(
      identical(DedaQa32LiveFriendAppearance.verifiedUpdate(
        original, impostor,
      ), original),
      true,
    );
  });

  testWidgets('no Firebase cold start preserves existing friend portrait',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DedaQa32LiveFriendAppearance(
          initial: original,
          builder: (context, shown) => Text(
            shown.displayName + ' / ' + shown.frameStyle.toString(),
          ),
        ),
      ),
    ));
    expect(find.text('مصمم تطبيق ديدا / 4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('missing or unverifiable public record remains safe fallback', () {
    expect(identical(
      DedaQa32LiveFriendAppearance.verifiedUpdate(original, null),
      original,
    ), isTrue);
    const noOwner = DedaSocialProfile(
      publicId: '@DEDA-ABC123', ownerUid: '',
      displayName: 'unknown', avatarStyle: 5,
      frameStyle: 5, backgroundStyle: 5, level: 1, badges: [],
    );
    expect(identical(
      DedaQa32LiveFriendAppearance.verifiedUpdate(noOwner, original),
      noOwner,
    ), isTrue);
  });
}
