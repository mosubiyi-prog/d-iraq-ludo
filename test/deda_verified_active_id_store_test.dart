import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/deda_verified_active_id_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('canonical to premium and back changes the ONE visible value', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const uid = 'stage100382-owner-a';
    const original = '@DEDA-AQPYXJ';
    const premium = '@DEDA-IRAQI';

    expect(DedaVerifiedActiveIdStore.read(uid, original), isNull);
    DedaVerifiedActiveIdStore.confirmed(
      uid: uid, originalId: original, displayId: original, fixedColor: null,
    );
    expect(DedaVerifiedActiveIdStore.read(uid, original)!.displayId, original);

    DedaVerifiedActiveIdStore.confirmed(
      uid: uid, originalId: original, displayId: premium, fixedColor: 'gold',
    );
    expect(DedaVerifiedActiveIdStore.read(uid, original)!.displayId, premium);
    expect(DedaVerifiedActiveIdStore.read(uid, original)!.fixedColor, 'gold');

    DedaVerifiedActiveIdStore.confirmed(
      uid: uid, originalId: original, displayId: original, fixedColor: null,
    );
    expect(DedaVerifiedActiveIdStore.read(uid, original)!.displayId, original);
    expect(DedaVerifiedActiveIdStore.read('other-user', original), isNull);
  });

  test('malformed alias and mismatched grant colors cannot be cached', () {
    expect(
      () => DedaVerifiedActiveIdStore.confirmed(
        uid: 'stage100382-owner-b',
        originalId: '@DEDA-AQPYXJ',
        displayId: '@DEDA-NOT-VALID',
        fixedColor: 'gold',
      ),
      throwsStateError,
    );
    expect(
      () => DedaVerifiedActiveIdStore.confirmed(
        uid: 'stage100382-owner-b',
        originalId: '@DEDA-AQPYXJ',
        displayId: '@DEDA-IRAQI',
        fixedColor: null,
      ),
      throwsStateError,
    );
  });

  test('restoration never reads another owner UID', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await DedaVerifiedActiveIdStore.restore(
      'stage100382-owner-c', '@DEDA-D62UEB');
    expect(
      DedaVerifiedActiveIdStore.read(
        'stage100382-owner-d', '@DEDA-D62UEB'),
      isNull,
    );
  });
}
