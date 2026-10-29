import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_second_phone_link_client.dart';
import 'package:d_iraq_ludo/deda_session_transition_gate.dart';

Map<String, dynamic> safeReply({bool replayed = false}) => {
  'status': 'ACCOUNT_LINKED_READONLY_EMULATOR_ONLY',
  'replayed': replayed,
  'emulatorOnly': true,
  'verifiedProgress': {
    'format': 1, 'version': 3, 'points': 25, 'coins': 10,
    'xp': 125, 'earnedDiamonds': 200,
    'spendable': false, 'entitlementsVerified': false,
  },
  'canRestoreFinancialBalances': false,
  'canCreditXp': false,
  'canCreditDiamonds': false,
  'canRestoreFrames': false,
  'canRestorePremiumId': false,
  'canIssueLeagueGift': false,
  'productionReady': false,
};

class _Transport implements DedaSecondPhoneLinkTransport {
  @override
  String? currentUid = 'emulator-second-phone-uid';
  @override
  bool isAnonymous = true;
  @override
  bool emulatorConfigured = true;
  int calls = 0;
  Map<String, dynamic> reply = safeReply();
  Completer<Map<String, dynamic>>? pending;
  @override
  Future<Map<String, dynamic>> linkWithoutClientAccountDetails() async {
    calls++;
    if (pending != null) return await pending!.future;
    return reply;
  }
}

void main() {
  test('verified QA link uses only server-derived account, no client amount', () async {
    final t = _Transport(), client = DedaSecondPhoneLinkClient(t);
    expect(await client.link(isCurrent: () => true),
        DedaSecondPhoneLinkStatus.linkedAwaitingSettlement);
    expect(t.calls, 1);
    t.reply = safeReply(replayed: true);
    expect(await client.link(isCurrent: () => true),
        DedaSecondPhoneLinkStatus.alreadyLinkedAwaitingSettlement);
    expect(t.calls, 2);
  });

  test('new phone reads server-reconciled XP and diamonds only as a nonspendable snapshot', () async {
    final t = _Transport(), client = DedaSecondPhoneLinkClient(t);
    final result = await client.linkAndReadVerifiedProgress(isCurrent: () => true);
    expect(result.status, DedaSecondPhoneLinkStatus.linkedAwaitingSettlement);
    expect(result.progress.version, 3);
    expect(result.progress.xp, 125);
    expect(result.progress.earnedDiamonds, 200);
    expect(result.progress.points, 25);
    expect(result.progress.coins, 10);
    expect(t.calls, 1);
  });

  test('replay never accepts forged, zeroed, spendable or oversized server balances', () async {
    final t = _Transport(), client = DedaSecondPhoneLinkClient(t);
    for (final bad in [
      {'earnedDiamonds': -1},
      {'xp': -25},
      {'xp': '9999'},
      {'points': null},
      {'version': 0},
      {'earnedDiamonds': 9007199254740992},
      {'spendable': true},
      {'entitlementsVerified': true},
      {'bonusFreeDiamonds': 30000},
    ]) {
      t.reply = {...safeReply(),
        'verifiedProgress': {...safeReply()['verifiedProgress'] as Map, ...bad}};
      await expectLater(client.linkAndReadVerifiedProgress(isCurrent: () => true),
          throwsFormatException);
    }
  });

  test('default pilot remains off for real users', () {
    expect(dedaPrivateSecondPhoneLinkEmulatorPilot, isFalse);
  });

  test('no emulator connection or anonymous identity blocks network call', () async {
    final t = _Transport(), client = DedaSecondPhoneLinkClient(t);
    t.emulatorConfigured = false;
    await expectLater(client.link(isCurrent: () => true), throwsStateError);
    t.emulatorConfigured = true;
    t.isAnonymous = false;
    await expectLater(client.link(isCurrent: () => true),
        throwsA(isA<DedaStaleSessionTransition>()));
    t.isAnonymous = true;
    t.currentUid = null;
    await expectLater(client.link(isCurrent: () => true),
        throwsA(isA<DedaStaleSessionTransition>()));
    expect(t.calls, 0);
  });

  test('stale account selection denies call before or after roundtrip', () async {
    final t = _Transport(), client = DedaSecondPhoneLinkClient(t);
    await expectLater(client.link(isCurrent: () => false),
        throwsA(isA<DedaStaleSessionTransition>()));
    expect(t.calls, 0);
    t.pending = Completer<Map<String, dynamic>>();
    final request = client.link(isCurrent: () => true);
    t.currentUid = 'another-account';
    t.pending!.complete(safeReply());
    await expectLater(request, throwsA(isA<DedaStaleSessionTransition>()));
  });

  test('replayed server proof must not invent frame, diamond, ID or XP grant', () async {
    final t = _Transport(), client = DedaSecondPhoneLinkClient(t);
    final cases = <Map<String, dynamic>>[
      {...safeReply(), 'canCreditDiamonds': true},
      {...safeReply(), 'canCreditXp': true},
      {...safeReply(), 'canRestoreFrames': true},
      {...safeReply(), 'canRestorePremiumId': true},
      {...safeReply(), 'canIssueLeagueGift': true},
      {...safeReply(), 'productionReady': true},
      {...safeReply(), 'emulatorOnly': false},
      {...safeReply(), 'accountKey': '07701234567'},
      {...safeReply(), 'replayed': 'yes'},
    ];
    for (final payload in cases) {
      t.reply = payload;
      await expectLater(client.link(isCurrent: () => true),
          throwsFormatException);
    }
  });

  test('unavailable callable never silently marks account as linked', () async {
    final t = _Transport(), client = DedaSecondPhoneLinkClient(t);
    t.pending = Completer<Map<String, dynamic>>();
    final request = client.link(isCurrent: () => true);
    t.pending!.completeError(StateError('SERVER_UNAVAILABLE'));
    await expectLater(request, throwsStateError);
  });
}
