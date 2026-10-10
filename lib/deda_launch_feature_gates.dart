/// DEDA public-launch policy: keep server-dependent additions in
/// source, but OFF until an owner-tested backend is actually live.
///
/// Do NOT use Firestore flags or preferences to bypass this compile-time gate.
class DedaLaunchFeatureGates {
  const DedaLaunchFeatureGates._();
  static const bool serverFeaturesEnabled = bool.fromEnvironment(
    'DEDA_SERVER_AUTOMATIONS_LIVE',
    defaultValue: false,
  );
  static const bool pinAutoRecovery = serverFeaturesEnabled;
  static const bool placeAutoApproval = serverFeaturesEnabled;
  static const bool telegramVerifiedRewards = serverFeaturesEnabled;
}
