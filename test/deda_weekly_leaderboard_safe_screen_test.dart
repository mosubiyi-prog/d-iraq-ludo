import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/deda_weekly_leaderboard_safe_screen.dart';

void main() {
  Map<String, Object?> packet({int points = 20}) {
    Map<String, Object?> week(String status) => <String, Object?>{
          'verified': true,
          'weekId': 'week-$status',
          'status': status,
          'rows': <Map<String, Object?>>[
            {
              'place': 1,
              'participantId': 'verified-participant-0001',
              'displayName': 'لاعب ديدا موثق',
              'activePublicId': '@DEDA-ABC123',
              'weeklyPoints': points,
              'verifiedTaskCompletions': points ~/ 20,
              'diamondsIfFinalWinner': 150,
            },
          ],
          'viewerParticipantId': 'verified-participant-0001',
          'viewerPlace': 1,
          'remainingMs': status == 'live' ? 90000 : 0,
          'rewardsCredited': false,
        };
    return <String, Object?>{
      'readOnly': true,
      'source': 'future_server_issued_only',
      'current': week('live'),
      'previous': week('closed'),
    };
  }

  testWidgets('without approved server no fetch/no fake user and no scroll',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const MaterialApp(
      home: DedaWeeklyLeaderboardSafeScreen(),
    ));
    expect(find.byType(Scrollable), findsNothing);
    expect(find.textContaining('الترتيب قيد التحقق'), findsOneWidget);
    expect(find.text('لاعب ديدا موثق'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('trusted payload loads and keeps single fixed viewport',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      home: DedaWeeklyLeaderboardSafeScreen(
        loadVerifiedStandings: () async => packet(),
        currentAccountStillAuthorized: () => true,
      ),
    ));
    await tester.pumpAndSettle();
    // A first-place user appears in both the podium and their own rank card.
    expect(find.text('لاعب ديدا موثق'), findsNWidgets(2));
    expect(find.text('20 نقطة'), findsWidgets);
    expect(find.byType(Scrollable), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late response from logged-out/switching user gets discarded',
      (tester) async {
    final response = Completer<Object?>();
    var stillSignedIn = true;
    await tester.pumpWidget(MaterialApp(
      home: DedaWeeklyLeaderboardSafeScreen(
        loadVerifiedStandings: () => response.future,
        currentAccountStillAuthorized: () => stillSignedIn,
      ),
    ));
    expect(find.text('لاعب ديدا موثق'), findsNothing);
    stillSignedIn = false;
    response.complete(packet());
    await tester.pumpAndSettle();
    expect(find.text('لاعب ديدا موثق'), findsNothing);
    expect(find.textContaining('الترتيب قيد التحقق'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid or spoofed server results never become rankings',
      (tester) async {
    final forged = packet()..['source'] = 'local_client_claim';
    await tester.pumpWidget(MaterialApp(
      home: DedaWeeklyLeaderboardSafeScreen(
        loadVerifiedStandings: () async => forged,
        currentAccountStillAuthorized: () => true,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('لاعب ديدا موثق'), findsNothing);
    expect(find.textContaining('الترتيب قيد التحقق'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('XP notifier refreshes verified current weekly standings',
      (tester) async {
    final signal = ValueNotifier<int>(0);
    addTearDown(signal.dispose);
    var requestCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: DedaWeeklyLeaderboardSafeScreen(
        loadVerifiedStandings: () async {
          requestCount++;
          return packet(points: requestCount * 20);
        },
        currentAccountStillAuthorized: () => true,
        refreshSignal: signal,
      ),
    ));
    await tester.pumpAndSettle();
    expect(requestCount, 1);
    expect(find.text('20 نقطة'), findsWidgets);
    signal.value++;
    await tester.pumpAndSettle();
    expect(requestCount, 2);
    expect(find.text('40 نقطة'), findsWidgets);
    expect(find.byType(Scrollable), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('session guard exceptions fail closed', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: DedaWeeklyLeaderboardSafeScreen(
        loadVerifiedStandings: () async => packet(),
        currentAccountStillAuthorized: () =>
            throw StateError('session expired'),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('لاعب ديدا موثق'), findsNothing);
    expect(find.textContaining('الترتيب قيد التحقق'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
