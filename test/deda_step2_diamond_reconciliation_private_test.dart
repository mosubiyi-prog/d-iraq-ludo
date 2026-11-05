import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_legacy_progress_capture.dart';
import 'package:d_iraq_ludo/deda_legacy_purchase_evidence.dart';
import 'package:d_iraq_ludo/deda_step2_financial_source_audit.dart';
import 'package:d_iraq_ludo/deda_step2_account_domains_recovery_readback.dart';
import 'package:d_iraq_ludo/deda_step2_assets_readback.dart';
import 'package:d_iraq_ludo/deda_step2_diamond_reconciliation_readonly.dart';
import 'package:d_iraq_ludo/deda_step2_legacy_ad_wallet_audit.dart';
import 'package:d_iraq_ludo/deda_step2_recovery_guardian.dart';

const account = '9647712345678';
const ownerUid = 'original-owner-uid';
const original = '@DEDA-ABC123';

class MemoryServerSources implements DedaDomainSourceIo {
  MemoryServerSources({this.balance = 20, this.hasWallet = true});
  final int? balance;
  final bool hasWallet;
  bool cached = false;
  List<DedaDomainServerRow> gifts = [
    const DedaDomainServerRow({
      'giftId': 'admin-gift-1',
      'targetPublicId': original, 'sourceType': 'admin',
      'status': 'received', 'amount': 50,
    }, id: 'admin-gift-1'),
    const DedaDomainServerRow({
      'giftId': 'weekly-prize-2',
      'targetPublicId': original, 'sourceType': 'weekly_league',
      'status': 'claimed', 'amount': 30,
    }, id: 'weekly-prize-2'),
    const DedaDomainServerRow({
      'giftId': 'pending-gift-3',
      'targetPublicId': original, 'sourceType': 'admin',
      'status': 'pending', 'amount': 10,
    }, id: 'pending-gift-3'),
  ];
  final List<String> visited = [];

  @override
  Future<DedaDomainServerRow> document(String path) async {
    visited.add(path);
    final Map<String, dynamic>? row = switch (path) {
      'deda_share_ids/$original' => {
        'publicId':original, 'ownerUid':ownerUid,
        'kind':'personal','active':true,
      },
      'users/$ownerUid' => {
        'accountKey':account,'sharePersonalId':original,
      },
      'deda_diamond_gift_balances/$original' => hasWallet
          ? {'publicId':original,'balance':balance}
          : null,
      _ => throw StateError('unexpected-path-read'),
    };
    return DedaDomainServerRow(row, cached:cached);
  }

  @override
  Future<List<DedaDomainServerRow>> receivedGifts(String id) async {
    visited.add('deda_diamond_gifts?$id');
    return gifts;
  }

  @override
  Future<List<DedaDomainServerRow>> friendships(String uid) =>
      throw UnimplementedError('diamond-audit-must-not-read-friends');
}

DedaVaultVerifiedScope scope({
  bool Function()? current, Future<bool> Function()? owner,
}) => DedaVaultVerifiedScope(
  accountKey:account,originalUid:ownerUid,originalId:original,
  intentId:'stage2-original-owner-intent-01',
  isCurrentIntent:current ?? () => true,
  verifyOriginalOwnerOnServer:owner ?? () async => true,
);

DedaStep2DiamondReconciliationReader reader(MemoryServerSources src) =>
  DedaStep2DiamondReconciliationReader(io:src,enabled:true);

