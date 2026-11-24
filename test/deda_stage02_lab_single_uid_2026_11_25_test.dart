import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_stage02_lab_single_uid_2026_11_25.dart';
import 'package:d_iraq_ludo/deda_session_transition_gate.dart';

void main() {
  bool lab({String project = 'deda-qa-uid-lab-20261108',
      String app = '1:180856267046:android:4c5670efc62169738121e7',
      String sender = '180856267046',
      String? bucket = 'deda-qa-uid-lab-20261108.firebasestorage.app',
      String name = '[DEFAULT]', int count = 1}) =>
      DedaStage02LabSingleUid.matchesLab(projectId: project, appId: app,
        senderId: sender, storageBucket: bucket, appName: name, appCount: count);

  bool principal(String? uid, DedaSessionAuthKind kind,
      {String expected = 'approved-test-uid'}) =>
      DedaStage02LabSingleUid.matchesPrincipal(expectedUid: expected,
        uid: uid, kind: kind);

  test('only the exact lab project and default app are allowed', () {
    expect(lab(), isTrue);
    expect(lab(project: 'deda-25b88'), isFalse);
    expect(lab(app: 'other'), isFalse);
    expect(lab(sender: 'other'), isFalse);
    expect(lab(bucket: null), isFalse);
    expect(lab(name: 'admin'), isFalse);
    expect(lab(count: 2), isFalse);
  });
  test('same UID is required and signed-out or anonymous never qualifies', () {
    expect(principal('approved-test-uid', DedaSessionAuthKind.authenticated), isTrue);
    expect(principal('different', DedaSessionAuthKind.authenticated), isFalse);
    expect(principal(null, DedaSessionAuthKind.none), isFalse);
    expect(principal('approved-test-uid', DedaSessionAuthKind.anonymous), isFalse);
    expect(principal('', DedaSessionAuthKind.authenticated, expected: ''), isFalse);
    expect(principal(' approved-test-uid ', DedaSessionAuthKind.authenticated,
        expected: ' approved-test-uid '), isFalse);
  });
  test('independent inspections of the same UID remain stable', () {
    for (var i = 0; i < 100; i++) {
      expect(principal('approved-test-uid', DedaSessionAuthKind.authenticated), isTrue);
    }
  });
}
