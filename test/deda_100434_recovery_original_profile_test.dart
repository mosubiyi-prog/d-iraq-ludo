import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_100430_owner_uid_continuity.dart';

void main() {
  const account = '07712345678';

  test('Recovered name comes from scoped server profile, never a typed alias', () {
    final name = DedaOwnerUidContinuity.validatedServerProfileName(
      {'accountKey': account, 'name': '  صاحب الحساب الأصلي  '},
      accountKey: account,
    );
    expect(name, 'صاحب الحساب الأصلي');
    expect(name, isNot('اسم جديد كتبه شخص في الهاتف الثاني'));
  });

  test('Recovery refuses profiles for other phone accounts', () {
    expect(
      () => DedaOwnerUidContinuity.validatedServerProfileName(
        {'accountKey': '07700000000', 'name': 'Other'},
        accountKey: account,
      ),
      throwsStateError,
    );
  });

  test('Linked recovery restores original role only from matched server account', () {
    expect(
      DedaOwnerUidContinuity.validatedServerAccountType(
        {'accountKey': account, 'accountType': 'user'}, accountKey: account,
      ),
      'user',
    );
    expect(
      DedaOwnerUidContinuity.validatedServerAccountType(
        {'accountKey': account, 'accountType': 'placeOwner'},
        accountKey: account,
      ),
      'placeOwner',
    );
  });

  test('A stale local owner role cannot be adopted from missing or foreign data', () {
    for (final profile in <Map<String, dynamic>?>[
      null,
      {'accountKey': account},
      {'accountKey': account, 'accountType': 'admin'},
      {'accountKey': account, 'accountType': 'general_manager'},
      {'accountKey': account, 'accountType': ''},
      {'accountKey': '07700000000', 'accountType': 'placeOwner'},
    ]) {
      expect(
        () => DedaOwnerUidContinuity.validatedServerAccountType(
          profile, accountKey: account,
        ),
        throwsStateError,
      );
    }
  });

  test('Recovery refuses absent, empty, invalid and oversized profile names', () {
    for (final profile in <Map<String, dynamic>?>[
      null,
      <String, dynamic>{'accountKey': account},
      {'accountKey': account, 'name': null},
      {'accountKey': account, 'name': 123},
      {'accountKey': account, 'name': ''},
      {'accountKey': account, 'name': '  '},
      {'accountKey': account, 'name': 'A'},
      {'accountKey': account, 'name': List<String>.filled(101, 'N').join()},
    ]) {
      expect(
        () => DedaOwnerUidContinuity.validatedServerProfileName(
          profile, accountKey: account,
        ),
        throwsStateError,
      );
    }
  });
}
