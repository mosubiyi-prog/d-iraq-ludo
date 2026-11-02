import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:d_iraq_ludo/main.dart' show DedaPreferences, DedaAccountType;
import 'package:d_iraq_ludo/deda_100431_linked_owner_session_policy.dart';

/// Run ONLY with --dart-define=DEDA_STEP2_LINKED_OWNER_COMPAT=true.
/// The normal build remains off. This exercises the actual preference writer,
/// not merely the stateless session policy.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const phone = '+9647712345678';
  const account = '9647712345678';
  const sourceUid = 'original_verified_firebase_uid';

  Future<void> attemptUnverified() =>
      DedaPreferences.saveLogin(
        name: 'اسم من جهاز غير مؤكد',
        normalizedPhone: phone,
        type: DedaAccountType.user,
      );

  test('private QA must have enabled the linked owner pilot for this test', () {
    expect(dedaLinkedOwnerCompatEnabled, isTrue);
  });

  test('phone-only login cannot erase the original UID or overwrite a confirmed profile', () async {
    SharedPreferences.setMockInitialValues({
      'deda_logged_in_v1': false,
      'deda_user_name_v1': 'الاسم المؤكد السابق',
      'deda_phone_v1': phone,
      'deda_account_phone_v1': phone,
      'deda_account_type_v1': 'placeOwner',
      'deda_step2_linked_verified_uid_v1': sourceUid,
      'deda_step2_linked_verified_account_v1': account,
    });
    final prefs = await SharedPreferences.getInstance();
    await expectLater(attemptUnverified(),
        throwsA(isA<StateError>().having(
          (e) => e.toString(), 'reason',
          contains('linked-owner-requires-verified-login-or-logout'))));
    expect(prefs.getString('deda_step2_linked_verified_uid_v1'), sourceUid);
    expect(prefs.getString('deda_step2_linked_verified_account_v1'), account);
    expect(prefs.getString('deda_user_name_v1'), 'الاسم المؤكد السابق');
    expect(prefs.getString('deda_account_type_v1'), 'placeOwner');
    expect(prefs.getBool('deda_logged_in_v1'), isFalse);
  });

  test('original phone persists UID on first link and a retry does not replace it', () async {
    SharedPreferences.setMockInitialValues({});
    final live = () => true;
    await DedaLinkedOwnerSessionPolicy.rememberConfirmedOriginalUid(
      accountKey: account, uid: sourceUid, isCurrent: live,
    );
    await DedaLinkedOwnerSessionPolicy.rememberConfirmedOriginalUid(
      accountKey: account, uid: sourceUid, isCurrent: live,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('deda_step2_linked_verified_uid_v1'),sourceUid);
    expect(prefs.getString('deda_step2_linked_verified_account_v1'),account);
    await expectLater(DedaLinkedOwnerSessionPolicy.rememberConfirmedOriginalUid(
      accountKey: account, uid:'foreign_uid', isCurrent: live,
    ),throwsStateError);
    expect(prefs.getString('deda_step2_linked_verified_uid_v1'),sourceUid);
  });

  test('expired original owner intent cannot create local proof', () async {
    SharedPreferences.setMockInitialValues({});
    await expectLater(DedaLinkedOwnerSessionPolicy.rememberConfirmedOriginalUid(
      accountKey: account, uid: sourceUid, isCurrent: () => false,
    ),throwsStateError);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('deda_step2_linked_verified_uid_v1'),false);
    expect(prefs.containsKey('deda_step2_linked_verified_account_v1'),false);
  });

  test('sign out clears active session but keeps protected account guard', () async {
    SharedPreferences.setMockInitialValues({
      'deda_logged_in_v1': true,
      'deda_user_name_v1': 'الاسم المؤكد',
      'deda_phone_v1': phone,
      'deda_account_phone_v1': phone,
      'deda_account_type_v1': 'user',
    });
    await DedaLinkedOwnerSessionPolicy.rememberConfirmedOriginalUid(
      accountKey: account, uid: sourceUid, isCurrent: () => true,
    );
    await DedaPreferences.logout();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('deda_logged_in_v1'), isFalse);
    expect(prefs.containsKey('deda_step2_linked_verified_uid_v1'), isFalse);
    expect(prefs.containsKey('deda_step2_linked_verified_account_v1'), isFalse);
    expect(prefs.getString('deda_step2_verified_owner_guard_v1_$account'), sourceUid);
    // A second phone/name-only login must not defeat explicit sign-out.
    await expectLater(attemptUnverified(), throwsStateError);
    expect(prefs.getString('deda_step2_verified_owner_guard_v1_$account'), sourceUid);
  });

  test('a guard-only interrupted linked login also blocks phone-only takeover', () async {
    SharedPreferences.setMockInitialValues({
      'deda_logged_in_v1': false,
      'deda_step2_verified_owner_guard_v1_$account': sourceUid,
    });
    await expectLater(attemptUnverified(), throwsStateError);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('deda_step2_verified_owner_guard_v1_$account'), sourceUid);
    expect(prefs.getBool('deda_logged_in_v1'), isFalse);
  });

  test('even a torn/partial confirmed UID proof cannot be downgraded', () async {
    for (final partial in <Map<String, Object>>[
      {'deda_step2_linked_verified_uid_v1': sourceUid},
      {'deda_step2_linked_verified_account_v1': account},
    ]) {
      SharedPreferences.setMockInitialValues({
        'deda_logged_in_v1': false,
        'deda_user_name_v1': 'صاحب الحساب',
        ...partial,
      });
      await expectLater(attemptUnverified(), throwsStateError);
      final prefs = await SharedPreferences.getInstance();
      for (final item in partial.entries) {
        expect(prefs.get(item.key), item.value);
      }
      expect(prefs.getBool('deda_logged_in_v1'), isFalse);
      expect(prefs.getString('deda_user_name_v1'), 'صاحب الحساب');
    }
  });
}
