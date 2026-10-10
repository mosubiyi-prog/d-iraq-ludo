import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_launch_feature_gates.dart';

void main() {
  test('public launch holds all server-dependent features OFF by default', () {
    expect(DedaLaunchFeatureGates.serverFeaturesEnabled, isFalse);
    expect(DedaLaunchFeatureGates.telegramVerifiedRewards, isFalse);
    expect(DedaLaunchFeatureGates.pinAutoRecovery, isFalse);
    expect(DedaLaunchFeatureGates.placeAutoApproval, isFalse);
  });
}
