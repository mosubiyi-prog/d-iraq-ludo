import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'deda_session_transition_gate.dart';

/// An EXPLICITLY emulator-only second-phone ACCOUNT POINTER handshake.
///
/// This does NOT recover balance or restore purchasable entitlements. The
/// callable is intentionally absent from production Functions. Never call
/// the public Firebase deployment for this private work-in-progress.
const dedaPrivateSecondPhoneLinkEmulatorPilot = bool.fromEnvironment(
  'DEDA_PRIVATE_SECOND_PHONE_LINK_EMULATOR_PILOT', defaultValue: false);

const _qaFunctionsHost = String.fromEnvironment(
  'DEDA_PRIVATE_SECOND_PHONE_FUNCTIONS_EMULATOR_HOST',
  defaultValue: '');
const _qaAuthEmulator = bool.fromEnvironment(
  'DEDA_PRIVATE_SECOND_PHONE_AUTH_EMULATOR', defaultValue: false);
const _qaFirestoreEmulator = bool.fromEnvironment(
  'DEDA_PRIVATE_SECOND_PHONE_FIRESTORE_EMULATOR', defaultValue: false);

abstract class DedaSecondPhoneLinkTransport {
  String? get currentUid;
  bool get isAnonymous;
  bool get emulatorConfigured;
  Future<Map<String, dynamic>> linkWithoutClientAccountDetails();
}

class DedaFirebaseSecondPhoneLinkTransport
    implements DedaSecondPhoneLinkTransport {
  DedaFirebaseSecondPhoneLinkTransport._(this.auth, this.functions);
  final FirebaseAuth auth;
  final FirebaseFunctions functions;

  /// No production fallback. Never auto-configure auth or Firestore here.
  /// The private QA harness must explicitly configure all three emulators.
  static DedaFirebaseSecondPhoneLinkTransport? forPrivateQa() {
    if (!dedaPrivateSecondPhoneLinkEmulatorPilot ||
        !_qaAuthEmulator || !_qaFirestoreEmulator ||
        !(_qaFunctionsHost == '10.0.2.2' ||
          _qaFunctionsHost == '127.0.0.1' ||
          _qaFunctionsHost == 'localhost')) return null;
    final functions = FirebaseFunctions.instance;
    functions.useFunctionsEmulator(_qaFunctionsHost, 5001);
    return DedaFirebaseSecondPhoneLinkTransport._(
        FirebaseAuth.instance, functions);
  }

  @override
  String? get currentUid => auth.currentUser?.uid;
  @override
  bool get isAnonymous => auth.currentUser?.isAnonymous == true;
  @override
  bool get emulatorConfigured => true;

  @override
  Future<Map<String, dynamic>> linkWithoutClientAccountDetails() async {
    final result = await functions
        .httpsCallable('dedaPrivateSecondPhoneLinkEmulatorOnly')
        .call(<String, dynamic>{});
    final data = result.data;
    if (data is! Map) throw const FormatException('invalid-private-link-reply');
    return data.map((key, value) =>
        MapEntry(key.toString(), value));
  }
}

enum DedaSecondPhoneLinkStatus {
  linkedAwaitingSettlement,
  alreadyLinkedAwaitingSettlement,
}

/// A verified server projection, never a local spendable wallet, rank award,
/// purchase receipt or authority to overwrite DEDA's original preferences.
class DedaVerifiedReadonlyProgress {
  const DedaVerifiedReadonlyProgress({
    required this.version, required this.points, required this.coins,
    required this.xp, required this.earnedDiamonds,
  });
  final int version, points, coins, xp, earnedDiamonds;
  static DedaVerifiedReadonlyProgress parse(Object? source) {
    if (source is! Map || source.length != 8 ||
        source['format'] != 1 ||
        source['spendable'] != false ||
        source['entitlementsVerified'] != false) {
      throw const FormatException('unsafe-verified-progress');
    }
    int requireAmount(String key, {bool positive = false}) {
      final value = source[key];
      if (value is! int || value < (positive ? 1 : 0) ||
          value > 9007199254740991) {
        throw const FormatException('unsafe-verified-progress-amount');
      }
      return value;
    }
    return DedaVerifiedReadonlyProgress(
      version: requireAmount('version', positive: true),
      points: requireAmount('points'),
      coins: requireAmount('coins'),
      xp: requireAmount('xp'),
      earnedDiamonds: requireAmount('earnedDiamonds'),
    );
  }
}

