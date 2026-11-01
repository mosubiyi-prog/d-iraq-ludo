import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_secure_pin_preflight.dart';

void main() {
  test('valid phone format and six-digit PIN are enforced for recovery', () {
    expect(DedaSecurePinPreflight.validAccountAndPin('07705551111', '684295'), isTrue);
    expect(DedaSecurePinPreflight.validAccountAndPin('+9647705551111', '684295'), isTrue);
    expect(DedaSecurePinPreflight.validAccountAndPin('07705551111', '000000'), isTrue);
    expect(DedaSecurePinPreflight.validAccountAndPin('07705551111', '12345'), isFalse);
    expect(DedaSecurePinPreflight.validAccountAndPin('07705551111', '1234567'), isFalse);
    expect(DedaSecurePinPreflight.validAccountAndPin('07', '684295'), isFalse);
  });

  final safeReceipt = <String, dynamic>{
    'status': 'PIN_VERIFIED_HOLD',
    'serverOwned': true,
    'productionMigrationEnabled': false,
    'canRestoreAssets': false,
    'canCreditXp': false,
    'canCreditDiamonds': false,
    'canIssueGift': false,
  };
  test('recovery PIN preflight accepts ONLY the server HOLD receipt', () {
    expect(DedaSecurePinPreflight.isHoldOnly(safeReceipt), isTrue);
    for (final key in ['productionMigrationEnabled','canRestoreAssets',
      'canCreditXp','canCreditDiamonds','canIssueGift']) {
      final changed = Map<String, dynamic>.from(safeReceipt)..[key] = true;
      expect(DedaSecurePinPreflight.isHoldOnly(changed), isFalse);
    }
    expect(DedaSecurePinPreflight.isHoldOnly({...safeReceipt,'serverOwned':false}), isFalse);
    expect(DedaSecurePinPreflight.isHoldOnly({...safeReceipt,'status':'ACTIVE'}), isFalse);
    expect(DedaSecurePinPreflight.isHoldOnly(null), isFalse);
    expect(DedaSecurePinPreflight.isHoldOnly('PIN_VERIFIED_HOLD'), isFalse);
  });
}
