import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_step1_google_settings_link_100439.dart';

void main() {
  testWidgets('Google account card stays hidden in protected default OFF build',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DedaGoogleSettingsLinkCard(
          phone: '9647712345678',
          originalId: '@DEDA-ABC123',
          isArabic: true,
        ),
      ),
    ));
    expect(find.byKey(const ValueKey('deda-google-link-settings-card')),
        findsNothing);
    expect(find.byKey(const ValueKey('deda-google-link-verified')),
        findsNothing);
  });
}
