import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_stage40_original_level_xp_fence.dart';

void main() {
  test('unchanged installed and default private build keeps original rewards', () {
    expect(DedaStage40OriginalTaskXpFence.privatePilot, isFalse);
    expect(DedaStage40OriginalTaskXpFence.blockLocalTaskAndSocialReward, isFalse);
    expect(
      DedaStage40OriginalTaskXpFence.decision(pilotEnabled: false),
      DedaStage40AwardRoute.originalLocal,
    );
  });

  test('opt-in pilot fails closed for BOTH original task and social level', () {
    expect(
      DedaStage40OriginalTaskXpFence.decision(pilotEnabled: true),
      DedaStage40AwardRoute.blockedPendingCutover,
    );
  });
}
