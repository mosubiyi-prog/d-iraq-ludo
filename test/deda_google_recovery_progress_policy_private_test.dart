import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_google_recovery_progress_100439.dart';

void main() {
  test('actual Google verification stages are strictly increasing, under 100', () {
    var before = 0;
    for (final step in DedaGoogleRecoveryStage.values) {
      final current = DedaGoogleRecoveryProgressPolicy.percent(step);
      expect(DedaGoogleRecoveryProgressPolicy.isSafeStep(before, step),
          isTrue);
      expect(current, greaterThan(before));
      expect(current, lessThan(100));
      expect(DedaGoogleRecoveryProgressPolicy.label(step), isNotEmpty);
      before = current;
    }
    expect(before, 85);
    expect(DedaGoogleRecoveryProgressPolicy.isSafeStep(85,
        DedaGoogleRecoveryStage.googleTokenReceived), isFalse);
    expect(DedaGoogleRecoveryProgressPolicy.isSafeStep(85,
        DedaGoogleRecoveryStage.originalOwnerVerified), isFalse);
  });

  test('identity-only and full-account outcomes never have same meaning', () {
    expect(DedaGoogleRecoveryOutcome.identityVerifiedOnly,
        isNot(DedaGoogleRecoveryOutcome.fullAccountRestored));
    expect(DedaGoogleRecoveryOutcome.cancelled,
        isNot(DedaGoogleRecoveryOutcome.fullAccountRestored));
  });
}
