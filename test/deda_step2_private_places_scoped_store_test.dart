import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_step2_private_places_scoped_store.dart';

const account = '07712345678';
const uid = 'original_uid_1';
const otherAccount = '07712345679';
const otherUid = 'other_uid_2';

Map<String, dynamic> place([String id = 'place_1']) => {
  'id': id, 'name': 'Home', 'note': 'Private',
  'latitude': 35.463, 'longitude': 44.39,
};

class Local implements DedaStep2PrivatePlacesLocal {
  final rows = <String, String>{};
  final reads = <String>[];
  final writes = <String>[];
  bool succeed = true;
  void Function()? beforeWrite;
  @override
  Future<String?> read(String key) async {
    reads.add(key);
    return rows[key];
  }
  @override
  Future<bool> write(String key, String value) async {
    beforeWrite?.call();
    writes.add(key);
    if (!succeed) return false;
    rows[key] = value;
    return true;
  }
}

class Harness {
  final local = Local();
  String loggedUid = uid;
  bool signedIn = true;
  bool active = true;
  bool pilot = true;
  late final lane = DedaStep2PrivatePlacesScope(
    local: local, currentUid: () => loggedUid,
    verifyOriginalOwner: (candidate, a) async =>
        signedIn && candidate == loggedUid &&
        (a == account && candidate == uid ||
         a == otherAccount && candidate == otherUid),
    enabled: pilot,
  );
  Future<List<Map<String, dynamic>>> read([
      String a = account, String u = uid]) =>
      lane.readScoped(accountKey: a, originalUid: u,
          isCurrent: () => active);
  Future<void> save(List<Map<String, dynamic>> places, [
      String a = account, String u = uid]) =>
      lane.saveScoped(accountKey: a, originalUid: u,
          places: places, isCurrent: () => active);
}

Future<void> blocked(Future<dynamic> future, String reason) async {
  await expectLater(future, throwsA(isA<DedaStep2PrivatePlacesHold>()
      .having((e) => e.reason, 'reason', reason)));
}

