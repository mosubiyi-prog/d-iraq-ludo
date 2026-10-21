import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_stage50_verified_friend_ink_badge.dart';

void main() {
  testWidgets('friend/location active-alias component OFF safely survives resume',
      (tester) async {
    expect(DedaStage50PublicIdStyleBridge.enabled, isFalse);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: DedaStage50VerifiedFriendInkBadge(
        originalId: '@DEDA-AQPYXJ',
        fallback: Text('@DEDA-AQPYXJ'),
      )),
    ));
    expect(find.text('@DEDA-AQPYXJ'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('@DEDA-AQPYXJ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('widget account changes keep original fallback with feature off',
      (tester) async {
    Widget view(String id) => MaterialApp(
      home: Scaffold(body: DedaStage50VerifiedFriendInkBadge(
        originalId: id, fallback: Text(id),
      )),
    );
    await tester.pumpWidget(view('@DEDA-AQPYXJ'));
    expect(find.text('@DEDA-AQPYXJ'), findsOneWidget);
    await tester.pumpWidget(view('@DEDA-BB3344'));
    expect(find.text('@DEDA-BB3344'), findsOneWidget);
    expect(find.text('@DEDA-AQPYXJ'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
