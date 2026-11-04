import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'deda_step2_linked_owner_flutter_handoff.dart';

const originalUid = 'owner-original-uid';
const account = '9647712345678';
const id = '@DEDA-ABC123';
const install = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

class FakeLoginPort implements DedaLoginHandoffPort {
  DedaLoginIdentity principal = const DedaLoginIdentity(
    null, null, DedaLoginKind.absent, 0);
  final List<String> events = [];
  bool ownerProof = true, deviceGranted = true, serverRead = true;
  bool throwBeforeGrant = false;
  bool laneBusy = false;
  bool signedInWrongUid = false;
  Completer<void>? holdGrant;
  void Function()? onOwnerProof;
  @override
  DedaLoginIdentity current() => principal;
  @override
  Future<T> inExistingOwnerLane<T>(
      Future<T> Function() work, bool Function() current) async {
    if (laneBusy) throw StateError('existing-auth-lane-busy');
    laneBusy = true;
    events.add('lane');
    try {
      if (!current()) throw StateError('intent-expired');
      final result = await work();
      if (!current()) throw StateError('intent-expired');
      return result;
    } finally { laneBusy = false; }
  }
  @override
  Future<DedaLoginIdentity> signInOriginal(String key, String pin) async {
    events.add('auth');
    principal = DedaLoginIdentity(signedInWrongUid ? 'other-uid' : originalUid,
        '$key@deda-login.invalid', DedaLoginKind.linked, principal.epoch + 1);
    return principal;
  }
  @override
  Future<void> proveOriginal(String key, String shareId, String uid) async {
    events.add('owner');
    if (!ownerProof || uid != originalUid || key != account || shareId != id) {
      throw StateError('owner-proof-denied');
    }
    onOwnerProof?.call();
  }
  @override
  Future<String> installId() async {
    events.add('install');
    return install;
  }
  @override
  Future<bool> grantDevice(String key, String originalId, String uid,
      String device) async {
    events.add('grant');
    if (holdGrant != null) await holdGrant!.future;
    if (throwBeforeGrant) throw StateError('appcheck-or-network-failed');
    return deviceGranted;
  }
  @override
  Future<void> writeSession(String key, String uid, String device) async {
    events.add('write');
  }
  @override
  Future<bool> readbackSession(String key, String uid) async {
    events.add('readback');
    return serverRead;
  }
}

Future<String> run(FakeLoginPort fake, {
  bool explicit = true,
  bool replaceAnonymous = false,
  bool Function()? current,
  String pin = '123456',
}) => DedaLoginHandoff(fake, enabled: true).login(
  phone: account, pin: pin, originalId: id,
  explicitUserAction: explicit,
  isCurrentIntent: current ?? () => true,
  explicitReplaceAnonymous: replaceAnonymous,
);

void main() {
  test('default disabled: no SDK or Firestore dispatch', () async {
    final disabled = DedaLoginHandoff(DummyPort());
    expect(dedaLinkedFlutterHandoffEnabled, false);
    await expectLater(disabled.login(phone: account, pin: '123456',
        originalId: id, explicitUserAction: true,
        isCurrentIntent: () => true), throwsStateError);
  });
  test('happy path: existing Auth lane then owner proof, grant, session write, readback', () async {
    final fake = FakeLoginPort();
    final uid = await run(fake);
    expect(uid, originalUid);
    expect(fake.events, ['lane','auth','owner','install','grant','write','readback']);
  });
  test('background or wrong PIN cannot initiate owner sign in', () async {
    final fake = FakeLoginPort();
    await expectLater(run(fake, explicit: false), throwsStateError);
    await expectLater(run(fake, pin:'000'), throwsArgumentError);
    expect(fake.events, isEmpty);
  });
  test('existing authenticated principal cannot be silently replaced', () async {
    final fake = FakeLoginPort()
      ..principal = const DedaLoginIdentity('other-uid','x@example.com',
          DedaLoginKind.linked, 4);
    await expectLater(run(fake), throwsStateError);
    expect(fake.principal.uid, 'other-uid');
    expect(fake.events, isEmpty);
  });
  test('existing anonymous principal requires explicit replacement consent', () async {
    final fake = FakeLoginPort()
      ..principal = const DedaLoginIdentity('old-anon',null,
          DedaLoginKind.anonymous, 1);
    await expectLater(run(fake), throwsStateError);
    expect(fake.events, isEmpty);
    expect(await run(fake, replaceAnonymous: true), originalUid);
  });
  test('server original-owner denial fails closed before device grant/write', () async {
    final fake = FakeLoginPort()..ownerProof = false;
    await expectLater(run(fake), throwsStateError);
    expect(fake.events, ['lane','auth','owner']);
  });
  test('missing or denied AppCheck grant never writes session', () async {
    final fake = FakeLoginPort()..deviceGranted = false;
    await expectLater(run(fake), throwsStateError);
    expect(fake.events, ['lane','auth','owner','install','grant']);
  });
  test('network failure before grant never writes session', () async {
    final fake = FakeLoginPort()..throwBeforeGrant = true;
    await expectLater(run(fake), throwsStateError);
    expect(fake.events, isNot(contains('write')));
  });
  test('stale login intent after owner proof prevents next write', () async {
    final fake = FakeLoginPort();
    var current = true;
    fake.onOwnerProof = () => current = false;
    await expectLater(run(fake,current:()=>current),throwsStateError);
    expect(fake.events, ['lane','auth','owner']);
  });
  test('A->B->A same UID with different epoch is rejected', () async {
    final fake = FakeLoginPort();
    fake.onOwnerProof = () {
      final p = fake.principal;
      fake.principal = DedaLoginIdentity(p.uid, p.email, p.kind, p.epoch + 2);
    };
    await expectLater(run(fake),throwsStateError);
    expect(fake.events, isNot(contains('write')));
  });
  test('session server readback required; local write acknowledgement insufficient', () async {
    final fake = FakeLoginPort()..serverRead=false;
    await expectLater(run(fake),throwsStateError);
    expect(fake.events.last,'readback');
  });
  test('existing lane allows only one in-flight login, no auto retry', () async {
    final fake = FakeLoginPort()..holdGrant = Completer<void>();
    final first = run(fake);
    await Future<void>.delayed(const Duration(milliseconds: 3));
    await expectLater(run(fake), throwsStateError);
    fake.holdGrant!.complete();
    expect(await first, originalUid);
    expect(fake.events.where((x)=>x=='auth').length, 1);
  });
  test('no signOut invoked on any failure or normal successful login', () async {
    final fake=FakeLoginPort()..ownerProof=false;
    await expectLater(run(fake), throwsStateError);
    expect(fake.events.contains('signout'), false);
  });
}
class DummyPort extends FakeLoginPort {}