void main() {
  test('source pilot is disabled by default in ordinary builds', () {
    expect(dedaStep2PrivatePlacesScopedPilot, false);
  });

  test('legacy unscoped key is not read or attributed to the signed-in owner', () async {
    final h = Harness();
    h.local.rows[DedaStep2PrivatePlacesScope.legacyGlobalKey] =
        jsonEncode([place('old')]);
    await blocked(h.read(), 'private-place-scope-not-captured-unknown');
    expect(h.local.reads, isNot(contains(
        DedaStep2PrivatePlacesScope.legacyGlobalKey)));
    expect(h.local.writes, isEmpty);
    expect(h.local.rows[DedaStep2PrivatePlacesScope.legacyGlobalKey],
        contains('old'));
  });

  test('verified original UID can read newly saved account-scoped places only', () async {
    final h = Harness();
    await h.save([place()]);
    final result = await h.read();
    expect(result.single['id'], 'place_1');
    expect(h.local.rows.keys, contains(
        DedaStep2PrivatePlacesScope.key(account, uid)));
    expect(h.local.rows.keys, isNot(contains(
        DedaStep2PrivatePlacesScope.legacyGlobalKey)));
  });

  test('two verified accounts on same handset use separate private keys', () async {
    final h = Harness();
    await h.save([place('a')]);
    h.loggedUid = otherUid;
    await h.save([place('b')], otherAccount, otherUid);
    expect((await h.read(otherAccount, otherUid)).single['id'], 'b');
    h.loggedUid = uid;
    expect((await h.read()).single['id'], 'a');
    expect(h.local.rows.length, 2);
  });

  test('unverified, disabled and changed sessions never read or write', () async {
    final h = Harness();
    h.signedIn = false;
    await blocked(h.save([place()]), 'private-place-owner-unverified');
    expect(h.local.reads, isEmpty);
    h.signedIn = true;
    h.loggedUid = otherUid;
    await blocked(h.read(), 'private-place-owner-session-lost');
    h.loggedUid = uid;
    h.active = false;
    await blocked(h.save([place()]), 'private-place-owner-session-lost');
    expect(h.local.writes, isEmpty);
  });

  test('scope requires valid account and original UID, never alias', () async {
    final h = Harness();
    await blocked(h.lane.readScoped(
      accountKey: '../admin', originalUid: uid, isCurrent: () => true),
      'private-place-account-scope-invalid');
    await blocked(h.lane.readScoped(
      accountKey: account, originalUid: 'other/uid',
      isCurrent: () => true), 'private-place-account-scope-invalid');
  });

  test('copy of another account stamped document cannot be accepted', () async {
    final h = Harness();
    h.local.rows[DedaStep2PrivatePlacesScope.key(account, uid)] =
        jsonEncode({
          'format': 1, 'accountKey': otherAccount,
          'originalUid': otherUid, 'places': [place()],
        });
    await blocked(h.read(), 'private-place-scope-conflict');
    await blocked(h.save([place('new')]), 'private-place-scope-conflict');
    expect(h.local.writes, isEmpty);
  });

  test('corrupted or privileged payload cannot silently be repaired', () async {
    for (final raw in ['{invalid', jsonEncode({
      'format': 1, 'accountKey': account,
      'originalUid': uid, 'places': [ {...place(), 'adminRole': true} ],
    })]) {
      final h = Harness();
      final key = DedaStep2PrivatePlacesScope.key(account, uid);
      h.local.rows[key] = raw;
      await expectLater(h.read(), throwsA(isA<DedaStep2PrivatePlacesHold>()));
      expect(h.local.rows[key], raw);
    }
  });

  test('bad coordinates, duplicate place IDs and forged attributes are rejected', () async {
    for (final entries in [
      [{...place(), 'latitude': 95.0}],
      [{...place(), 'longitude': 200.0}],
      [place(), place()],
      [{...place(), 'diamonds': 123}],
      [{...place(), 'id': ''}],
    ]) {
      final h = Harness();
      await expectLater(h.save(entries),
          throwsA(isA<DedaStep2PrivatePlacesHold>()));
      expect(h.local.writes, isEmpty);
    }
  });

  test('changing Firebase UID while writing only targets old scoped key and fails', () async {
    final h = Harness();
    h.local.beforeWrite = () => h.loggedUid = otherUid;
    await blocked(h.save([place()]), 'private-place-owner-session-lost');
    expect(h.local.writes.single,
        DedaStep2PrivatePlacesScope.key(account, uid));
    expect(h.local.rows.keys, isNot(contains(
        DedaStep2PrivatePlacesScope.key(otherAccount, otherUid))));
  });

  test('failed local write does not pretend to have a recovered place', () async {
    final h = Harness();
    h.local.succeed = false;
    await blocked(h.save([place()]), 'private-place-local-write-failed');
    expect(h.local.rows, isEmpty);
  });

  test('future edits stay within the same proven UID and never change legacy data', () async {
    final h = Harness();
    h.local.rows[DedaStep2PrivatePlacesScope.legacyGlobalKey] =
        jsonEncode([place('old-other-unknown')]);
    await h.save([place('new')]);
    await h.save([place('edited')]);
    expect((await h.read()).single['id'], 'edited');
    expect(h.local.rows[DedaStep2PrivatePlacesScope.legacyGlobalKey],
        contains('old-other-unknown'));
    expect(h.local.writes, hasLength(2));
  });

  test('empty scoped inventory needs explicit verified save, not inferred from absence', () async {
    final h = Harness();
    await blocked(h.read(), 'private-place-scope-not-captured-unknown');
    await h.save([]);
    expect(await h.read(), isEmpty);
    expect(h.local.rows, hasLength(1));
  });
}
