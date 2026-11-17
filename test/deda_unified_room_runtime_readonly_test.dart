import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_unified_room_runtime_readonly.dart';

Map<String, dynamic> approval(String domain, Map<String, dynamic> payload) =>
    <String, dynamic>{
      'status': 'VERIFIED_READ_ONLY',
      'authorized': true,
      'domain': domain,
      'payload': payload,
      'accountRestored': false,
      'financialRestore': false,
      'uidChanged': false,
    };

void main() {
  test('production read-only room is OFF by default; never attempts Firebase', () async {
    expect(dedaUnifiedRoomReadOnlyEnabled, isFalse);
    final result = await DedaUnifiedRoomRuntimeReadOnly.readDomain('profile');
    expect(result.status, 'HOLD');
    expect(result.payload, isNull);
    for (final domain in <String>['original_id', 'friends', 'league', 'premium_id']) {
      final held = await DedaUnifiedRoomRuntimeReadOnly.readDomain(domain);
      expect(held.status, 'HOLD', reason: domain);
      expect(held.payload, isNull);
    }
    final invalid = await DedaUnifiedRoomRuntimeReadOnly.readDomain('admin');
    expect(invalid.status, 'HOLD');
    expect(DedaUnifiedRoomRuntimeReadOnly.homeSectionDomains,
      <String>['profile', 'original_id', 'premium_id', 'friends', 'league']);
    expect(await DedaUnifiedRoomRuntimeReadOnly.readHomeSections(), isEmpty);
    await DedaUnifiedRoomRuntimeReadOnly.preflightOnHome();
  });

  test('eight sanitized scoped replies can be parsed, never restore account', () {
    const examples = <String, Map<String, dynamic>>{
      'profile': {'displayName': 'DEDA user', 'level': 12},
      'original_id': {'publicId': '@DEDA-ABC123'},
      'premium_id': {'displayId': '@DEDA-1234', 'color': 'gold'},
      'friends': {'friendCount': 4},
      'league': {'weeklyPoints': 40},
      'gifts': {'giftCount': 3},
      'wallet': {'balanceDisplay': 80, 'giftWalletBalance': 10},
      'places': {'publishedPlaceCount': 2},
    };
    for (final entry in examples.entries) {
      final result = DedaUnifiedRoomRuntimeReadOnly.acceptServerReply(
          entry.key, approval(entry.key, entry.value));
      expect(result.verifiedReadOnly, isTrue, reason: entry.key);
      expect(result.payload, entry.value);
      expect(() => result.payload!['level'] = 0, throwsUnsupportedError);
    }
  });

  test('malicious historical UID, token, phone or PIN in payload is HOLD', () {
    final response = approval('profile', <String, dynamic>{
      'displayName': 'A',
      'sourceUid': 'QA_HISTORIC_A',
    });
    final parsed = DedaUnifiedRoomRuntimeReadOnly.acceptServerReply(
        'profile', response);
    expect(parsed.status, 'HOLD');
    expect(parsed.payload, isNull);
  });

  test('missing or conflicting balance must not overwrite local diamonds', () {
    for (final value in <dynamic>[-1, null, '500', 1.5, 1000000001]) {
      final response = approval('wallet', <String, dynamic>{
        'balanceDisplay': value,
      });
      expect(DedaUnifiedRoomRuntimeReadOnly.acceptServerReply(
          'wallet', response).verifiedReadOnly, isFalse);
    }
  });

  test('one signed profile reply cannot open friends or arbitrary scope', () {
    expect(DedaUnifiedRoomRuntimeReadOnly.acceptServerReply(
      'friends', approval('profile', <String, dynamic>{
        'displayName': 'A',
      }),
    ).status, 'HOLD');
    expect(DedaUnifiedRoomRuntimeReadOnly.acceptServerReply(
      'admin', approval('admin', <String, dynamic>{'displayName': 'A'}),
    ).status, 'HOLD');
  });

  test('no successful restore, award or UID change may be announced', () {
    for (final claimed in <String>[
      'accountRestored', 'financialRestore', 'uidChanged',
    ]) {
      final response=approval('profile', <String, dynamic>{
        'displayName': 'A',
      });
      response[claimed] = true;
      expect(DedaUnifiedRoomRuntimeReadOnly.acceptServerReply(
          'profile', response).status, 'HOLD', reason: claimed);
    }
  });

  test('HOLD and absent proof have no payload or fake defaults', () {
    final response=approval('profile', <String, dynamic>{'level': 5});
    response['authorized'] = false;
    final result=DedaUnifiedRoomRuntimeReadOnly.acceptServerReply(
        'profile', response);
    expect(result.status, 'HOLD');
    expect(result.payload, isNull);
    expect(result.domain, isNull);
  });

  test('premium ID format and color are validated independently', () {
    final response=approval('premium_id', <String, dynamic>{
      'displayId': '@DEDA-NOT-REAL', 'color': 'gold',
    });
    expect(DedaUnifiedRoomRuntimeReadOnly.acceptServerReply(
        'premium_id', response).status, 'HOLD');
    final mismatched=approval('premium_id', <String, dynamic>{
      'displayId': '@DEDA-1234', 'color': 'unknown',
    });
    expect(DedaUnifiedRoomRuntimeReadOnly.acceptServerReply(
        'premium_id', mismatched).status, 'HOLD');
  });
}
