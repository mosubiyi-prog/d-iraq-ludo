import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_lab_frame_purchase_action.dart';
import 'package:d_iraq_ludo/deda_lab_verified_frame_catalog.dart';
import 'package:d_iraq_ludo/deda_lab_premium_frame_artwork.dart';
import 'package:d_iraq_ludo/deda_lab_frame_secure_checkout.dart';

void main() {
  test('16 exact-frame catalog: 3 permanently free and 13 buy-once at 1000', () {
    expect(dedaLabVerifiedFrames.length, 16);
    expect(dedaLabVerifiedFrames.where((f) => f.free).length, 3);
    expect(dedaLabVerifiedFrames.where((f) => !f.free).length, 13);
    final names = dedaLabVerifiedFrames.map((f) => f.nameAr).toSet();
    expect(names.length, 16);
    for (var style = 6; style <= 18; style++) {
      final frame = DedaLabPremiumFrameStyles.byProfileStyle(style);
      expect(frame, isNotNull);
      expect(frame!.priceDiamonds, 1000);
      expect(DedaLabFrameSecureCheckout.paidFrameIds.contains(frame.id), isTrue);
      expect(DedaLabPremiumFrameStyles.profileStyleOf(frame), style);
    }
  });

  testWidgets('unapproved rollout cannot show a pretend Buy or debit button',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DedaLabFramePurchaseAction(
          originalId: '@DEDA-AQPYXJ',
          frameId: 'FRAME_03',
          onVerifiedOwned: () {},
        ),
      ),
    ));
    expect(find.text('1000 💎'), findsOneWidget);
    expect(find.text('الشراء بعد التحقق'), findsOneWidget);
    expect(find.text('شراء — 1000 💎'), findsNothing);
    expect(find.text('استخدام'), findsNothing);
  });

  test('point01 exactly 13 approved paid frames at 1000 diamonds', () {
    expect(DedaLabFrameSecureCheckout.paidFrameIds.length, 13);
    expect(DedaLabFrameSecureCheckout.priceDiamonds, 1000);
    expect(DedaLabFrameSecureCheckout.paidFrameIds.contains('FRAME_03'), isTrue);
    expect(DedaLabFrameSecureCheckout.paidFrameIds.contains('FRAME_04'), isFalse);
    expect(DedaLabFrameSecureCheckout.paidFrameIds.contains('FRAME_01'), isFalse);
    expect(DedaLabFrameSecureCheckout.paidFrameIds.contains('FRAME_02'), isFalse);
  });
  test('point01 rejects arbitrary IDs, bypass and noncatalog frames', () {
    expect(() => DedaLabFrameSecureCheckout.purchaseId(
      '@DEDA-IRAQI', 'FRAME_03'), throwsArgumentError);
    expect(() => DedaLabFrameSecureCheckout.purchaseId(
      '@DEDA-AQPYXJ', 'FRAME_17'), throwsArgumentError);
    expect(() => DedaLabFrameSecureCheckout.purchaseId(
      '@DEDA-AQPYXJ', 'FRAME_01'), throwsArgumentError);
    expect(DedaLabFrameSecureCheckout.purchaseId(
      '@DEDA-AQPYXJ', 'FRAME_03'), '@DEDA-AQPYXJ_FRAME_03');
  });
  test('point01 real checkout defaults OFF until audited production rules', () {
    expect(DedaLabFrameSecureCheckout.live, isFalse);
  });
}
