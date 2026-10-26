import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/main.dart' as app;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('actual editor reports unavailable ownership and allows an explicit retry when SDK is not ready', (tester) async {
    SharedPreferences.setMockInitialValues({'deda_phone_v1': '07712345678'});
    await app.DedaPreferences.load();
    await tester.pumpWidget(const MaterialApp(home: app.DedaEditProfilePage()));
    await tester.pump();
    final unavailable = find.byKey(const Key('deda_owned_frames_unavailable'));
    expect(unavailable, findsOneWidget);
    expect(find.byKey(const Key('deda_owned_frames_loading')), findsNothing);
    final retry = find.descendant(of: unavailable, matching: find.byType(TextButton));
    expect(retry, findsOneWidget);
    expect(tester.widget<TextButton>(retry).onPressed, isNotNull);
    await tester.tap(retry);
    await tester.pump();
    expect(unavailable, findsOneWidget);
    expect(find.byKey(const Key('deda_owned_frames_loading')), findsNothing);
    // Dispose animated artwork and finish the existing wallet readiness wait.
    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(tester.takeException(), isNull);
  });
}
