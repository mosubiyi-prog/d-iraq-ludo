import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:d_iraq_ludo/deda_stage67_spark_secure_card_checkout.dart';
import 'package:d_iraq_ludo/deda_stage67_spark_card_action.dart';

void main() {
  test('no secret or locally minted diamonds can activate secure checkout',
      () {
    expect(DedaStage67SparkCardCheckout.live, isFalse);
    expect(DedaStage67SparkCardCheckout.priceDiamonds, 5000);
    expect(DedaStage67SparkCardCheckout.styles,
        {'gold', 'diamond', 'royal', 'pink'});
    expect(
      DedaStage67SparkCardCheckout.receiptId('@DEDA-AX7H9P', 'gold'),
      '@DEDA-AX7H9P_gold',
    );
    expect(
      () => DedaStage67SparkCardCheckout.receiptId(
          '@DEDA-000001', 'red'),
      throwsArgumentError,
    );
    expect(
      () => DedaStage67SparkCardCheckout.receiptId(
          '@DEDA-SALEM', 'gold'),
      throwsArgumentError,
    );
    expect(
      () => DedaStage67SparkCardCheckout.receiptId(
          '9647700001111', 'pink'),
      throwsArgumentError,
    );
  });

  testWidgets('card action cannot appear as a successful buy without live rules',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DedaStage67SparkCardAction(
          originalId: '@DEDA-AX7H9P',
          style: 'gold',
        ),
      ),
    ));
    expect(
      find.byKey(const Key('deda_stage67_secure_checkout_off')),
      findsOneWidget,
    );
    expect(find.text('شراء 5,000'), findsNothing);
    expect(find.text('مملوكة ✓'), findsNothing);
  });
}
