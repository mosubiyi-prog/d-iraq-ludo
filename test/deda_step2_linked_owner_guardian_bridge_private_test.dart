import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_step2_linked_owner_flutter_handoff.dart';
import 'package:d_iraq_ludo/deda_step2_recovery_guardian.dart';
import 'package:d_iraq_ludo/deda_step2_account_domains_recovery_readback.dart';
import 'package:d_iraq_ludo/deda_step2_assets_readback.dart';
import 'package:d_iraq_ludo/deda_step2_diamond_reconciliation_readonly.dart';
import 'package:d_iraq_ludo/deda_step2_linked_owner_guardian_bridge.dart';
import 'package:d_iraq_ludo/deda_step2_linked_owner_guardian_assembly.dart';

const account = '9647712345678';
const uid = 'verified-original-uid';
const normalId = '@DEDA-ABC123';
const intent = 'persisted_recovery_intent_20261104';
const install = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

class FakePort implements DedaLoginHandoffPort {
  DedaLoginIdentity identity =
      const DedaLoginIdentity(null, null, DedaLoginKind.absent, 0);
  final List<String> events = <String>[];
  bool ownerValid = true;
  bool sessionValid = true;
  bool grantValid = true;
  void Function()? onOwnerProof;
  @override
  DedaLoginIdentity current() => identity;
  @override
  Future<T> inExistingOwnerLane<T>(
      Future<T> Function() action, bool Function() isCurrentIntent) async {
    events.add('lane');
    if (!isCurrentIntent()) throw StateError('stale');
    return action();
  }
  @override
  Future<DedaLoginIdentity> signInOriginal(String key, String pin) async {
    events.add('auth');
    if (pin != '123456') throw StateError('wrong-pin');
    identity = DedaLoginIdentity(uid, '$key@deda-login.invalid',
        DedaLoginKind.linked, identity.epoch + 1);
    return identity;
  }
  @override
  Future<void> proveOriginal(
      String key, String originalId, String claimedUid) async {
    events.add('proof');
    if (!ownerValid || key != account ||
        originalId != normalId || claimedUid != uid) {
      throw StateError('wrong-owner');
    }
    onOwnerProof?.call();
  }
  @override
  Future<String> installId() async {
    events.add('install');
    return install;
  }
  @override
  Future<bool> grantDevice(String key, String originalId,
      String claimedUid, String installationId) async {
    events.add('grant');
    return grantValid;
  }
  @override
  Future<void> writeSession(String key, String claimedUid,
      String installationId) async {
    events.add('write');
  }
  @override
  Future<bool> readbackSession(String key, String claimedUid) async {
    events.add('readback');
    return sessionValid;
  }
}
class FakeJournal implements DedaVaultRecoveryJournal {
  final Map<String, DedaVaultJournalRow> rows = {};
  int created = 0;
  int completed = 0;
  @override
  Future<DedaVaultJournalRow?> read(
      DedaVaultVerifiedScope scope, DedaVaultCode code) async =>
      rows[scope.operationKey(code)];
  @override
  Future<bool> reserveIfAbsent(DedaVaultVerifiedScope scope,
      DedaVaultCode code, String operationKey) async {
    if (rows.containsKey(operationKey)) return false;
    created++;
    rows[operationKey] = DedaVaultJournalRow(
        operationKey: operationKey, state: DedaVaultJournalState.reserved);
    return true;
  }
  @override
  Future<void> markVerified(DedaVaultVerifiedScope scope, DedaVaultCode code,
      String operationKey, String receiptId) async {
    completed++;
    rows[operationKey] = DedaVaultJournalRow(
        operationKey: operationKey,
        state: DedaVaultJournalState.verified,
        receiptId: receiptId);
  }
}
class FakeWorker implements DedaVaultWorkerAdapter {
  int calls = 0;
  DedaVaultReceipt? receipt;
  @override
  DedaVaultCode get code => DedaVaultCode.originalBackupReadback;
  @override
  Future<void> executeOnce(DedaVaultVerifiedScope scope, String op) async {
    calls++;
    receipt = DedaVaultReceipt(
      accountKey: scope.accountKey, originalUid: scope.originalUid,
      code: code, operationKey: op, receiptId: 'server-receipt-000001');
  }
  @override
  Future<DedaVaultReceipt?> confirmByReadback(
      DedaVaultVerifiedScope scope, String op) async => receipt;
}
DedaLinkedOwnerGuardianBridge make(FakePort port, FakeJournal journal, {
  bool enabled = true,
  Map<DedaVaultCode, DedaVaultWorkerAdapter> adapters = const {},
  bool guardianEnabled = true,
  DedaStep2AccountDomainsRecoveryReadback? domainReadback,
  DedaStep2AssetsReadback? assetReadback,
  DedaStep2DiamondReconciliationReader? diamondReadback,
  Future<String?> Function(DedaVaultVerifiedScope)? originalAdWalletRaw,
  Future<bool> Function(DedaVaultVerifiedScope)? restoreFreeAppearance,
  Future<bool> Function(DedaVaultVerifiedScope,String)? restoreQuizUi,
}) => DedaLinkedOwnerGuardianBridge(
  enabled: enabled,
  handoff: DedaLoginHandoff(port, enabled: true),
  domainReadback: domainReadback,
  assetReadback: assetReadback,
  diamondReadback: diamondReadback,
  originalAdWalletRaw: originalAdWalletRaw,
  restoreFreeAppearance: restoreFreeAppearance,
  restoreQuizUi: restoreQuizUi,
  guardian: DedaStep2RecoveryGuardian(
    journal: journal, adapters: adapters,
    enabledForPrivateTests: guardianEnabled,
  ),
);
Future<DedaLinkedGuardianLoginResult> login(
    DedaLinkedOwnerGuardianBridge bridge, {
    bool explicit = true,
    bool recover = false,
    bool Function()? current,
    String? recoveryIntentId,
    Set<DedaVaultCode> selected = const {},
    DedaVaultRecoveryTrigger trigger =
        DedaVaultRecoveryTrigger.explicitUserRequest,
    }) => bridge.loginAndPrepare(
  phone: account, pin: '123456', originalId: normalId,
  explicitUserAction: explicit,
  isCurrentIntent: current ?? () => true,
  explicitRecoveryRequest: recover,
  recoveryIntentId: recoveryIntentId,
  selectedCodes: selected,
  trigger: trigger,
);