class DedaVerifiedReadonlyEntitlements {
  const DedaVerifiedReadonlyEntitlements({
    required this.ownedFrames,required this.ownedCards,
    required this.ownedPremiumIds,required this.activePremiumId,
    required this.premiumLedgerStatus,required this.unreviewedNativeFrames,
    required this.pendingNativeFrames,
  });
  final List<String> ownedFrames,ownedCards,ownedPremiumIds;
  final String? activePremiumId;
  final String premiumLedgerStatus;
  final List<String> unreviewedNativeFrames,pendingNativeFrames;

  static const frames=<String>{
    'FRAME_03','FRAME_05','FRAME_06','FRAME_07','FRAME_08',
    'FRAME_09','FRAME_10','FRAME_11','FRAME_12','FRAME_13',
    'FRAME_14','FRAME_15','FRAME_16',
  };
  static const cards=<String>{'gold','diamond','royal','pink'};
  static final premiumId=RegExp(r'^@DEDA-[A-Z0-9]{4,12}
  const DedaSecondPhoneVerifiedLink(this.status, this.progress, this.entitlements);
  final DedaSecondPhoneLinkStatus status;
  final DedaVerifiedReadonlyProgress progress;
  final DedaVerifiedReadonlyEntitlements entitlements;
}

class DedaSecondPhoneLinkClient {
  const DedaSecondPhoneLinkClient(this.transport);
  final DedaSecondPhoneLinkTransport transport;

  /// No account, original UID, PIN, installId, balances or league XP is
  /// transmitted. Firebase Auth adds the authenticated UID automatically.
  Future<DedaSecondPhoneLinkStatus> link({
    required bool Function() isCurrent,
  }) async => (await linkAndReadVerifiedProgress(isCurrent: isCurrent)).status;

  Future<DedaSecondPhoneVerifiedLink> linkAndReadVerifiedProgress({
    required bool Function() isCurrent,
  }) async {
    if (!transport.emulatorConfigured) {
      throw StateError('private-second-phone-emulator-required');
    }
    void check(String uid) {
      if (!isCurrent() ||
          !transport.isAnonymous ||
          transport.currentUid != uid) {
        throw const DedaStaleSessionTransition();
      }
    }
    final uid = transport.currentUid;
    if (uid == null || uid.isEmpty || !transport.isAnonymous) {
      throw const DedaStaleSessionTransition();
    }
    check(uid);
    final reply = await transport.linkWithoutClientAccountDetails();
    check(uid);
    if (reply.length != 12 ||
        reply['status'] != 'ACCOUNT_LINKED_READONLY_EMULATOR_ONLY' ||
        reply['emulatorOnly'] != true ||
        reply['replayed'] is! bool ||
        reply['canRestoreFinancialBalances'] != false ||
        reply['canCreditXp'] != false ||
        reply['canCreditDiamonds'] != false ||
        reply['canRestoreFrames'] != false ||
        reply['canRestorePremiumId'] != false ||
        reply['canIssueLeagueGift'] != false ||
        reply['productionReady'] != false) {
      throw const FormatException('unsafe-private-link-reply');
    }
    final progress = DedaVerifiedReadonlyProgress.parse(
        reply['verifiedProgress']);
    final entitlements = DedaVerifiedReadonlyEntitlements.parse(reply['verifiedEntitlements']);
    check(uid);
    return DedaSecondPhoneVerifiedLink(
      reply['replayed'] == true
          ? DedaSecondPhoneLinkStatus.alreadyLinkedAwaitingSettlement
          : DedaSecondPhoneLinkStatus.linkedAwaitingSettlement,
      progress,
      entitlements,
    );
  }
}
);

  static DedaVerifiedReadonlyEntitlements parse(Object? raw) {
    if(raw is! Map||raw.length!=12||raw['format']!=1||
        raw['readOnly']!=true||raw['spendable']!=false||
        raw['grantAuthority']!=false||raw['fullySettled']!=false||
        !{'registry-confirmed','missing-needs-review'}
          .contains(raw['premiumLedgerStatus'])) {
      throw const FormatException('unsafe-entitlement-payload');
    }
    List<String> list(String key,bool Function(String) accept,int max) {
      final value=raw[key];
      if(value is! List||value.length>max||
          value.any((v)=>v is! String||!accept(v))||
          value.toSet().length!=value.length) {
        throw const FormatException('unsafe-entitlement-list');
      }
      return List<String>.unmodifiable(value.cast<String>());
    }
    final ownedFrames=list('ownedFrames',frames.contains,13);
    final ownedCards=list('ownedCards',cards.contains,4);
    final ownedIds=list('ownedPremiumIds',premiumId.hasMatch,249);
    final unreviewed=list('unreviewedNativeFrames',frames.contains,13);
    final pending=list('pendingNativeFrames',frames.contains,13);
    final active=raw['activePremiumId'];
    final status=raw['premiumLedgerStatus'] as String;
    if((active!=null&&(active is! String||!premiumId.hasMatch(active)))||
       (active!=null&&!ownedIds.contains(active))||
       (status=='missing-needs-review'&&(ownedIds.isNotEmpty||active!=null))||
       unreviewed.any(ownedFrames.contains)) {
      throw const FormatException('entitlement-proof-contradiction');
    }
    return DedaVerifiedReadonlyEntitlements(
      ownedFrames:ownedFrames,ownedCards:ownedCards,ownedPremiumIds:ownedIds,
      activePremiumId:active as String?,premiumLedgerStatus:status,
      unreviewedNativeFrames:unreviewed,pendingNativeFrames:pending,
    );
  }
}

