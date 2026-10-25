import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
// ignore: depend_on_referenced_packages
import 'package:geolocator_android/geolocator_android.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/main.dart' as app;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const invalidId = 'أدخل معرف DEDA صحيحًا للمستلم.';
  Future<void> open(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    app.DedaPreferences.phone = '07700000000';
    app.DedaPreferences.isLoggedIn = true;
    app.DedaPreferences.accountType = null;
    await tester.pumpWidget(const MaterialApp(home: app.DedaShareLocationPage()));
    await tester.pumpAndSettle();
    // No Firebase is initialized. Clear the expected preparation error before
    // inspecting what the real send callback does under a changed account.
    final context = tester.element(find.byType(app.DedaShareLocationPage));
    ScaffoldMessenger.of(context).clearSnackBars();
    await tester.pumpAndSettle();
  }
  void send(WidgetTester tester) {
    final button = find.widgetWithIcon(FilledButton, Icons.send);
    tester.widget<FilledButton>(button).onPressed!();
  }
  testWidgets('same-account page keeps original recipient validation', (tester) async {
    await open(tester);
    send(tester); await tester.pump();
    expect(find.text(invalidId), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final loggedOut in [false, true]) {
    testWidgets('old share page cannot send after ${loggedOut ? "logout" : "account change"}', (tester) async {
      await open(tester);
      if (loggedOut) {
        app.DedaPreferences.isLoggedIn = false;
      } else {
        app.DedaPreferences.phone = '07700000001';
      }
      send(tester); await tester.pump();
      // The old implementation reached validation and showed an error on B.
      // The guarded page performs no validation, GPS, share or task operation.
      expect(find.text(invalidId), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  for (final changeAccount in [false, true]) {
    testWidgets('GPS continuation ${changeAccount ? "rejects a changed account" : "keeps same-account sending"}', (tester) async {
      const channel = MethodChannel('flutter.baseflow.com/geolocator_android');
      final original = GeolocatorPlatform.instance;
      final position = Completer<Object?>();
      var gpsCalls = 0;
      GeolocatorAndroid.registerWith();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'isLocationServiceEnabled': return true;
          case 'checkPermission': return 2;
          case 'getCurrentPosition': gpsCalls++; return position.future;
          case 'cancelGetCurrentPosition': return null;
        }
        throw StateError('Unexpected GPS method ${call.method}');
      });
      addTearDown(() {
        GeolocatorPlatform.instance = original;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      await open(tester);
      await tester.enterText(find.byType(TextField), '@DEDA-ABCDEF');
      send(tester); await tester.pump(); await tester.pump();
      expect(gpsCalls, 1);
      if (changeAccount) app.DedaPreferences.phone = '07700000001';
      position.complete({
        'latitude': 33.3, 'longitude': 44.4,
        'timestamp': DateTime(2026).millisecondsSinceEpoch,
        'accuracy': 5.0, 'altitude': 0.0, 'altitude_accuracy': 0.0,
        'heading': 0.0, 'heading_accuracy': 0.0, 'speed': 0.0,
        'speed_accuracy': 0.0, 'is_mocked': false,
      });
      await tester.pump(); await tester.pump();
      // With no initialized Firebase the same-account send must reach the
      // original not-ready failure. B must never enter that backend operation.
      expect(find.text('تعذر إرسال المشاركة الآن. حاول مرة أخرى.'),
          changeAccount ? findsNothing : findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
