/// Account-scoped server projections. No numeric restore into old preferences,
/// reward inference, caller amounts or fallback to an old local wallet.
class DedaMigratedProgress {
  DedaMigratedProgress._(this.account, this.original, this.version,
      this.points, this.coins, this.xp, this.earnedDiamonds,
      this.giftedDiamonds, this.managerDiamonds, this.purchasableDiamonds);
  final String account, original;
  final int version, points, coins, xp, earnedDiamonds, giftedDiamonds;
  final int? managerDiamonds;
  final int purchasableDiamonds;
  static int _amount(Object? value) {
    if (value is! int || value < 0 || value > 9007199254740991) {
      throw const FormatException('invalid-migrated-amount');
    }
    return value;
  }
  static DedaMigratedProgress decode(Object? value, String account, String original) {
    if (value is! Map || value['state'] is! Map || value['originalId'] != original ||
        !RegExp(r'^[0-9]+$').hasMatch(account) ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(original)) {
      throw const FormatException('invalid-migrated-wallet');
    }
    final state = value['state'] as Map;
    const keys = {'format', 'accountKey', 'version', 'balances', 'initializedBy'};
    if (state.length != keys.length || !keys.every(state.containsKey) ||
        state['format'] != 1 || state['accountKey'] != account ||
        state['version'] is! int || (state['version'] as int) < 1 ||
        (state['version'] as int) > 9007199254740991 ||
        state['initializedBy'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(state['initializedBy'] as String) || state['balances'] is! Map) {
      throw const FormatException('invalid-migrated-projection');
    }
    final balances = state['balances'] as Map;
    const units = {'points', 'coins', 'xp', 'earnedDiamonds'};
    if (balances.length != units.length || !units.every(balances.containsKey)) {
      throw const FormatException('invalid-migrated-units');
    }
    final points = _amount(balances['points']), coins = _amount(balances['coins']);
    final xp = _amount(balances['xp']), earned = _amount(balances['earnedDiamonds']);
    final gifted = _amount(value['giftedBalance']);
    final manager = value['managerBalance'] == null ? null : _amount(value['managerBalance']);
    if (!value.containsKey('managerBalance')) throw const FormatException('missing-manager-wallet-status');
    final purchasable = _amount(value['purchasableBalance']);
    if (purchasable != (manager ?? earned + gifted)) {
      throw const FormatException('migrated-wallet-total-conflict');
    }
    return DedaMigratedProgress._(account, original, state['version'] as int,
        points, coins, xp, earned, gifted, manager, purchasable);
  }
}

class DedaMigratedScope {
  const DedaMigratedScope(this.account, this.original, this.principal);
  final String account, original;
  final Object principal;
  bool matches(DedaMigratedScope? other) => other != null && account == other.account &&
      original == other.original && principal == other.principal;
}
abstract class DedaMigratedProgressIo {
  DedaMigratedScope? get current;
  Future<Object?> call(String name, Map<String, Object?> data);
}
class DedaMigratedProgressService {
  DedaMigratedProgressService(this.io);
  final DedaMigratedProgressIo io;
  Future<DedaMigratedProgress> read(String original) => _request(original, null);
  Future<DedaMigratedProgress> purchaseFrame(String original, String frame) => _request(original, frame);
  Future<DedaMigratedProgress> _request(String original, String? frame) async {
    final before = io.current;
    if (before == null || before.original != original) throw StateError('migrated-owner-required');
    void check() {
      if (!before.matches(io.current)) throw StateError('migrated-account-changed');
    }
    check();
    final value = await io.call(frame == null ? 'dedaReadMigratedProgress' : 'dedaPurchaseMigratedFrame',
        frame == null ? const {} : {'frameId': frame});
    check();
    final result = DedaMigratedProgress.decode(value, before.account, original);
    if (frame != null && (value is! Map || value['owned'] != true || value['frameId'] != frame ||
        value['replayed'] is! bool || value['legacyOwned'] is! bool)) {
      throw const FormatException('migrated-purchase-not-confirmed');
    }
    return result;
  }
}
