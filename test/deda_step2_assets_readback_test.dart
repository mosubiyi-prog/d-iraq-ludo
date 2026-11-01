import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_step2_assets_readback.dart';

const account = '07712345678';
const uid = 'original-owner-uid';
const original = '@DEDA-ABC123';
const week = '2026-11-01';

class AssetsIo implements DedaStep2AssetsIo {
  final Map<String, DedaStep2CloudDocument> docs = {};
  final frames = <String>{'FRAME_03','FRAME_16'};
  final calls = <String>[];
  bool brokenFrames = false;

  AssetsIo() {
    docs.addAll({
      'deda_share_ids/$original': DedaStep2CloudDocument({
        'publicId': original, 'ownerUid': uid,
        'kind': 'personal', 'active': true,
      }),
      'deda_account_profiles/$account': DedaStep2CloudDocument({
        'accountKey': account, 'name': 'Original User',
        'accountType': 'user',
      }),
      'deda_diamond_gift_balances/$original': DedaStep2CloudDocument({
        'publicId': original, 'balance': 725,
      }),
      'deda_stage71_active_identifier/$original': DedaStep2CloudDocument({
        'originalId': original, 'activeId': '@DEDA-VIP123',
      }),
      'deda_weekly_direct_accounts/$original': DedaStep2CloudDocument({
        'accountKey': account, 'publicId': original,
      }),
      'deda_weekly_direct_weeks/$week/scores/$original':
          DedaStep2CloudDocument({
        'publicId': original, 'weekId': week, 'weeklyXp': 120,
      }),
    });
  }

  @override
  Future<DedaStep2CloudDocument> server(String path) async {
    calls.add(path);
    return docs[path] ?? const DedaStep2CloudDocument(null);
  }

  @override
  Future<Set<String>> ownedFrameIds(String originalId) async {
    calls.add('strict-owned-frames/$originalId');
    if (brokenFrames) throw StateError('partial-frame-receipt');
    return frames;
  }
}

class Harness {
  final io = AssetsIo();
  String live = uid;
  bool current = true, proof = true;
  late final service = DedaStep2AssetsReadback(
    io: io,
    currentUid: () => live,
    verifyOriginalOwner: (u, a) async =>
        proof && u == uid && a == account,
    enabled: true,
  );

  Future<DedaStep2AssetsEvidence> read() => service.inspect(
    accountKey: account, originalId: original, originalUid: uid,
    weekId: week, isCurrent: () => current,
  );
}

