import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/main.dart';
import 'package:d_iraq_ludo/deda_stage75_unread_gift_badge.dart';

void main() {
  testWidgets('original gift tab combines both badge sources and keeps its tap', (tester) async {
    var taps = 0;
    DedaGiftInbox.pendingNotifier.value = 2;
    DedaStage75UnreadGiftBadge.pendingNotifier.value = 1;
    addTearDown(() async {
      await DedaGiftInbox.stop();
      await DedaStage75UnreadGiftBadge.stop();
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Row(children: [
      DedaGiftNavBadge(label: 'هداياي', onTap: () => taps++),
    ]))));
    expect(find.text('3'), findsOneWidget);
    expect(find.byIcon(Icons.card_giftcard_outlined), findsOneWidget);
    await tester.tap(find.text('هداياي'));
    expect(taps, 1);
    DedaStage75UnreadGiftBadge.pendingNotifier.value = 100;
    await tester.pump();
    expect(find.text('99+'), findsOneWidget);
    DedaGiftInbox.accountChanged();
    await tester.pump();
    expect(find.text('99+'), findsNothing);
    expect(DedaGiftInbox.pendingNotifier.value, 0);
    expect(DedaStage75UnreadGiftBadge.pendingNotifier.value, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
