import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_100377_my_store_page_staged.dart';
import 'package:d_iraq_ludo/deda_100377_profile_free_inventory.dart';

void main() {
  test('point12 free catalogue mirrors the original three picker sections', () {
    final rows = DedaProfileFreeInventory.forDevice(
      avatarStyle: 2, frameStyle: 4, backgroundStyle: 8,
    );
    List<DedaMyStoreItem> items(DedaMyStoreSection section) =>
        rows.where((r) => r.section == section).toList();
    expect(items(DedaMyStoreSection.avatars).length, 6);
    expect(items(DedaMyStoreSection.frames).length, 6);
    expect(items(DedaMyStoreSection.backgrounds).length, 6);
    expect(DedaProfileFreeInventory.avatarChoices, [0, 1, 2, 3, 4, 5]);
    expect(DedaProfileFreeInventory.frameChoices, [0, 1, 2, 3, 4, 5]);
    expect(DedaProfileFreeInventory.backgroundChoices, [0, 1, 2, 6, 7, 8]);
    for (final row in rows) {
      expect(row.proof, DedaMyStoreProof.basicFree);
      expect(row.receiptKind, isNull);
      expect(row.id.startsWith('moonlit_'), isFalse);
    }
    for (final section in [
      DedaMyStoreSection.avatars,
      DedaMyStoreSection.frames,
      DedaMyStoreSection.backgrounds,
    ]) {
      expect(items(section).where((r) => r.active).length, 1);
    }
  });

  test('legacy selections survive without inventing premium entitlements', () {
    final rows = DedaProfileFreeInventory.forDevice(
      avatarStyle: 7, frameStyle: 12, backgroundStyle: 4,
    );
    final saved = rows.where((r) => r.proof == DedaMyStoreProof.deviceSaved);
    expect(saved.map((r) => r.id), containsAll(['avatar_7', 'background_4']));
    expect(saved.every((r) => r.active), isTrue);
    expect(rows.where((r) => r.section == DedaMyStoreSection.frames).length, 6);
    expect(rows.where((r) => r.section == DedaMyStoreSection.frames &&
        r.active), isEmpty);
    expect(rows.any((r) => r.id == 'frame_12'), isFalse);
    expect(rows.any((r) => r.proof == DedaMyStoreProof.serverVerified), isFalse);
  });

  test('out-of-range local values are never added as owned store products', () {
    final rows = DedaProfileFreeInventory.forDevice(
      avatarStyle: 300, frameStyle: -1, backgroundStyle: 99,
    );
    expect(rows.length, 18);
    expect(rows.any((r) => r.active), isFalse);
    expect(rows.any((r) => r.proof == DedaMyStoreProof.serverVerified), isFalse);
  });
}