DedaStep2ArchivedDiamondFinancialSource oldPhone({
  String? adRaw = '{"balance":63,"viewsToday":2,"day":"2026-11-05"}',
  String uid = ownerUid,
  String key = account,
  String id = original,
  String capture = 'original_diamond_capture_id_20261105',
  String installId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
}) {
  final progress=DedaLegacyProgressCapture.decodeForAccount(
    jsonEncode({'format':1,'accountKey':account,
      'records':{
        'taskPoints':'{"points":150}',
        'socialCoinsAndXp':'{"xp":150}',
        'earnedDiamonds':adRaw,
      }}), expectedAccountKey:account,
  );
  final purchase=DedaLegacyPurchaseCapture.decode(
    jsonEncode({'format':1,'accountKey':account,'originalId':original,
      'inventory':'{"owned":[]}',
      'frameJournals':{
        for(final frame in dedaLegacyPurchaseFrames) frame:null,
      }}),accountKey:account,originalId:original,
  );
  return DedaStep2ArchivedDiamondFinancialSource(
    accountKey:key,originalUid:uid,originalId:id,captureId:capture,
    sourceInstallId:installId,
    audit:DedaStep2FinancialSourceAudit.inspect(
      progress:progress,purchase:purchase),
  );
}

void main() {
  test('OFF by default; no implicit public APK financial migration', () {
    expect(dedaStep2DiamondReconciliationReadOnlyEnabled,false);
    expect(() async => await DedaStep2DiamondReconciliationReader(
      io:MemoryServerSources()).inspect(
        scope:scope(),archivedSource:oldPhone(adRaw:null)),throwsA(
          isA<DedaStep2DiamondHold>()));
  });

  test('old 63 ad, gift wallet 20, claimed receipts 80: never sum or re-credit',
      () async {
    final src=MemoryServerSources();
    final r=await reader(src).inspect(scope:scope(),
      archivedSource:oldPhone());
    expect(r.receivedGiftWalletBalance,20);
    expect(r.archivalReviewCaseKey,
      'deda_legacy_diamond_review_v1/$ownerUid/original_diamond_capture_id_20261105');
    expect(r.manualLegacyBalanceReviewRequired,true);
    expect(r.missingOldPhoneValues,isEmpty);
    expect(r.receivedGiftGross,80);
    expect(r.pendingGiftGross,10);
    expect(r.receivedGiftReceipts,2);
    expect(r.pendingGiftReceipts,1);
    expect(r.localAdWallet.untrustedBalance,63);
    expect(r.localAdWallet.status,
        DedaStep2LegacyAdWalletStatus.structurallyPlausibleUntrusted);
    expect(r.additionalGiftDiamondsToCredit,0);
    expect(r.importedOldPhoneAdDiamonds,0);
    expect(r.additionalSpendableDiamonds,0);
    expect(r.canRestoreSpendableBalance,false);
    expect(r.canReplayGifts,false);
    expect(r.hasCompleteEarnAndSpendHistory,false);
    expect(r.fullAccountRestored,false);
    expect(src.visited,[
      'deda_share_ids/$original','users/$ownerUid',
      'deda_diamond_gift_balances/$original',
      'deda_diamond_gifts?$original',
    ]);
  });

  test('missing source is UNKNOWN, never reset balance to zero', () async {
    final report=await reader(MemoryServerSources(hasWallet:false))
        .inspect(scope:scope(),archivedSource:oldPhone(adRaw:null));
    expect(report.receivedGiftWalletBalance,isNull);
    expect(report.missingOldPhoneValues,isNotEmpty);
    expect(report.localAdWallet.status,
        DedaStep2LegacyAdWalletStatus.missingUnknown);
    expect(report.warnings,
        contains('missing-gift-wallet-is-unknown-not-zero'));
    expect(report.importedOldPhoneAdDiamonds,0);
  });

  test('old phone account swap and invalid installation fail before wallet reads',
      () async {
    final src=MemoryServerSources();
    for(final invalid in [
      oldPhone(uid:'foreign-owner-uid'),
      oldPhone(key:'9647700000000'),
      oldPhone(id:'@DEDA-FOREIG'),
      oldPhone(capture:'short'),
      oldPhone(installId:'not-a-verified-install'),
    ]) {
      await expectLater(reader(src).inspect(
        scope:scope(),archivedSource:invalid),
        throwsA(isA<DedaStep2DiamondHold>()));
    }
    expect(src.visited,isEmpty);
  });

  test('same old-phone evidence yields same review key without duplicate payout',
      () async {
    final src=MemoryServerSources();
    final a=await reader(src).inspect(
      scope:scope(),archivedSource:oldPhone());
    final b=await reader(src).inspect(
      scope:scope(),archivedSource:oldPhone());
    expect(a.archivalReviewCaseKey,b.archivalReviewCaseKey);
    expect(a.additionalSpendableDiamonds,0);
    expect(b.additionalSpendableDiamonds,0);
    expect(a.canRestoreSpendableBalance,false);
  });

  test('repeated gift ID across server query is rejected before any credit',
      () async {
    final src=MemoryServerSources();
    src.gifts = [src.gifts.first,src.gifts.first];
    await expectLater(reader(src).inspect(
      scope:scope(),archivedSource:oldPhone(adRaw:null)),
      throwsA(isA<DedaStep2DiamondHold>()));
  });

  test('wrong recipient, unknown status, malformed or negative amount denied',
      () async {
    final src=MemoryServerSources();
    for (final change in [
      {'targetPublicId':'@DEDA-WRONG1'},
      {'status':'restored-again'},
      {'amount':-1},
      {'amount':1.5},
      {'giftId':'different-id'},
    ]) {
      src.gifts=[DedaDomainServerRow({
        ...src.gifts.first.fields!,...change,
      },id:'admin-gift-1')];
      await expectLater(reader(src).inspect(
        scope:scope(),archivedSource:oldPhone(adRaw:null)),
        throwsA(isA<DedaStep2DiamondHold>()));
    }
  });

  test('independent wallet source mismatch freezes rather than choosing higher',
      () async {
    final src=MemoryServerSources(balance:20);
    final domain=DedaAccountDomainContinuity(
      status:const {},friendRelations:0,acceptedFriends:0,giftReceipts:3,
      iraqDay:'2026-11-05',existingGiftWallet:25);
    await expectLater(reader(src).inspect(scope:scope(),
      archivedSource:oldPhone(adRaw:null),domainReadback:domain),
      throwsA(isA<DedaStep2DiamondHold>()));
  });

  test('asset wallet and server wallet must agree on original UID and amount',
      () async {
    const assets=DedaStep2AssetsEvidence(
      accountKey:account,originalUid:ownerUid,originalId:original,
      accountName:'Owner',accountType:'user',
      verifiedPaidFrameIds:{},verifiedPaidCardStyles:{},
      verifiedAcceptedPremiumIds:{},
      receivedGiftWalletBalance:10,managerPersonalBalance:null,
      activeDisplayId:null,currentWeeklyXp:null,serverSources:{},
    );
    await expectLater(reader(MemoryServerSources()).inspect(
      scope:scope(),archivedSource:oldPhone(adRaw:null),assetReadback:assets),
      throwsA(isA<DedaStep2DiamondHold>()));
  });

  test('cached financial source is invalid even when fields look correct',
      () async {
    final src=MemoryServerSources()..cached=true;
    await expectLater(reader(src).inspect(
      scope:scope(),archivedSource:oldPhone(adRaw:null)),
      throwsA(isA<DedaStep2DiamondHold>()));
  });

  test('owner mismatch and stale intent stop before any user wallet read',
      () async {
    final src=MemoryServerSources();
    await expectLater(reader(src).inspect(
      scope:scope(owner:() async => false),
      archivedSource:oldPhone(adRaw:null)),throwsStateError);
    expect(src.visited,isEmpty);
    await expectLater(reader(src).inspect(
      scope:scope(current:() => false),
      archivedSource:oldPhone(adRaw:null)),throwsStateError);
    expect(src.visited,isEmpty);
  });

  test('receipt count disagreement is HOLD, never import missing receipts',
      () async {
    final r=DedaAccountDomainContinuity(
      status:const {},friendRelations:0,acceptedFriends:0,giftReceipts:2,
      iraqDay:'2026-11-05');
    await expectLater(reader(MemoryServerSources()).inspect(
      scope:scope(),archivedSource:oldPhone(adRaw:null),domainReadback:r),
      throwsA(isA<DedaStep2DiamondHold>()));
  });
}