class DedaSecondPhoneVerifiedLink {
  const DedaSecondPhoneVerifiedLink(this.status, this.progress);
  final DedaSecondPhoneLinkStatus status;
  final DedaVerifiedReadonlyProgress progress;
}

class DedaSecondPhoneLinkClient {
  const DedaSecondPhoneLinkClient(this.transport);
  final DedaSecondPhoneLinkTransport transport;

  /// No account, original UID, PIN, installId, balances or league XP is
  /// transmitted. Firebase Auth adds the authenticated UID automatically.
  Future<DedaSecondPhoneLinkStatus> link({
    required bool Function() isCurrent,
  }) async => (await linkAndReadVerifiedProgress(isCurrent: isCurrent)).status;

  Future<DedaSecondPhoneVerifiedLink> linkAndReadVerifiedProgress({
    required bool Function() isCurrent,
  }) async {
    if (!transport.emulatorConfigured) {
      throw StateError('private-second-phone-emulator-required');
    }
    void check(String uid) {
      if (!isCurrent() ||
          !transport.isAnonymous ||
          transport.currentUid != uid) {
        throw const DedaStaleSessionTransition();
      }
    }
    final uid = transport.currentUid;
    if (uid == null || uid.isEmpty || !transport.isAnonymous) {
      throw const DedaStaleSessionTransition();
    }
    check(uid);
    final reply = await transport.linkWithoutClientAccountDetails();
    check(uid);
    if (reply.length != 11 ||
        reply['status'] != 'ACCOUNT_LINKED_READONLY_EMULATOR_ONLY' ||
        reply['emulatorOnly'] != true ||
        reply['replayed'] is! bool ||
        reply['canRestoreFinancialBalances'] != false ||
        reply['canCreditXp'] != false ||
        reply['canCreditDiamonds'] != false ||
        reply['canRestoreFrames'] != false ||
        reply['canRestorePremiumId'] != false ||
        reply['canIssueLeagueGift'] != false ||
        reply['productionReady'] != false) {
      throw const FormatException('unsafe-private-link-reply');
    }
    final progress = DedaVerifiedReadonlyProgress.parse(
        reply['verifiedProgress']);
    check(uid);
    return DedaSecondPhoneVerifiedLink(
      reply['replayed'] == true
          ? DedaSecondPhoneLinkStatus.alreadyLinkedAwaitingSettlement
          : DedaSecondPhoneLinkStatus.linkedAwaitingSettlement,
      progress,
    );
  }
}
