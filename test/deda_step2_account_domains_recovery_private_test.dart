import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_step2_recovery_guardian.dart';
import 'package:d_iraq_ludo/deda_step2_account_domains_recovery_readback.dart';

const account='07712345678', uid='original-uid-100436',
    original='@DEDA-ABC123', week='2026-11-01';

class FakeDomains implements DedaDomainSourceIo {
  FakeDomains({this.crossOwner=false,this.cached=false,
    this.badFriend=false,this.badGift=false,this.emptyCloud=false});
  final bool crossOwner,cached,badFriend,badGift,emptyCloud;
  final List<String> reads=<String>[];
  int writes=0;

  @override
  Future<DedaDomainServerRow> document(String path) async {
    reads.add(path);
    final d=<String,Map<String,dynamic>>{
      'deda_share_ids/$original': {
        'publicId': original, 'ownerUid':crossOwner?'foreign-uid':uid,
        'kind':'personal','active':true,
      },
      'users/$uid': {'accountKey':account,'sharePersonalId':original},
      'deda_account_profiles/$account': {
        'accountKey':account,'name':'Owner','accountType':'user',
      },
      'deda_social_profiles/$original': {
        'ownerUid':uid,'publicId':original,'displayName':'Owner',
      },
      'deda_diamond_gift_balances/$original': {
        'publicId':original,'balance':350,
      },
      'deda_stage71_active_identifier/$original': {
        'originalId':original,'activeId':'@DEDA-QA1234',
      },
      'deda_weekly_direct_accounts/$original': {
        'accountKey':account,'publicId':original,
      },
      'deda_weekly_direct_control/active': {'weekId':week},
      'deda_weekly_direct_weeks/$week/scores/$original': {
        'weekId':week,'publicId':original,'weeklyXp':85,
      },
      'deda_profile_ui_migration/$account': {
        'accountKey':account,'originalId':original,'uid':uid,
        'kind':'free-profile-appearance-only',
      },
    };
    if (path.startsWith('deda_gm_personal_diamond_wallets/')) {
      throw StateError('ADMIN_WALLET_READ_NOT_PERMITTED_FOR_OWNER');
    }
    if(path.startsWith('deda_quiz_ui_snapshots/$uid/days/')) {
      final day=path.split('/').last;
      return DedaDomainServerRow({
        'kind':'display-only-untrusted-quiz-v1','uid':uid,
        'accountKey':account,'originalId':original,'day':day,
      });
    }
    if(!d.containsKey(path)) {
      throw StateError('unexpected-path:$path');
    }
    return DedaDomainServerRow(
      emptyCloud && (path.startsWith('deda_diamond_gift_balances/') ||
          path.startsWith('deda_profile_ui_migration/')) ? null : d[path],
      cached: cached && path=='users/$uid');
  }

  @override
  Future<List<DedaDomainServerRow>> friendships(String ownerUid) async {
    expect(ownerUid,uid);
    reads.add('query:friends:$ownerUid');
    if(emptyCloud)return <DedaDomainServerRow>[];
    return <DedaDomainServerRow>[
      DedaDomainServerRow({
        'members':<String>[uid,'friend-uid'],
        'requesterUid':uid,'recipientUid':'friend-uid',
        'status': 'accepted',
      },id:'pair-1'),
      DedaDomainServerRow({
        'members':<String>[uid,badFriend?uid:'friend-two'],
        'requesterUid':uid,'recipientUid':'friend-two',
        'status':'pending',
      },id:'pair-2'),
    ];
  }

  @override
  Future<List<DedaDomainServerRow>> receivedGifts(String id) async {
    expect(id,original);
    reads.add('query:gifts:$id');
    if(emptyCloud)return <DedaDomainServerRow>[];
    return <DedaDomainServerRow>[
      DedaDomainServerRow({
        'targetPublicId':badGift?'@DEDA-OTHER1':original,
        'amount':100,'status':'claimed',
      },id:'gift-001'),
    ];
  }
}

