import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/main.dart';
import 'package:d_iraq_ludo/deda_stage75_unread_gift_badge.dart';

void main() {
  testWidgets('diamond pending badge appears, updates and clears on home nav',
      (tester) async {
    DedaGiftInbox.pendingNotifier.value = 0;
    DedaStage75UnreadGiftBadge.pendingNotifier.value = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: const SizedBox.shrink(),
        bottomNavigationBar: Row(
          children: [
            DedaGiftNavBadge(label: 'هداياي', onTap: () {}),
          ],
        ),
      ),
    ));
    expect(find.text('هداياي'), findsOneWidget);
    expect(find.text('2'), findsNothing);
    DedaGiftInbox.pendingNotifier.value = 2;
    await tester.pump();
    expect(find.text('2'), findsOneWidget,
        reason: 'two pending diamond gifts must produce a red nav badge');
    DedaGiftInbox.pendingNotifier.value = 0;
    await tester.pump();
    expect(find.text('2'), findsNothing,
        reason: 'claimed/viewed history must not remain a pending alert');
    await tester.pumpWidget(const SizedBox.shrink());
    DedaGiftInbox.pendingNotifier.value = 0;
    DedaStage75UnreadGiftBadge.pendingNotifier.value = 0;
  });
}
