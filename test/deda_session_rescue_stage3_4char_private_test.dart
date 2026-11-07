import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_session_recovery_coordinator.dart';
import 'package:d_iraq_ludo/deda_session_rescue_stage3_bridge.dart';
import 'package:d_iraq_ludo/deda_qa32_spark_public_identifier_directory.dart';
import 'package:d_iraq_ludo/deda_stage51_verified_friend_alias_search.dart';
import 'package:d_iraq_ludo/deda_social_service.dart';
import 'package:d_iraq_ludo/deda_verified_active_id_store.dart';

const original = '@DEDA-ABC123';
const premiumFour = '@DEDA-AAAA';
const account = '9647712345678';
const owner = 'old-immutable-uid';

class FakeStage3 implements DedaRescueStage3Port {
  DedaRescueSnapshot current = const DedaRescueSnapshot(
    uid: owner, epoch: 1, anonymous: false,
  );
  int verifyCalls = 0;
  int activeReads = 0;
  int notifications = 0;
  String? display = premiumFour;
  Future<DedaRescueResult> Function()? verifyBehavior;
  Future<String?> Function()? readBehavior;

  @override
  DedaRescueSnapshot? capture() => current;

  @override
  Future<DedaRescueResult> verifyOwner(String key, String id) {
    expect(key, account);
    expect(id, original);
    verifyCalls++;
    return verifyBehavior?.call() ??
        Future.value(const DedaRescueResult(DedaRescueStatus.ready));
  }

  @override
  Future<String?> readVerifiedOwnerDisplay(String uid, String id) {
    expect(uid, owner);
    expect(id, original);
    activeReads++;
    return readBehavior?.call() ?? Future.value(display);
  }

  @override
  void notifyVerifiedOwnerViews() => notifications++;
}

