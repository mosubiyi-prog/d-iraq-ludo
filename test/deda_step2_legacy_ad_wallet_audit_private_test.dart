import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_step2_legacy_ad_wallet_audit.dart';
import 'package:d_iraq_ludo/deda_step2_financial_source_audit.dart';
import 'package:d_iraq_ludo/deda_legacy_progress_capture.dart';
import 'package:d_iraq_ludo/deda_legacy_purchase_evidence.dart';

const account = '07712345678', original = '@DEDA-ABC123';

DedaStep2FinancialSourceAudit auditFrom(String? oldWallet) {
  final originalPhone = DedaLegacyProgressCapture.decodeForAccount(
    jsonEncode({
      'format':1,
      'accountKey':account,
      'records':{
        'taskPoints':null,
        'socialCoinsAndXp':null,
        'earnedDiamonds':oldWallet,
      },
    }),
    expectedAccountKey: account,
  );
  final purchase = DedaLegacyPurchaseCapture.decode(
    jsonEncode({
      'format':1,
      'accountKey':account,
      'originalId':original,
      'inventory':null,
      'frameJournals':{
        for (final frame in dedaLegacyPurchaseFrames) frame:null,
      },
    }),
    accountKey:account,originalId:original,
  );
  return DedaStep2FinancialSourceAudit.inspect(
    progress:originalPhone,purchase:purchase,
  );
}

void main() {
  test('valid old wallet shape is OBSERVATION only: never mint diamonds', () {
    final evidence = auditFrom(
      '{"balance":127,"viewsToday":2,"day":"2026-10-31"}');
    final ad = evidence.adWallet;
    expect(ad.status,
      DedaStep2LegacyAdWalletStatus.structurallyPlausibleUntrusted);
    expect(ad.untrustedBalance,127);
    expect(ad.untrustedViewsToday,2);
    expect(ad.untrustedDay,'2026-10-31');
    expect(ad.hasProviderSignedRewardReceipts,false);
    expect(ad.hasServerSpendLedger,false);
    expect(ad.canReconcileSpendableDiamondBalance,false);
    expect(ad.canReissueRewardedAdDiamonds,false);
    expect(evidence.canSettleFinancialBalances,false);
  });

  test('no original-phone ad wallet is UNKNOWN, never zero balance', () {
    final observation = auditFrom(null).adWallet;
    expect(observation.status,DedaStep2LegacyAdWalletStatus.missingUnknown);
    expect(observation.untrustedBalance,isNull);
    expect(observation.mayTreatMissingAsZero,false);
  });

  test('malformed wallet remains raw archive evidence but no numeric credit', () {
    for(final raw in <String>[
      'garbled',
      '',
      '{"balance":-1,"viewsToday":0,"day":"2026-10-31"}',
      '{"balance":999999999999,"viewsToday":0,"day":"2026-10-31"}',
      '{"balance":20,"viewsToday":6,"day":"2026-10-31"}',
      '{"balance":20,"viewsToday":1,"day":"2026-02-31"}',
      '{"balance":20.5,"viewsToday":1,"day":"2026-10-31"}',
      '{"balance":20,"viewsToday":1,"day":"2026-10-31","extra":1}',
      '{"balance":20,"viewsToday":1}',
      '[]',
      ' ' * 30001,
    ]) {
      final observation=auditFrom(raw).adWallet;
      expect(observation.status,
        DedaStep2LegacyAdWalletStatus.malformedUntrusted,
        reason:raw.length < 90 ? raw : 'oversized');
      expect(observation.untrustedBalance,isNull);
      expect(observation.canReconcileSpendableDiamondBalance,false);
    }
  });

  test('daily views are not an all-time ledger or trusted 3-gem receipts', () {
    final one = auditFrom(
      '{"balance":0,"viewsToday":0,"day":"2026-10-31"}').adWallet;
    final other = auditFrom(
      '{"balance":100,"viewsToday":5,"day":"2026-10-31"}').adWallet;
    expect(one.status,
      DedaStep2LegacyAdWalletStatus.structurallyPlausibleUntrusted);
    expect(other.status,
      DedaStep2LegacyAdWalletStatus.structurallyPlausibleUntrusted);
    expect(one.canReissueRewardedAdDiamonds,false);
    expect(other.canReissueRewardedAdDiamonds,false);
  });

  test('local evidence cannot claim checkout entitlement even if wallet plausible', () {
    final data=auditFrom(
      '{"balance":10000,"viewsToday":5,"day":"2026-11-05"}');
    expect(data.adWallet.canReconcileSpendableDiamondBalance,false);
    expect(data.independentReceiptsAndBalancesVerified,false);
    expect(data.canGrantPurchases,false);
    expect(data.canEraseOriginalPhoneData,false);
    expect(data.allowPhoneCutover,false);
  });
}
