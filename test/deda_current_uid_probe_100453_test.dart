import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_current_uid_probe_100453.dart';
import 'package:d_iraq_ludo/deda_session_diagnostic_readonly_100441.dart';

void main() {
  test('feature stays OFF by default; no production settings control', () {
    expect(dedaCurrentUidProbe100453Qa, isFalse);
  });

  test('a live Firebase UID is classified but never returned raw', () {
    const uid = 'QA_EXISTING_A_OR_B_OR_C_UID_2026';
    final first = DedaCurrentUidProbe100453.classify(
      firebaseReady: true, uid: uid, isAnonymous: true);
    expect(first.kind, DedaCurrentUidProbeKind.anonymous);
    expect(first.fingerprint, matches(RegExp(r'^[0-9A-F]{16}$')));
    expect(first.fingerprint, isNot(contains(uid)));
    expect(first.fingerprint,
      DedaSessionDiagnosticReadOnly.fingerprintOfUid(uid));
    final second = DedaCurrentUidProbe100453.classify(
      firebaseReady: true, uid: uid, isAnonymous: false);
    expect(second.kind, DedaCurrentUidProbeKind.linked);
    expect(second.fingerprint, first.fingerprint);
    final other = DedaCurrentUidProbe100453.classify(
      firebaseReady: true, uid: 'QA_OTHER_UID_123456',
      isAnonymous: true);
    expect(other.fingerprint, isNot(first.fingerprint));
  });

  test('absent Firebase and logged-out states never invent a UID', () {
    final missing = DedaCurrentUidProbe100453.classify(
      firebaseReady: false, uid: 'QA_INVALID_UID', isAnonymous: true);
    expect(missing.kind, DedaCurrentUidProbeKind.firebaseUnavailable);
    expect(missing.fingerprint, isNull);
    final signedOut = DedaCurrentUidProbe100453.classify(
      firebaseReady: true, uid: null, isAnonymous: null);
    expect(signedOut.kind, DedaCurrentUidProbeKind.noSession);
    expect(signedOut.fingerprint, isNull);
  });

  test('unreadable principal does not claim matching A B C', () {
    for (final bad in <String>['', 'QA_UID']) {
      final result = DedaCurrentUidProbe100453.classify(
        firebaseReady: true, uid: bad, isAnonymous: null);
      expect(result.kind, DedaCurrentUidProbeKind.unreadable);
      expect(result.fingerprint, isNull);
    }
  });

  test('Arabic explanation distinguishes observation from ownership', () {
    expect(DedaCurrentUidProbe100453.message(
      DedaCurrentUidProbeKind.anonymous, true),
      contains('مجهولة'));
    expect(DedaCurrentUidProbe100453.message(
      DedaCurrentUidProbeKind.noSession, true), contains('لا توجد'));
  });
}
