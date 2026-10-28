/// Stage40 of DEDA weekly league — signed-original-source QA cutover fence.
 ///
 /// This flag is OFF for every ordinary build, including already installed
 /// users. There is NO trusted live task issuer, migration completion,
 /// App Check enforcement or old-version revocation in this module.
 ///
 /// A future PRIVATE QA pilot cannot award locally while awaiting a fully
 /// reviewed server-only migration: block both original DedaTaskEngine +5
 /// and SocialProgressWallet +20 lifetime XP / +10 social coins.
 ///
 /// Important: false is ORIGINAL behavior. Never enable for real users
 /// without an independently verified server claim, migration settlement
 /// and an enforced old-APK writer fence plus owner approval.
enum DedaStage40AwardRoute { originalLocal, blockedPendingCutover }

class DedaStage40OriginalTaskXpFence {
  const DedaStage40OriginalTaskXpFence._();

  static const bool privatePilot = bool.fromEnvironment(
    'DEDA_STAGE40_ORIGINAL_TASK_XP_FENCE_QA', defaultValue: false);

  static DedaStage40AwardRoute decision({
    required bool pilotEnabled,
    required bool originalLevelXpAndCoinsWrite,
  }) {
    if (!pilotEnabled) return DedaStage40AwardRoute.originalLocal;
    // Stop BOTH task and social writer, not only the UI-facing +5.
    // No local fallback on offline, account switching or untrusted server.
    return DedaStage40AwardRoute.blockedPendingCutover;
  }

  static bool get blockLocalTaskAndSocialReward => privatePilot;
}