void main() {
  test('4-character premium ID is a valid display and original stays six', () {
    const record = DedaVerifiedActiveId(
      uid: owner, originalId: original,
      displayId: premiumFour, fixedColor: 'gold',
    );
    expect(record.wellFormed, isTrue);
    expect(DedaVerifiedActiveId.fromJson(record.toJson())?.displayId,
        premiumFour);
    expect(DedaSocialService.looksLikePersonalId(premiumFour), isFalse,
        reason: 'Never use premium alias as a canonical friend/owner key');
  });

  test('4-letter public alias requires exact current original projection', () {
    final proof = DedaQa32SparkPublicIdentifierDirectory
        .styleFromProjection(original, <String, dynamic>{
      'originalId': original,
      'activeId': premiumFour,
      'baseColor': 'gold',
      'updatedAt': 123,
    });
    expect(proof?['displayId'], premiumFour);
    expect(DedaQa32SparkPublicIdentifierDirectory.styleFromProjection(
        original, <String, dynamic>{
          'originalId': '@DEDA-WRONG1',
          'activeId': premiumFour,
          'baseColor': 'gold',
          'updatedAt': 123,
        }), isNull);
  });

  test('4-character friend alias maps ONLY to immutable original route', () {
    final proof = DedaStage51FriendAliasProof.parse(
      <String, dynamic>{
        'requestedId': premiumFour,
        'originalId': original,
        'serverConfirmed': true,
      },
      premiumFour,
    );
    expect(proof?.originalId, original);
    expect(
      () => DedaStage51FriendAliasProof.parse(<String, dynamic>{
        'requestedId': premiumFour,
        'originalId': '@DEDA-AA',
        'serverConfirmed': true,
      }, premiumFour),
      throwsStateError,
    );
  });

  test('legacy missing sharePersonalId must still match ALL server proof', () {
    final dir = <String, dynamic>{
      'accountKey': account, 'active': true, 'createdUid': owner,
    };
    final session = <String, dynamic>{'uid': owner, 'accountKey': account};
    final profile = <String, dynamic>{'accountKey': account};
    final route = <String, dynamic>{
      'publicId': original, 'kind': 'personal',
      'ownerUid': owner, 'active': true,
    };
    bool check({
      String uid = owner, String id = original,
      Map<String, dynamic>? d,
      Map<String, dynamic>? s,
      Map<String, dynamic>? p,
      Map<String, dynamic>? r,
    }) => DedaRescueLegacyCanonicalProof.authentic(
      uid: uid, accountKey: account,
      expectedOriginalId: id,
      directory: d ?? dir,
      session: s ?? session,
      profile: p ?? profile,
      route: r ?? route,
    );
    expect(check(), isTrue);
    expect(check(id: premiumFour), isFalse);
    expect(check(uid: 'different-uid'), isFalse);
    expect(check(d: {...dir, 'createdUid': 'other'}), isFalse);
    expect(check(s: {...session, 'uid': 'other'}), isFalse);
    expect(check(p: {...profile, 'sharePersonalId': '@DEDA-WRONG1'}), isFalse);
    expect(check(r: {...route, 'ownerUid': 'other'}), isFalse);
    expect(check(r: {...route, 'publicId': premiumFour}), isFalse);
    expect(check(r: {...route, 'active': false}), isFalse);
  });

  test('ready triggers exactly one UI notification with premium 4 letters',
      () async {
    final fake = FakeStage3();
    final control = DedaRescueStage3Controller(fake);
    final result = await control.rescue(
        accountKey: account, originalId: original);
    expect(result.status, DedaRescueStatus.ready);
    expect(result.verifiedDisplayId, premiumFour);
    expect(result.mayRecheckAdminGateway, isTrue);
    expect(result.mayRecheckGoogleCard, isTrue);
    expect(control.updates.value?.verifiedDisplayId, premiumFour);
    expect(fake.verifyCalls, 1);
    expect(fake.activeReads, 1);
    expect(fake.notifications, 1);
    control.updates.dispose();
  });

  test('session denied does NOT refresh ID or notify administration', () async {
    final fake = FakeStage3();
    fake.verifyBehavior = () async =>
        const DedaRescueResult(DedaRescueStatus.permissionDenied);
    final result = await DedaRescueStage3Controller(fake).rescue(
        accountKey: account, originalId: original);
    expect(result.status, DedaRescueStatus.permissionDenied);
    expect(result.verifiedDisplayId, isNull);
    expect(result.mayRecheckAdminGateway, isFalse);
    expect(fake.activeReads, 0);
    expect(fake.notifications, 0);
  });

  test('offline session never promotes a stored old ID as verified', () async {
    final fake = FakeStage3();
    fake.verifyBehavior = () async =>
        const DedaRescueResult(DedaRescueStatus.temporarilyOffline);
    final result = await DedaRescueStage3Controller(fake).rescue(
        accountKey: account, originalId: original);
    expect(result.status, DedaRescueStatus.temporarilyOffline);
    expect(result.verifiedDisplayId, isNull);
    expect(fake.notifications, 0);
  });

  test('same UID / session / account shares one pending readiness check',
      () async {
    final fake = FakeStage3();
    final completer = Completer<DedaRescueResult>();
    fake.verifyBehavior = () => completer.future;
    final c = DedaRescueStage3Controller(fake);
    final first = c.rescue(accountKey: account, originalId: original);
    final second = c.rescue(accountKey: account, originalId: original);
    expect(identical(first, second), isTrue);
    completer.complete(const DedaRescueResult(DedaRescueStatus.ready));
    expect((await first).verifiedDisplayId, premiumFour);
    expect(fake.verifyCalls, 1);
    expect(fake.notifications, 1);
  });

  test('changed UID during owner proof discards a late ready', () async {
    final fake = FakeStage3();
    final completer = Completer<DedaRescueResult>();
    fake.verifyBehavior = () => completer.future;
    final c = DedaRescueStage3Controller(fake);
    final result = c.rescue(accountKey: account, originalId: original);
    fake.current = const DedaRescueSnapshot(
        uid: 'different-uid', epoch: 2, anonymous: false);
    completer.complete(const DedaRescueResult(DedaRescueStatus.ready));
    expect((await result).status, DedaRescueStatus.uidChanged);
    expect(fake.activeReads, 0);
    expect(fake.notifications, 0);
    expect(c.updates.value, isNull);
  });

  test('changed epoch DURING alias read never publishes stale ID', () async {
    final fake = FakeStage3();
    final completer = Completer<String?>();
    fake.readBehavior = () => completer.future;
    final c = DedaRescueStage3Controller(fake);
    final result = c.rescue(accountKey: account, originalId: original);
    await Future<void>.delayed(Duration.zero);
    fake.current = const DedaRescueSnapshot(
        uid: owner, epoch: 3, anonymous: false);
    completer.complete(premiumFour);
    expect((await result).status, DedaRescueStatus.uidChanged);
    expect(fake.notifications, 0);
    expect(c.updates.value, isNull);
  });

  test('failed active alias source stays UNKNOWN without falsifying owner', () async {
    final fake = FakeStage3();
    fake.readBehavior = () async => throw StateError('no verified alias');
    final result = await DedaRescueStage3Controller(fake).rescue(
        accountKey: account, originalId: original);
    expect(result.status, DedaRescueStatus.ready);
    expect(result.verifiedDisplayId, isNull);
    expect(fake.notifications, 1);
  });

  test('unrelated or malformed alias never becomes displayed proof', () async {
    final fake = FakeStage3()..display = '@DEDA-X';
    final result = await DedaRescueStage3Controller(fake).rescue(
        accountKey: account, originalId: original);
    expect(result.verifiedDisplayId, isNull);
    expect(fake.notifications, 1);
  });

  test('premium input cannot replace the required immutable original', () async {
    final fake = FakeStage3();
    final result = await DedaRescueStage3Controller(fake).rescue(
        accountKey: account, originalId: premiumFour);
    expect(result.ownerReady, isFalse);
    expect(fake.verifyCalls, 0);
  });
}
