import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_session_recovery_coordinator.dart';
import 'package:d_iraq_ludo/deda_session_rescue_stage3_core.dart';
import 'package:d_iraq_ludo/deda_session_missing_owner_entry_100441.dart';

const key = '9647712345678';
const original = '@DEDA-ABC123';

class MissingPrincipalPort implements DedaRescueStage3Port {
  int verificationAttempts = 0;
  int aliasReads = 0;
  int notifications = 0;
  DedaRescueSnapshot? current = const DedaRescueSnapshot(
      uid: null, epoch: 17, anonymous: false);

  @override
  DedaRescueSnapshot? capture() => current;
  @override
  Future<DedaRescueResult> verifyOwner(String a, String o) async {
    verificationAttempts++;
    return const DedaRescueResult(DedaRescueStatus.ready);
  }
  @override
  Future<String?> readVerifiedOwnerDisplay(String uid, String id) async {
    aliasReads++;
    return '@DEDA-AAAA';
  }
  @override
  void notifyVerifiedOwnerViews() => notifications++;
}

void main() {
  test('missing Firebase principal is signedOut and NO owner proof runs', () async {
    final port = MissingPrincipalPort();
    final controller = DedaRescueStage3Controller(port);
    final result = await controller.rescue(accountKey: key, originalId: original);
    expect(result.status, DedaRescueStatus.signedOut);
    expect(result.ownerReady, isFalse);
    expect(result.uid, isNull);
    expect(result.verifiedDisplayId, isNull);
    expect(port.verificationAttempts, 0);
    expect(port.aliasReads, 0);
    expect(port.notifications, 0);
    expect(controller.updates.value, isNull);
  });

  test('unavailable Firebase snapshot is distinct from signed out', () async {
    final port = MissingPrincipalPort()..current = null;
    final result = await DedaRescueStage3Controller(port)
        .rescue(accountKey: key, originalId: original);
    expect(result.status, DedaRescueStatus.firebaseNotReady);
    expect(port.verificationAttempts, 0);
  });

  test('explicit user confirmation offers only original absent account', () {
    bool offer({
      DedaRescueStatus status = DedaRescueStatus.signedOut,
      bool rescueEnabled = true,
      bool entryEnabled = true,
      bool firebaseReady = true,
      String? uid,
      String a = key,
      String o = original,
    }) => DedaMissingOwnerEntryPolicy.canOffer(
      status: status,
      rescueEnabled: rescueEnabled,
      verifiedExistingEntryEnabled: entryEnabled,
      firebaseReady: firebaseReady,
      liveUid: uid,
      accountKey: a,
      originalId: o,
    );
    expect(offer(), isTrue);
    expect(offer(rescueEnabled: false), isFalse);
    expect(offer(entryEnabled: false), isFalse);
    expect(offer(firebaseReady: false), isFalse);
    expect(offer(uid: 'administrator-uid'), isFalse);
    expect(offer(uid: 'linked-uid'), isFalse);
    expect(offer(status: DedaRescueStatus.permissionDenied), isFalse);
    expect(offer(status: DedaRescueStatus.ownerProofRequired), isFalse);
    expect(offer(status: DedaRescueStatus.temporarilyOffline), isFalse);
    expect(offer(status: DedaRescueStatus.uidChanged), isFalse);
    expect(offer(status: DedaRescueStatus.ready), isFalse);
    expect(offer(a: 'not-phone'), isFalse);
    expect(offer(o: '@DEDA-AAAA'), isFalse);
  });

  test('cancelled or changed selection cannot open owner login', () {
    bool allow({
      bool consent = true, bool unchanged = true,
      String? uid, DedaRescueStatus status = DedaRescueStatus.signedOut,
    }) => DedaMissingOwnerEntryPolicy.mayOpenAfterConsent(
        explicitUserConsent: consent,
        accountUnchanged: unchanged,
        status: status,
        rescueEnabled: true,
        verifiedExistingEntryEnabled: true,
        firebaseReady: true,
        liveUid: uid,
        accountKey: key,
        originalId: original,
    );
    expect(allow(), isTrue);
    expect(allow(consent: false), isFalse);
    expect(allow(unchanged: false), isFalse);
    expect(allow(uid: 'uid-appeared-while-dialog-open'), isFalse);
    expect(allow(status: DedaRescueStatus.permissionDenied), isFalse);
  });
}
