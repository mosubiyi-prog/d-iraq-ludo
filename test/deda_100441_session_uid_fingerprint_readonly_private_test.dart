import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_session_diagnostic_readonly_100441.dart';

void main() {
  test('same live Firebase UID has stable private diagnostic fingerprint', () {
    final first = DedaSessionDiagnosticReadOnly.fingerprintOfUid(
        'synthetic-original-uid-100441');
    expect(first, matches(RegExp(r'^[0-9A-F]{16}$')));
    expect(DedaSessionDiagnosticReadOnly.fingerprintOfUid(
        'synthetic-original-uid-100441'), first);
    expect(first, isNot(contains('synthetic-original-uid')));
  });

  test('three independent historical candidates cannot be conflated', () {
    final a = DedaSessionDiagnosticReadOnly.fingerprintOfUid(
        'synthetic-a-owner-uid');
    final b = DedaSessionDiagnosticReadOnly.fingerprintOfUid(
        'synthetic-b-directory-uid');
    final c = DedaSessionDiagnosticReadOnly.fingerprintOfUid(
        'synthetic-c-social-uid');
    final d = DedaSessionDiagnosticReadOnly.fingerprintOfUid(
        'synthetic-d-unknown-current-uid');
    expect({a, b, c, d}.length, 4);
    expect(() => DedaSessionDiagnosticReadOnly.fingerprintOfUid(''),
        throwsArgumentError);
  });

  test('separate Google link is offered only for detached anonymous UID', () {
    DedaSessionProbeReport sample({
      DedaProbeKind kind = DedaProbeKind.anonymous,
      DedaProbeMatch original = DedaProbeMatch.differentUid,
      DedaProbeMatch directory = DedaProbeMatch.differentUid,
      bool google = false,
      bool password = false,
    }) => DedaSessionProbeReport(
      kind, original, directory, google, password,
      sessionFingerprint: 'B2A482AB8AB94AB3',
    );
    bool eligible(DedaSessionProbeReport r) =>
        DedaSessionDiagnosticReadOnly.mayOfferDetachedGoogleLink(r);

    expect(eligible(sample()), true);
    expect(eligible(sample(kind: DedaProbeKind.linked)), false);
    expect(eligible(sample(kind: DedaProbeKind.signedOut)), false);
    expect(eligible(sample(original: DedaProbeMatch.sameUid)), false);
    expect(eligible(sample(directory: DedaProbeMatch.sameUid)), false);
    expect(eligible(sample(original: DedaProbeMatch.unavailable)), false);
    expect(eligible(sample(directory: DedaProbeMatch.unavailable)), false);
    expect(eligible(sample(google: true)), false);
    expect(eligible(sample(password: true)), false);
  });

  test('fingerprint is diagnostic, not a Firebase owner assertion', () {
    final value = DedaSessionDiagnosticReadOnly.fingerprintOfUid(
        'synthetic-anonymous-current-uid');
    expect(value.length, 16);
    expect(value, isNot(equals('synthetic-anonymous-current-uid')));
  });
}
