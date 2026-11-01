import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_free_firestore_recovery_hold.dart';

void main() {
  test('original ID format is canonical, not arbitrary premium alias', () {
    expect(DedaFreeFirestoreRecoveryHold.validOriginal('@DEDA-AB3C5D'), isTrue);
    for (final bad in ['', '@DEDA-ab3c5d', '@DEDA-TOO-LONG',
                       '@DEDA-12345', '@DEDA-1234567', '123456']) {
      expect(DedaFreeFirestoreRecoveryHold.validOriginal(bad), isFalse);
    }
  });
  test('account key must be a clean numeric account key', () {
    expect(DedaFreeFirestoreRecoveryHold.validAccount('07705551111'), isTrue);
    expect(DedaFreeFirestoreRecoveryHold.validAccount('9647705551111'), isTrue);
    expect(DedaFreeFirestoreRecoveryHold.validAccount('+9647705551111'), isFalse);
  });
  const account = '07705551111';
  const original = '@DEDA-AB3C5D';
  const source = 'original-firebase-uid';
  const freshUid = 'new-firebase-uid';
  final anchor = <String, dynamic>{
    'accountKey': account, 'sourceUid': source, 'originalId': original,
  };
  test('new phone uses server-stored canonical original; never a local alias', () {
    expect(DedaFreeFirestoreRecoveryHold.validAnchor(anchor,account), isTrue);
    expect(DedaFreeFirestoreRecoveryHold.validAnchor(
      {...anchor,'accountKey':'other-account'},account), isFalse);
    expect(DedaFreeFirestoreRecoveryHold.validAnchor(
      {...anchor,'sourceUid':''},account), isFalse);
    expect(DedaFreeFirestoreRecoveryHold.validAnchor(
      {...anchor,'originalId':'@DEDA-TOO-LONG'},account), isFalse);
  });
  final hold = <String, dynamic>{
    'uid':freshUid,'accountKey':account,'originalId':original,
    'sourceUid':source,'status':'PIN_PROVED_HOLD',
    'canRestoreAssets':false,'canMigrate':false,'canCreditXp':false,
    'canCreditDiamonds':false,'canIssueGift':false,
  };
  test('hold is strict with no financial or ownership access', () {
    expect(DedaFreeFirestoreRecoveryHold.isHoldOnly(
      hold,freshUid,account,original,source),isTrue);
    for(final property in ['canRestoreAssets','canMigrate',
                           'canCreditXp','canCreditDiamonds','canIssueGift']) {
      expect(DedaFreeFirestoreRecoveryHold.isHoldOnly(
        {...hold,property:true},freshUid,account,original,source),isFalse);
    }
    expect(DedaFreeFirestoreRecoveryHold.isHoldOnly(
      {...hold,'uid':source},freshUid,account,original,source),isFalse);
    expect(DedaFreeFirestoreRecoveryHold.isHoldOnly(
      {...hold,'originalId':'@DEDA-ZZ9999'},freshUid,account,original,source),
      isFalse);
  });
}
