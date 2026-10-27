import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/deda_verified_active_id_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String prefsKey(String uid, String original) =>
      'deda_verified_active_display_v1_' +
      base64Url.encode(utf8.encode('$uid|$original'));
  Map<String, String?> record(String uid, String original, String display) =>
      <String, String?>{
        'uid': uid,
        'originalId': original,
        'displayId': display,
        'fixedColor': 'gold',
      };

  test('cold start preloads same-UID server-confirmed premium ID only',
      () async {
    const uid = 'stage14-a';
    const otherUid = 'stage14-b';
    const original = '@DEDA-D62UEB';
    const premium = '@DEDA-IRAQI';
    SharedPreferences.setMockInitialValues({
      prefsKey(uid, original): jsonEncode(record(uid, original, premium)),
      prefsKey(otherUid, original):
          jsonEncode(record(otherUid, original, '@DEDA-AAAA')),
    });
    expect(DedaVerifiedActiveIdStore.read(uid, original), isNull);
    await DedaVerifiedActiveIdStore.preloadForUid(uid);
    expect(DedaVerifiedActiveIdStore.read(uid, original)?.displayId, premium);
    expect(DedaVerifiedActiveIdStore.read(otherUid, original), isNull);
  });

  test('forged prefs key for another original is ignored', () async {
    const uid = 'stage14-c';
    const original = '@DEDA-CCABCD';
    SharedPreferences.setMockInitialValues({
      prefsKey(uid, '@DEDA-DDABCD'):
          jsonEncode(record(uid, original, '@DEDA-IRAQI')),
      prefsKey(uid, original): '{broken json',
    });
    await DedaVerifiedActiveIdStore.preloadForUid(uid);
    expect(DedaVerifiedActiveIdStore.read(uid, original), isNull);
  });

  test('other authenticated UID never receives account alias',
      () async {
    const owner = 'stage14-d';
    const other = 'stage14-e';
    const original = '@DEDA-C0FFEE';
    SharedPreferences.setMockInitialValues({
      prefsKey(owner, original):
          jsonEncode(record(owner, original, '@DEDA-SALEM')),
    });
    await DedaVerifiedActiveIdStore.preloadForUid(other);
    expect(DedaVerifiedActiveIdStore.read(other, original), isNull);
    expect(DedaVerifiedActiveIdStore.read(owner, original), isNull);
  });

  test('older cached value cannot overwrite newer verified Use selection',
      () async {
    const uid = 'stage14-f';
    const original = '@DEDA-AQPYXJ';
    SharedPreferences.setMockInitialValues({
      prefsKey(uid, original):
          jsonEncode(record(uid, original, '@DEDA-OLD1')),
    });
    DedaVerifiedActiveIdStore.confirmed(
      uid: uid,
      originalId: original,
      displayId: '@DEDA-NEW1',
      fixedColor: 'gold',
    );
    await DedaVerifiedActiveIdStore.preloadForUid(uid);
    expect(DedaVerifiedActiveIdStore.read(uid, original)?.displayId,
        '@DEDA-NEW1');
  });
}