void main() {
  test('same verified original owner reads 13-frame subset and distinct wallets', () async {
    final h = Harness();
    final evidence = await h.read();
    expect(evidence.accountName, 'Original User');
    expect(evidence.verifiedPaidFrameIds, {'FRAME_03','FRAME_16'});
    expect(evidence.receivedGiftWalletBalance, 725);
    expect(evidence.managerPersonalBalance, isNull);
    expect(evidence.activeDisplayId, '@DEDA-VIP123');
    expect(evidence.currentWeeklyXp, 120);
    expect(evidence.fullAccountRestored, isFalse);
    expect(evidence.canRestoreDiamonds, isFalse);
    expect(evidence.canReissueWeeklyPrizes, isFalse);
    expect(evidence.canReissueGifts, isFalse);
    expect(evidence.canTransferPurchasedFrames, isFalse);
    expect(evidence.canActivatePremiumId, isFalse);
    expect(evidence.serverSources.keys, containsAll([
      'xpAndLevel','earnedDiamonds','receivedGiftsAndHadaya',
      'premiumGrants','friends','savedPlaces','publishedPlaces','settings',
      'dailyTasks','trafficQuestions','historicalLeaguePrizes',
    ]));
    expect(h.io.calls.length, greaterThanOrEqualTo(8));
  });

  test('repeat read has no write or reward behavior', () async {
    final h = Harness();
    final first = await h.read();
    final second = await h.read();
    expect(first.receivedGiftWalletBalance, second.receivedGiftWalletBalance);
    expect(first.verifiedPaidFrameIds, second.verifiedPaidFrameIds);
  });

  test('missing gift wallet is UNKNOWN not zero and never spendable', () async {
    final h = Harness();
    h.io.docs.remove('deda_diamond_gift_balances/$original');
    final e = await h.read();
    expect(e.receivedGiftWalletBalance, isNull);
    expect(e.serverSources['receivedGiftWallet'], contains('unknown'));
    expect(e.canRestoreDiamonds, isFalse);
  });

  test('missing premium active selection cannot revoke or grant ownership', () async {
    final h = Harness();
    h.io.docs.remove('deda_stage71_active_identifier/$original');
    final e = await h.read();
    expect(e.activeDisplayId, isNull);
    expect(e.canActivatePremiumId, isFalse);
  });

  test('strict frame service partial receipt failure blocks complete inventory', () async {
    final h = Harness();
    h.io.brokenFrames = true;
    await expectLater(h.read(), throwsStateError);
  });

  test('unknown frame ID cannot be smuggled into a legitimate owned set', () async {
    final h = Harness();
    h.io.frames.add('FRAME_99');
    await expectLater(h.read(), throwsA(isA<DedaStep2AssetsHold>()));
  });

  test('cache, pending write and wrong route block without reading wallet', () async {
    for (final changed in [
      const DedaStep2CloudDocument(null, isFromCache: true),
      const DedaStep2CloudDocument(null, hasPendingWrites: true),
      const DedaStep2CloudDocument({
        'publicId': original, 'kind': 'personal',
        'ownerUid': 'other-person', 'active': true,
      }),
    ]) {
      final h = Harness();
      h.io.docs['deda_share_ids/$original'] = changed;
      await expectLater(h.read(), throwsA(isA<DedaStep2AssetsHold>()));
      expect(h.io.calls, ['deda_share_ids/$original']);
    }
  });

  test('wrong UID, unproven original and stale session fail before reads', () async {
    for (final setting in ['uid','proof','stale']) {
      final h = Harness();
      if (setting == 'uid') h.live = 'someone-else';
      if (setting == 'proof') h.proof = false;
      if (setting == 'stale') h.current = false;
      await expectLater(h.read(), throwsA(isA<DedaStep2AssetsHold>()));
      expect(h.io.calls, isEmpty);
    }
  });

  test('rejected malformed wallet and overflow never become displayed zero', () async {
    for (final value in <Object>[-1, '500', 9007199254740992]) {
      final h = Harness();
      h.io.docs['deda_diamond_gift_balances/$original'] =
          DedaStep2CloudDocument({
        'publicId': original, 'balance': value,
      });
      await expectLater(h.read(), throwsA(isA<DedaStep2AssetsHold>()));
    }
  });

  test('manager is a separate pool not ordinary gift money', () async {
    final h = Harness();
    h.io.docs['admin_entry_access/$account'] = const DedaStep2CloudDocument({
      'active': true, 'status': 'active',
      'accessType': 'general_manager_gateway',
      'allowedRole': 'general_manager',
    });
    h.io.docs['deda_gm_personal_diamond_wallets/$account'] =
        const DedaStep2CloudDocument({
      'accountKey': account, 'balance': 1000000,
      'initialBalance': 1000000,
    });
    final e = await h.read();
    expect(e.receivedGiftWalletBalance, 725);
    expect(e.managerPersonalBalance, 1000000);
    expect(e.canRestoreDiamonds, isFalse);
  });

  test('manager wallet without full server gate is refused', () async {
    final h = Harness();
    h.io.docs['deda_gm_personal_diamond_wallets/$account'] =
        const DedaStep2CloudDocument({
      'accountKey': account, 'balance': 1000000,
      'initialBalance': 1000000,
    });
    await expectLater(h.read(), throwsA(isA<DedaStep2AssetsHold>()));
  });

  test('wrong week score owner cannot generate fresh points', () async {
    final h = Harness();
    h.io.docs['deda_weekly_direct_weeks/$week/scores/$original'] =
      const DedaStep2CloudDocument({
        'publicId': '@DEDA-OTHER1', 'weekId': week, 'weeklyXp': 900,
      });
    await expectLater(h.read(), throwsA(isA<DedaStep2AssetsHold>()));
  });

  test('feature is off by default and cannot read assets', () async {
    final h = Harness();
    final disabled = DedaStep2AssetsReadback(
      io: h.io, currentUid: () => uid,
      verifyOriginalOwner: (u, key) async => true,
      enabled: false,
    );
    await expectLater(
      disabled.inspect(accountKey: account, originalId: original,
        originalUid: uid, weekId: week, isCurrent: () => true),
      throwsA(isA<DedaStep2AssetsHold>()),
    );
    expect(h.io.calls, isEmpty);
  });

  test('invalid week or display alias cannot authorize asset read', () async {
    final h = Harness();
    await expectLater(h.service.inspect(accountKey: account,
      originalId: '@DEDA-VIP123', originalUid: uid,
      weekId: week, isCurrent: () => true),
      throwsA(isA<DedaStep2AssetsHold>()));
    await expectLater(h.service.inspect(accountKey: account,
      originalId: original, originalUid: uid,
      weekId: '2026-99-99-INVALID', isCurrent: () => true),
      throwsA(isA<DedaStep2AssetsHold>()));
    // A premium-looking value may have the same six-character syntax as an
    // original ID. The immutable server route still rejects it, and the
    // malformed week never triggers another read.
    expect(h.io.calls, ['deda_share_ids/@DEDA-VIP123']);
  });
}