class FakeCloudDomainIo implements DedaDomainSourceIo {
  final List<String> reads = <String>[];
  @override
  Future<DedaDomainServerRow> document(String path) async {
    reads.add(path);
    final values=<String,Map<String,dynamic>>{
      'deda_share_ids/$normalId': {
        'publicId':normalId,'ownerUid':uid,'kind':'personal','active':true,
      },
      'users/$uid': {'accountKey':account,'sharePersonalId':normalId},
      'deda_account_profiles/$account': {
        'accountKey':account,'accountType':'user',
      },
      'deda_profile_ui_migration/$account': {
        'accountKey':account,'originalId':normalId,'uid':uid,
        'kind':'free-profile-appearance-only',
      },
    };
    if(path.startsWith('deda_quiz_ui_snapshots/$uid/days/')) {
      return DedaDomainServerRow({
        'kind':'display-only-untrusted-quiz-v1',
        'uid':uid,'accountKey':account,'originalId':normalId,
        'day':path.split('/').last,
      });
    }
    if(path.startsWith('deda_gm_personal_diamond_wallets/')) {
      throw StateError('forbidden-manager-wallet-query');
    }
    return DedaDomainServerRow(values[path]);
  }
  @override
  Future<List<DedaDomainServerRow>> friendships(String uid) async {
    reads.add('friendships:$uid');
    return <DedaDomainServerRow>[];
  }
  @override
  Future<List<DedaDomainServerRow>> receivedGifts(String id) async {
    reads.add('gifts:$id');
    return <DedaDomainServerRow>[];
  }
}

