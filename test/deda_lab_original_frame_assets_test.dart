import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_lab_verified_frame_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('all 16 DEDA original LAB frame artwork assets are actually bundled', () async {
    expect(dedaLabVerifiedFrames.length, 16);
    var free = 0, locked = 0;
    for (final f in dedaLabVerifiedFrames) {
      expect(f.bundled, true, reason: '${f.id} must be real asset, not placeholder');
      final data = await rootBundle.load(f.assetPath);
      expect(data.lengthInBytes, greaterThan(90000),
          reason: '${f.id} original lossless luxury artwork absent');
      expect(f.originalSha256.length, 64);
      if (f.free) {
        free++;
        expect(f.priceDiamonds, 0);
      } else {
        locked++;
        expect(f.priceDiamonds, 1000);
      }
    }
    expect(free, 3);
    expect(locked, 13);
  });
}
