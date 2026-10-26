import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_migrated_progress.dart';

const account = '07700000000', original = '@DEDA-ABC234';
Map<String, Object?> wallet() => {
  'state': {'format': 1, 'accountKey': account, 'version': 2,
    'initializedBy': List.filled(64, 'a').join(),
    'balances': <String, Object?>{'points': 1000, 'coins': 30, 'xp': 20, 'earnedDiamonds': 9}},
  'originalId': original, 'giftedBalance': 991, 'managerBalance': null, 'purchasableBalance': 1000,
};
class Io implements DedaMigratedProgressIo {
  @override DedaMigratedScope? current = const DedaMigratedScope(account, original, ('uid', 1));
  final calls = <(String, Map<String, Object?>)>[];
  Object? response = wallet();
  Future<Object?> Function()? action;
  @override Future<Object?> call(String name, Map<String, Object?> data) async {
    calls.add((name, Map.of(data)));
    return action == null ? response : await action!();
  }
}
void main() {
  test('server wallet keeps all four units separate from gifts and manager diamonds', () async {
    final io = Io(), result = await DedaMigratedProgressService(Io()).read(original);
    expect(result.points, 1000); expect(result.coins, 30); expect(result.xp, 20);
    expect(result.earnedDiamonds, 9); expect(result.giftedDiamonds, 991);
    expect(result.managerDiamonds, isNull); expect(result.purchasableDiamonds, 1000);
    await DedaMigratedProgressService(io).read(original);
    expect(io.calls, hasLength(1));
    expect(io.calls.single.$1, 'dedaReadMigratedProgress');
    expect(io.calls.single.$2, isEmpty);
  });
  test('manager wallet remains exclusive and is never added to ordinary funds', () async {
    final io = Io()..response = {...wallet(), 'managerBalance': 999000, 'purchasableBalance': 999000};
    final result = await DedaMigratedProgressService(io).read(original);
    expect(result.earnedDiamonds, 9); expect(result.giftedDiamonds, 991);
    expect(result.managerDiamonds, 999000); expect(result.purchasableDiamonds, 999000);
  });
  for (final defect in ['missing-state', 'foreign-account', 'foreign-original', 'negative', 'fraction', 'missing-unit', 'wrong-total', 'missing-manager']) {
    test('invalid $defect cannot produce zero or a local fallback', () async {
      final value = wallet(), state = value['state']! as Map<String, Object?>;
      final balances = state['balances']! as Map<String, Object?>;
      if (defect == 'missing-state') value.remove('state');
      if (defect == 'foreign-account') state['accountKey'] = '07700000001';
      if (defect == 'foreign-original') value['originalId'] = '@DEDA-OTHER1';
      if (defect == 'negative') balances['earnedDiamonds'] = -1;
      if (defect == 'fraction') balances['xp'] = 1.5;
      if (defect == 'missing-unit') balances.remove('coins');
      if (defect == 'wrong-total') value['purchasableBalance'] = 1000000;
      if (defect == 'missing-manager') value.remove('managerBalance');
      final io = Io()..response = value;
      await expectLater(DedaMigratedProgressService(io).read(original), throwsFormatException);
    });
  }
  for (final next in [null, const DedaMigratedScope(account, original, ('other-uid', 2)),
      const DedaMigratedScope(account, original, ('uid', 3))]) {
    test('delayed response cannot cross logout, UID rotation or A to B to A epoch', () async {
      final io = Io(), pending = Completer<Object?>(); io.action = () => pending.future;
      final result = DedaMigratedProgressService(io).read(original);
      io.current = next; pending.complete(wallet());
      await expectLater(result, throwsStateError); expect(io.calls, hasLength(1));
    });
  }
  test('transport failure remains visible and is never retried or converted into a balance', () async {
    final io = Io()..action = () async => throw StateError('offline');
    await expectLater(DedaMigratedProgressService(io).read(original), throwsStateError);
    expect(io.calls, hasLength(1));
  });
  test('purchase sends only stable frame ID and accepts only confirmed same-owner response', () async {
    final io = Io()..response = {...wallet(), 'frameId': 'FRAME_03', 'owned': true,
      'replayed': false, 'legacyOwned': false};
    await DedaMigratedProgressService(io).purchaseFrame(original, 'FRAME_03');
    expect(io.calls, hasLength(1));
    expect(io.calls.single.$1, 'dedaPurchaseMigratedFrame');
    expect(io.calls.single.$2, {'frameId': 'FRAME_03'});
    io.response = {...wallet(), 'frameId': 'FRAME_05', 'owned': true, 'replayed': false, 'legacyOwned': false};
    await expectLater(DedaMigratedProgressService(io).purchaseFrame(original, 'FRAME_03'), throwsFormatException);
  });
  test('missing owner and foreign original dispatch nothing', () async {
    final io = Io()..current = null;
    await expectLater(DedaMigratedProgressService(io).read(original), throwsStateError);
    expect(io.calls, isEmpty);
    io.current = const DedaMigratedScope(account, original, ('uid', 1));
    await expectLater(DedaMigratedProgressService(io).read('@DEDA-OTHER1'), throwsStateError);
    expect(io.calls, isEmpty);
  });
}
