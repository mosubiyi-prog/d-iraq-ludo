import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
// Exercise the pinned Android plugin's cancellation implementation, rather
// than a fake that merely repeats our timeout behavior.
// ignore: depend_on_referenced_packages
import 'package:geolocator_android/geolocator_android.dart';
import '../lib/main.dart' as app;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter.baseflow.com/geolocator_android');
  late GeolocatorPlatform original;
  late List<Completer<Object?>> requests;
  late List<String> started;
  late List<String> cancelled;
  var permission = 2;
  Map<String, Object?> position() => {
    'latitude': 33.3, 'longitude': 44.4,
    'timestamp': DateTime(2026).millisecondsSinceEpoch,
    'accuracy': 5.0, 'altitude': 0.0, 'altitude_accuracy': 0.0,
    'heading': 0.0, 'heading_accuracy': 0.0, 'speed': 0.0,
    'speed_accuracy': 0.0, 'is_mocked': false,
  };
  setUp(() {
    original = GeolocatorPlatform.instance;
    GeolocatorAndroid.registerWith();
    requests = []; started = []; cancelled = []; permission = 2;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'isLocationServiceEnabled': return true;
        case 'checkPermission': return permission;
        case 'requestPermission': return permission;
        case 'getCurrentPosition':
          started.add((call.arguments as Map)['requestId'] as String);
          final pending = Completer<Object?>(); requests.add(pending);
          return pending.future;
        case 'cancelGetCurrentPosition':
          cancelled.add((call.arguments as Map)['requestId'] as String);
          return null;
      }
      throw StateError('Unexpected location operation: ${call.method}');
    });
  });
  tearDown(() {
    for (final request in requests) {
      if (!request.isCompleted) request.complete(position());
    }
    GeolocatorPlatform.instance = original;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  Future<void> openSearch(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: app.DedaPlaceSearchPage(initialQuery: 'Baghdad'),
    ));
    await tester.pump(); await tester.pump();
  }
  testWidgets('actual search times out, cancels the same Android request and allows explicit retry', (tester) async {
    await openSearch(tester);
    expect(started, hasLength(1));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    final busyButton = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.search));
    expect(busyButton.onPressed, isNull);
    await tester.pump(const Duration(seconds: 12)); await tester.pump();
    expect(cancelled, [started.single]);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    final retry = find.widgetWithIcon(IconButton, Icons.search);
    expect(tester.widget<IconButton>(retry).onPressed, isNotNull);
    await tester.tap(retry); await tester.pump(); await tester.pump();
    expect(started, hasLength(2)); expect(started[0], isNot(started[1]));
    // A late reply to the timed-out request cannot complete the newer search.
    requests.first.complete(position()); await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 12)); await tester.pump();
    expect(cancelled, started);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('permission denial exits actual search without starting GPS', (tester) async {
    permission = 1;
    await openSearch(tester);
    expect(started, isEmpty); expect(cancelled, isEmpty);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('leaving search during GPS does not continue into registered-place loading', (tester) async {
    await openSearch(tester); expect(started, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    requests.single.complete(position()); await tester.pump(); await tester.pump();
    // The original continuation would start the account/database path after
    // disposal. No Firebase app or registered-place setup exists in this test.
    expect(tester.takeException(), isNull); expect(cancelled, isEmpty);
    await tester.pump(const Duration(seconds: 13));
    expect(tester.takeException(), isNull);
  });
}