class FakeOriginalAssetIo implements DedaStep2AssetsIo {
  final List<String> queries = <String>[];
  bool errorOnAssets = false;
  @override
  Future<DedaStep2CloudDocument> server(String path) async {
    queries.add(path);
    if (errorOnAssets) throw StateError('assets-must-not-run');
    if (path=='deda_share_ids/$normalId') {
      return const DedaStep2CloudDocument({
        'publicId':normalId,'ownerUid':uid,
        'kind':'personal','active':true,
      });
    }
    if (path=='deda_account_profiles/$account') {
      return const DedaStep2CloudDocument({
        'accountKey':account,'name':'Linked Original',
        'accountType':'user',
      });
    }
    if (path=='deda_diamond_gift_balances/$normalId') {
      return const DedaStep2CloudDocument({
        'publicId':normalId,'balance':750,
      });
    }
    if (path=='deda_stage71_active_identifier/$normalId') {
      return const DedaStep2CloudDocument({
        'originalId':normalId,'activeId':normalId,
      });
    }
    if (path.startsWith('deda_gm_personal_diamond_wallets/')) {
      throw StateError('forbidden-gm-personal-wallet');
    }
    return const DedaStep2CloudDocument(null);
  }
  @override
  Future<Set<String>> ownedFrameIds(String id) async {
    queries.add('frames:$id'); return <String>{};
  }
  @override
  Future<Set<String>> acceptedOwnedPremiumIds(String id) async {
    queries.add('accepted:$id'); return <String>{};
  }
}

DedaStep2AssetsReadback fakeOriginalAssetReadback(FakeOriginalAssetIo io) =>
  DedaStep2AssetsReadback(io:io,enabled:true,
    currentUid:()=>uid,
    verifyOriginalOwner:(u,a)async=>u==uid && a==account);

