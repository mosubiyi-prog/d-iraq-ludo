import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_100431_linked_owner_session_policy.dart';

const account = '9647712345678';
const uid = 'original-account-uid';
const original = '@DEDA-ABC123';

void main() {
  test('100441 source explicitly enables linked-owner PIN safety opt-in', () {
    expect(dedaLinkedOwnerCompatEnabled, isTrue);
  });

  test('PIN session cannot be associated with new anonymous or split UID', () {
    bool valid(String principal, String registered, String routed) =>
        DedaLinkedOwnerSessionPolicy.canOpenExistingPinSessionOnOriginalUid(
          uid: principal, accountKey: account,
          directory: <String, Object>{
            'accountKey': account, 'active': true, 'createdUid': registered,
          },
          projection: <String, Object>{
            'accountKey': account, 'sharePersonalId': original,
          },
          route: <String, Object>{
            'publicId': original, 'kind': 'personal', 'active': true,
            'ownerUid': routed,
          },
        );

    expect(valid(uid, uid, uid), isTrue);
    expect(valid('new-anonymous-uid', uid, uid), isFalse);
    expect(valid(uid, 'directory-second-uid', uid), isFalse);
    expect(valid(uid, uid, 'personal-id-third-uid'), isFalse);
  });
}
