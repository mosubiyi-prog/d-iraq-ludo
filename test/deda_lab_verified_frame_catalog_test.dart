import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_lab_verified_frame_catalog.dart';

void main() {
  test('16 unique original frames with exactly 3 free royal assets', () {
    expect(dedaLabVerifiedFrames.length, 16);
    expect(dedaLabVerifiedFrames.map((f) => f.id).toSet().length, 16);
    final free = dedaLabVerifiedFrames.where((f) => f.free).toList();
    expect(free.map((f) => f.id), ['FRAME_01', 'FRAME_02', 'FRAME_04']);
    expect(free.every((f) => f.bundled), true);
    expect(free.every((f) => f.priceDiamonds == 0), true);
    final locked = dedaLabVerifiedFrames.where((f) => !f.free).toList();
    expect(locked.length, 13);
    expect(locked.every((f) => f.priceDiamonds == 1000), true);
    expect(locked.every((f) => !f.bundled), true,
        reason:'Only 3 royal images are in original app bundle so far');
    expect(dedaLabInternalAvatarDimension, 111);
    expect(dedaLabPurchasedFramePriceDiamonds, 1000);
  });
  test('per-artwork portrait aperture remains proportional and centered', () {
    for (final frame in dedaLabVerifiedFrames) {
      expect(frame.portraitLeft, inInclusiveRange(0.0, 0.5));
      expect(frame.portraitTop, inInclusiveRange(0.0, 0.5));
      expect(frame.portraitWidth, inExclusiveRange(0.3, 0.8));
      expect(frame.portraitHeight, inExclusiveRange(0.3, 0.8));
      expect(frame.portraitLeft + frame.portraitWidth,
          lessThanOrEqualTo(1.0));
      expect(frame.portraitTop + frame.portraitHeight,
          lessThanOrEqualTo(1.0));
      expect(frame.originalSha256.length, 64);
    }
  });
  test('preview never equals verified ownership of a paid asset', () {
    final paid=dedaLabVerifiedFrames.firstWhere((x)=>x.id=='FRAME_03');
    expect(paid.free, false);
    expect(paid.canPreviewNatively, false);
    expect(paid.needsTrustedCheckout, true);
    expect(dedaLabIsGiftedOrOwnedFrame(paid, const <String>{}), false);
    expect(dedaLabIsGiftedOrOwnedFrame(paid, const {'FRAME_03'}), true);
    expect(dedaLabIsGiftedOrOwnedFrame(dedaLabVerifiedFrames.first,
        const <String>{}), true);
  });
}
