import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_lab_frame_secure_checkout.dart';

void main() {
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
