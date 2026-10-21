import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/main.dart';
import 'package:d_iraq_ludo/deda_social_service.dart';

void main() {
  const name = 'مصمم تطبيق ديدا';
  const canonical = '@DEDA-ABC123';

  const publicProfile = DedaSocialProfile(
    publicId: canonical,
    ownerUid: 'verified-owner',
    displayName: name,
    avatarStyle: 3,
    frameStyle: 4,
    backgroundStyle: 2,
    level: 7,
    badges: ['badge_elite'],
  );

  testWidgets('public view uses OWNER portrait and verified stored frame',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: DedaFriendPublicProfilePage(profile: publicProfile),
    ));
    final matches = tester.widgetList<DedaFramedAvatar>(
        find.byType(DedaFramedAvatar)).toList();
    expect(matches, isNotEmpty);
    expect(matches.first.avatarStyle, 3);
    expect(matches.first.frameStyle, 4);
    expect(find.text(name), findsOneWidget);
    expect(find.text(canonical), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('royal public hero uses white contrast and two name lines',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: DedaFriendPublicProfilePage(profile: publicProfile),
    ));
    final publicName = tester.widget<Text>(find.text(name));
    expect(publicName.maxLines, 2);
    expect(publicName.style?.color, Colors.white);
    final royal = find.byWidgetPredicate((widget) {
      if (widget is! Container || widget.decoration is! BoxDecoration) {
        return false;
      }
      final decoration = widget.decoration! as BoxDecoration;
      final gradient = decoration.gradient;
      return gradient is LinearGradient &&
          gradient.colors.contains(const Color(0xFF092A63)) &&
          gradient.colors.contains(const Color(0xFF51204E)) &&
          decoration.borderRadius == BorderRadius.circular(29);
    });
    expect(royal, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('public view only exposes approved public profile metadata',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: DedaFriendPublicProfilePage(profile: publicProfile),
    ));
    expect(find.text('نخبوي'), findsOneWidget);
    expect(find.textContaining('المستوى 7'), findsWidgets);
    expect(find.textContaining('رقم الهاتف'), findsOneWidget);
    expect(find.textContaining('998,960'), findsNothing);
    expect(find.textContaining('975,645'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