DedaVaultVerifiedScope scope({bool Function()? current,
  Future<bool> Function()? originalProof}) =>
    DedaVaultVerifiedScope(
      accountKey:account,originalUid:uid,originalId:original,
      intentId:'recover_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      isCurrentIntent:current ?? ()=>true,
      verifyOriginalOwnerOnServer:originalProof ?? ()async=>true,
    );

void main() {
  test('server-owned friends gifts wallet and league preserve UID without a single grant',
      () async {
    final io=FakeDomains();
    final out=await DedaStep2AccountDomainsRecoveryReadback(
      io:io,enabled:true).inspect(scope());
    expect(out.friendRelations,2);
    expect(out.acceptedFriends,1);
    expect(out.giftReceipts,1);
    expect(out.existingGiftWallet,350);
    expect(out.existingWeeklyXp,85);
    expect(out.activeDisplayId,'@DEDA-QA1234');
    expect(out.status['quizUiToday'],
        'verified-source-ui-only-hydration-separate');
    expect(RegExp(r'^20\d{2}-\d{2}-\d{2}$').hasMatch(out.iraqDay),true);
    expect(out.status['friends'],'verified-existing-uid-relations');
    expect(out.status['giftInbox'],'verified-existing-receipts-no-reissue');
    expect(out.status['earnedDiamonds'],'legacy-award-ledger-not-attested');
    expect(out.canCreditDiamonds,false);
    expect(out.canIssueGiftOrWeeklyPrize,false);
    expect(out.fullAccountRestored,false);
    expect(io.writes,0);
    expect(io.reads.where((p)=>p.startsWith(
      'deda_gm_personal_diamond_wallets/')),isEmpty);
  });
  test('empty cloud gift/friends is unknown, never zero reconstructed balances',
      () async {
    final io=FakeDomains(emptyCloud:true);
    final out=await DedaStep2AccountDomainsRecoveryReadback(
      io:io,enabled:true).inspect(scope());
    expect(out.friendRelations,0);
    expect(out.giftReceipts,0);
    expect(out.existingGiftWallet,isNull);
    expect(out.status['giftWallet'],'absent-unknown-not-zero');
    expect(out.status['friends'],'server-query-empty-legacy-unknown');
    expect(out.fullAccountRestored,false);
  });
  test('foreign original ID UID is rejected before protected data reads',
      () async {
    final io=FakeDomains(crossOwner:true);
    await expectLater(DedaStep2AccountDomainsRecoveryReadback(
      io:io,enabled:true).inspect(scope()),
      throwsA(isA<DedaDomainSourceHold>()));
    expect(io.reads.any((s)=>s.startsWith('query:')),false);
  });
  test('wrong friend or gift owner never becomes verified data',
      () async {
    for(final io in <FakeDomains>[FakeDomains(badFriend:true),
                                FakeDomains(badGift:true)]) {
      await expectLater(DedaStep2AccountDomainsRecoveryReadback(
        io:io,enabled:true).inspect(scope()),
        throwsA(isA<DedaDomainSourceHold>()));
      expect(io.writes,0);
    }
  });
  test('changed session or cached server data causes secure hold',() async {
    for(final arg in <FakeDomains>[
      FakeDomains(cached:true),FakeDomains()
    ]) {
      final verified=DedaStep2AccountDomainsRecoveryReadback(io:arg,
        enabled:true);
      await expectLater(verified.inspect(arg.cached?scope():
          scope(current:()=>false)),throwsA(anything));
      expect(arg.writes,0);
    }
  });
  test('explicit guard OFF blocks all account queries',() async {
    final io=FakeDomains();
    await expectLater(DedaStep2AccountDomainsRecoveryReadback(
      io:io,enabled:false).inspect(scope()),
      throwsA(isA<DedaDomainSourceHold>()));
    expect(io.reads,isEmpty);
  });
}
