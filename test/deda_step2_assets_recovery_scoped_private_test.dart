import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_step2_assets_readback.dart';

const account='07712345678';
const uid='original-owner-100436-uid';
const original='@DEDA-ABC123';
const week='2026-11-01';

class StrictAssetsSource implements DedaStep2AssetsIo {
  StrictAssetsSource({this.manager=false});
  final bool manager;
  final List<String> queried=<String>[];

  @override
  Future<DedaStep2CloudDocument> server(String path) async {
    queried.add(path);
    if (path.startsWith('deda_gm_personal_diamond_wallets/')) {
      throw StateError('cross-role-manager-wallet-query-violation');
    }
    if (path=='deda_share_ids/$original') {
      return const DedaStep2CloudDocument({
        'publicId':original,'ownerUid':uid,'kind':'personal','active':true,
      });
    }
    if (path=='deda_account_profiles/$account') {
      return const DedaStep2CloudDocument({
        'accountKey':account,'name':'Existing Owner','accountType':'user',
      });
    }
    if (path=='admin_entry_access/$account') {
      return DedaStep2CloudDocument(manager
          ? const {'accountKey':account,'active':true,'status':'active',
                   'accessType':'general_manager_gateway',
                   'allowedRole':'general_manager'}
          : null);
    }
    if (path=='deda_diamond_gift_balances/$original') {
      return const DedaStep2CloudDocument({'publicId':original,'balance':300});
    }
    if (path=='deda_stage71_active_identifier/$original') {
      return const DedaStep2CloudDocument({
        'originalId':original,'activeId':'@DEDA-QA1234',
      });
    }
    if (path=='deda_weekly_direct_accounts/$original') {
      return const DedaStep2CloudDocument({
        'publicId':original,'accountKey':account,
      });
    }
    if (path=='deda_weekly_direct_weeks/$week/scores/$original') {
      return const DedaStep2CloudDocument({
        'weekId':week,'publicId':original,'weeklyXp':120,
      });
    }
    throw StateError('unexpected-server-read:$path');
  }

  @override
  Future<Set<String>> ownedFrameIds(String originalId) async {
    expect(originalId,original);
    return <String>{};
  }
}

DedaStep2AssetsReadback reader(StrictAssetsSource io) =>
    DedaStep2AssetsReadback(
      io:io,enabled:true,currentUid:()=>uid,
      verifyOriginalOwner:(u,a) async => u==uid && a==account,
    );

void main() {
  test('standard owner reads existing gifts, frames, league without querying GM wallet',
      () async {
    final io=StrictAssetsSource();
    final record=await reader(io).inspect(accountKey:account,
      originalUid:uid,originalId:original,weekId:week,isCurrent:()=>true);
    expect(record.receivedGiftWalletBalance,300);
    expect(record.currentWeeklyXp,120);
    expect(record.activeDisplayId,'@DEDA-QA1234');
    expect(record.managerPersonalBalance,isNull);
    expect(record.fullAccountRestored,false);
    expect(record.canRestoreDiamonds,false);
    expect(io.queried.where((p)=>p.startsWith(
      'deda_gm_personal_diamond_wallets/')),isEmpty);
  });

  test('GM gateway routes to separate admin proof instead of exposing wallet',
      () async {
    final io=StrictAssetsSource(manager:true);
    await expectLater(reader(io).inspect(accountKey:account,
      originalUid:uid,originalId:original,weekId:week,
      isCurrent:()=>true),throwsA(isA<DedaStep2AssetsHold>()));
    expect(io.queried.where((p)=>p.startsWith(
      'deda_gm_personal_diamond_wallets/')),isEmpty);
  });

  test('stale UID blocks assets before any cloud read', () async {
    final io=StrictAssetsSource();
    await expectLater(DedaStep2AssetsReadback(io:io,enabled:true,
      currentUid:()=> 'foreign-uid',
      verifyOriginalOwner:(u,a)async=>true,
    ).inspect(accountKey:account,originalId:original,
      originalUid:uid,weekId:week,isCurrent:()=>true),
      throwsA(isA<DedaStep2AssetsHold>()));
    expect(io.queried,isEmpty);
  });
}