void main() {
  const backup = DedaVaultCode.originalBackupReadback;

  test('guarded recovery audits canonical domains and hydrates free UI only',() async {
    final p=FakePort(),j=FakeJournal(),w=FakeWorker();
    final io=FakeCloudDomainIo();
    var appearance=0,quiz=0;
    final bridge=make(p,j,adapters:{backup:w},
      domainReadback:DedaStep2AccountDomainsRecoveryReadback(
        io:io,enabled:true),
      restoreFreeAppearance:(scope) async {
        appearance++;
        expect(scope.originalUid,uid);
        return true;
      },
      restoreQuizUi:(scope,day) async {
        quiz++;
        expect(day.length,10);
        expect(day.contains('-'),true);
        return true;
      },
    );
    final result=await login(bridge,recover:true,
      recoveryIntentId:intent,selected:{backup});
    expect(result.recovery!.stepStates[backup],DedaVaultStepState.verified);
    expect(result.domainContinuity,isNotNull);
    expect(result.domainContinuity!.existingGiftWallet,isNull);
    expect(result.domainContinuity!.status['giftWallet'],
      'absent-unknown-not-zero');
    expect(result.freeAppearanceHydrated,true);
    expect(result.quizUiHydrated,true);
    expect(result.fullAccountRestored,false);
    expect(appearance,1);
    expect(quiz,1);
    expect(io.reads.any((v)=>v.startsWith(
      'deda_gm_personal_diamond_wallets/')),false);
  });

  test('explicit recovery reads verified diamonds/cards once, no grant or debit',() async {
    final p=FakePort(),j=FakeJournal(),w=FakeWorker(),io=FakeOriginalAssetIo();
    final bridge=make(p,j,adapters:{backup:w},
      assetReadback:fakeOriginalAssetReadback(io));
    final value=await login(bridge,recover:true,
      recoveryIntentId:intent,selected:{backup});
    expect(value.assetContinuity,isNotNull);
    expect(value.assetContinuity!.receivedGiftWalletBalance,750);
    expect(value.assetContinuity!.verifiedPaidCardStyles,isEmpty);
    expect(value.assetContinuity!.verifiedAcceptedPremiumIds,isEmpty);
    expect(value.fullAccountRestored,false);
    expect(value.assetContinuity!.canRestoreDiamonds,false);
    expect(j.created,1);
    expect(io.queries.any((q)=>q.startsWith(
      'deda_gm_personal_diamond_wallets/')),false);
  });

  test('explicit guarded recovery inspects archived ad and gift wallet with zero credit',() async {
    final p=FakePort(),j=FakeJournal(),w=FakeWorker(),io=FakeCloudDomainIo();
    var archiveReads=0;
    final bridge=make(p,j,adapters:{backup:w},
      diamondReadback:DedaStep2DiamondReconciliationReader(
        io:io,enabled:true),
      originalAdWalletRaw:(scope) async {
        archiveReads++;
        expect(scope.originalUid,uid);
        return '{"balance":63,"viewsToday":2,"day":"2026-11-05"}';
      },
    );
    final result=await login(bridge,recover:true,
      recoveryIntentId:intent,selected:{backup});
    expect(result.diamondContinuity,isNotNull);
    expect(result.diamondContinuity!.receivedGiftWalletBalance,isNull);
    expect(result.diamondContinuity!.localAdWallet.untrustedBalance,63);
    expect(result.diamondContinuity!.additionalSpendableDiamonds,0);
    expect(result.completion.domains['earnedAdDiamonds'],
      DedaStep2CompletionState.missingHistoricalProof);
    expect(result.fullAccountRestored,false);
    expect(archiveReads,1);
    expect(j.created,1);
    expect(io.reads,contains('gifts:$normalId'));
  });

  test('diamond recovery fails closed if original-phone evidence callback absent',() async {
    final p=FakePort(),j=FakeJournal(),w=FakeWorker(),io=FakeCloudDomainIo();
    final bridge=make(p,j,adapters:{backup:w},
      diamondReadback:DedaStep2DiamondReconciliationReader(
        io:io,enabled:true));
    await expectLater(login(bridge,recover:true,
      recoveryIntentId:intent,selected:{backup}),throwsStateError);
    expect(io.reads,isEmpty);
  });

  test('normal login and blocked guardian read no assets',() async {
    final p=FakePort(),j=FakeJournal(),io=FakeOriginalAssetIo()
      ..errorOnAssets=true;
    final bridge=make(p,j,
      assetReadback:fakeOriginalAssetReadback(io));
    final ordinary=await login(bridge);
    expect(ordinary.assetContinuity,isNull);
    expect(io.queries,isEmpty);
    await expectLater(login(bridge,recover:true,
      recoveryIntentId:intent,selected:{backup}),throwsStateError);
    expect(io.queries,isEmpty);
  });

  test('blocked guardian never invokes domain audit or free UI restores',() async {
    final p=FakePort(),j=FakeJournal(),io=FakeCloudDomainIo();
    var hydrated=0;
    final bridge=make(p,j,
      domainReadback:DedaStep2AccountDomainsRecoveryReadback(
        io:io,enabled:true),
      restoreFreeAppearance:(scope) async {
        hydrated++;
        return true;
      });
    final result=await login(bridge,recover:true,
      recoveryIntentId:intent,selected:{backup});
    expect(result.recovery!.stoppedSafely,true);
    expect(result.domainContinuity,isNull);
    expect(hydrated,0);
    expect(io.reads,isEmpty);
  });

  test('OFF by default: assembly and bridge perform zero actions', () async {
    expect(dedaLinkedOwnerGuardianBridgeEnabled, false);
    expect(() => DedaLinkedOwnerGuardianAssembly.prepare(), throwsStateError);
    final p = FakePort(), j = FakeJournal();
    await expectLater(login(make(p, j, enabled: false)), throwsStateError);
    expect(p.events, isEmpty);
    expect(j.created, 0);
  });
  test('normal verified login never starts recovery', () async {
    final p = FakePort(), j = FakeJournal();
    final result = await login(make(p, j));
    expect(result.originalUid, uid);
    expect(result.accountKey, account);
    expect(result.recovery, isNull);
    expect(result.fullAccountRestored, false);
    expect(p.events, ['lane','auth','proof','install','grant','write','readback']);
    expect(j.created, 0);
  });
  test('no sneaked recovery without separate explicit request', () async {
    final p = FakePort(), j = FakeJournal();
    await expectLater(login(make(p,j),selected:{backup}), throwsStateError);
    expect(p.events, isEmpty);
    expect(j.created, 0);
  });
  test('recovery requires persisted intent and reviewed code BEFORE Auth', () async {
    final p = FakePort(), j = FakeJournal();
    await expectLater(login(make(p,j),recover:true,selected:{backup}),
        throwsStateError);
    await expectLater(login(make(p,j),recover:true,
        recoveryIntentId:intent,selected:{DedaVaultCode.socialService}),
        throwsStateError);
    expect(p.events, isEmpty);
  });
  test('explicit recovery with approved worker runs once, no full claim', () async {
    final p = FakePort(), j = FakeJournal(), w = FakeWorker();
    final bridge = make(p, j, adapters:{backup:w});
    final result = await login(bridge,recover:true,
        recoveryIntentId:intent,selected:{backup});
    expect(result.recovery!.stepStates[backup], DedaVaultStepState.verified);
    expect(result.fullAccountRestored, false);
    expect(j.created, 1);
    expect(j.completed, 1);
    expect(w.calls, 1);
    await expectLater(login(bridge,recover:true,
        recoveryIntentId:intent,selected:{backup}), throwsStateError);
    expect(w.calls, 1);
  });
  test('without approved worker, guardian blocks without reserve', () async {
    final p = FakePort(), j = FakeJournal();
    final result = await login(make(p,j),recover:true,
        recoveryIntentId:intent,selected:{backup});
    expect(result.recovery!.stoppedSafely, true);
    expect(result.recovery!.stepStates[backup], DedaVaultStepState.blocked);
    expect(j.created, 0);
    expect(result.fullAccountRestored, false);
  });
  test('verified resume does not invent a new journal operation', () async {
    final p = FakePort(), j = FakeJournal(), w = FakeWorker();
    final result = await login(make(p,j,adapters:{backup:w}),recover:true,
        recoveryIntentId:intent,selected:{backup},
        trigger:DedaVaultRecoveryTrigger.explicitlyVerifiedResume);
    expect(result.recovery!.stepStates[backup], DedaVaultStepState.blocked);
    expect(j.created, 0);
    expect(w.calls, 0);
  });
  test('server owner rejection prevents every guardian write', () async {
    final p = FakePort()..ownerValid=false, j = FakeJournal();
    await expectLater(login(make(p,j),recover:true,
        recoveryIntentId:intent,selected:{backup}), throwsStateError);
    expect(j.created, 0);
  });
  test('server session rejection prevents guardian dispatch', () async {
    final p = FakePort(), j = FakeJournal();
    p.onOwnerProof = () => p.sessionValid = false;
    await expectLater(login(make(p,j),recover:true,
        recoveryIntentId:intent,selected:{backup}), throwsStateError);
    expect(j.created, 0);
  });
  test('intent expiry after owner proof prevents every worker', () async {
    final p = FakePort(), j = FakeJournal();
    var alive = true;
    p.onOwnerProof = () => alive = false;
    await expectLater(login(make(p,j),recover:true,current:()=>alive,
        recoveryIntentId:intent,selected:{backup}), throwsStateError);
    expect(j.created, 0);
  });
  test('same UID with changed epoch is not eligible', () async {
    final p = FakePort(), j = FakeJournal();
    var proofs = 0;
    p.onOwnerProof = () {
      proofs++;
      if(proofs > 1) {
        final prev = p.identity;
        p.identity = DedaLoginIdentity(
            prev.uid,prev.email,prev.kind,prev.epoch+2);
      }
    };
    await expectLater(login(make(p,j),recover:true,
        recoveryIntentId:intent,selected:{backup}), throwsStateError);
    expect(j.created, 0);
  });
  test('linked account A cannot silently replace itself with B', () async {
    final p = FakePort(), j = FakeJournal();
    p.identity = const DedaLoginIdentity(
        'foreign-uid','other@example.com',DedaLoginKind.linked,3);
    await expectLater(login(make(p,j)),throwsStateError);
    expect(p.identity.uid,'foreign-uid');
    expect(p.events,isEmpty);
  });
}
