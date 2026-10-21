import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_qa32_public_recipient_resolver.dart';

void main() {
  const alias = '@DEDA-IRAQI';
  const original = '@DEDA-AQPYXJ';
  test('requires live AppCheck-backed server, never silently uses local ID', () {
    expect(DedaQa32PublicRecipientResolver.enabled, false);
  });
  test('server-confirmed premium ID becomes exactly canonical original', () {
    expect(DedaQa32PublicRecipientResolver.canonicalFromVerifiedReply({
      'requestedId': alias, 'originalId': original, 'serverConfirmed': true
    }, alias), original);
    expect(DedaQa32PublicRecipientResolver.canonicalFromVerifiedReply({
      'requestedId': alias, 'originalId': null, 'serverConfirmed': false
    }, alias), null);
  });
  test('reject spoofed account, malformed server response and false positive', () {
    for (final response in [
      {'requestedId': '@DEDA-BADBAD', 'originalId': original,
          'serverConfirmed': true},
      {'requestedId': alias, 'originalId': original, 'serverConfirmed': false},
      {'requestedId': alias, 'originalId': null, 'serverConfirmed': true},
      {'requestedId': alias, 'originalId': original, 'serverConfirmed': true,
          'ownerUid':'hijack'},
      {'requestedId': alias, 'originalId': '@DEDA-IRAQI',
          'serverConfirmed': true},
    ]) {
      expect(() => DedaQa32PublicRecipientResolver.canonicalFromVerifiedReply(
          response, alias), throwsStateError);
    }
    expect(() => DedaQa32PublicRecipientResolver.canonicalFromVerifiedReply(
        null, alias), throwsStateError);
  });
}
