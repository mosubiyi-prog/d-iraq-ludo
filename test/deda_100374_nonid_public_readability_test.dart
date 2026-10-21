import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/main.dart';
import 'package:d_iraq_ludo/deda_social_service.dart';

// 100374: public readability is a NON-identifier backend/ownership fix.
// Premium alias resolution stays OFF: the canonical fallback must still be
// legible over the dark owner-card background, including on the other device.
void main() {
  const viewerProfile = DedaSocialProfile(
    publicId: '@DEDA-ABC123',
    ownerUid: 'verified-owner',
    displayName: 'سالم حسن',
    avatarStyle: 2,
    frameStyle: 5,
    backgroundStyle: 3,
    level: 1,
    badges: <String>[],
  );

  testWidgets('friend name is white and original fallback text is legible',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: DedaFriendPublicProfilePage(profile: viewerProfile),
    ));
    final name = tester.widget<Text>(find.text('سالم حسن'));
    expect(name.maxLines, 2);
    expect(name.style?.color, Colors.white);
    final idTexts =
        tester.widgetList<Text>(find.text('@DEDA-ABC123')).toList();
    expect(idTexts, isNotEmpty);
    expect(idTexts.any((t) => t.style?.color == Colors.white), isTrue,
        reason: 'Canonical fallback on the dark public card must be white');
    expect(tester.takeException(), isNull);
  });
}
