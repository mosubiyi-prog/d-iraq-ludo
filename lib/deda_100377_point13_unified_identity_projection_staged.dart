import 'deda_qa32_active_account_scope.dart';
import 'deda_stage50_verified_friend_ink_badge.dart';

/// Point13 source-only adapter: one visible identity vs immutable routing ID.
/// This is NOT proof that the 200 reserved manager IDs are published or live.
/// Ownership/grants/public reads still require their existing trusted sources.
class DedaPoint13UnifiedIdentity {
  final String canonicalOriginal;
  final String stagedDisplayId;
  final String? permanentColor;
  final bool isServerVerified;

  const DedaPoint13UnifiedIdentity._(
    this.canonicalOriginal,
    this.stagedDisplayId,
    this.permanentColor,
    this.isServerVerified,
  );

  static const bool releaseEnabled = bool.fromEnvironment(
    'DEDA_100377_UNIFIED_ACTIVE_ID_LIVE', defaultValue: false,
  );

  static final RegExp _original = RegExp(r'^@DEDA-[A-Z0-9]{6}$');
  static final RegExp _alias = RegExp(r'^@DEDA-[A-Z0-9]{4,12}$');
  static const Set<String> _colors = {
    'gold', 'diamond', 'royal', 'pink',
  };

  /// Never route shares, friend lookups or grant records using the alias.
  String get routeId => canonicalOriginal;
  String get displayedId =>
      releaseEnabled && isServerVerified ? stagedDisplayId : canonicalOriginal;
  bool get hasLivePremiumFoil => releaseEnabled && isServerVerified &&
      stagedDisplayId != canonicalOriginal && permanentColor != null;

  static DedaPoint13UnifiedIdentity originalOnly(String original) {
    if (!_original.hasMatch(original)) {
      throw StateError('point13-invalid-canonical-original');
    }
    return DedaPoint13UnifiedIdentity._(original, original, null, false);
  }

  /// The verified owner source already binds Firebase UID, canonical ID and
  /// one active owned alias. Never use an arbitrary local SharedPreference.
  static DedaPoint13UnifiedIdentity fromVerifiedOwner({
    required String currentUid,
    required String originalId,
    required DedaQa32ActiveAccountIdentity? proof,
  }) {
    final fallback = originalOnly(originalId);
    if (proof == null || !proof.verifiedFor(currentUid, originalId)) {
      return fallback;
    }
    final alias = proof.displayId;
    final color = proof.fixedColor;
    if (!_alias.hasMatch(alias) ||
        alias == originalId && color != null ||
        alias != originalId && !_colors.contains(color)) {
      return fallback;
    }
    return DedaPoint13UnifiedIdentity._(
      originalId, alias, color, alias != originalId,
    );
  }

  /// Call ONLY with the DTO returned by Stage50's owner-verified, server-only
  /// public style bridge. A manually forged DTO or an offline art preview is
  /// never authority to grant an ID, change an account or publish a route.
  static DedaPoint13UnifiedIdentity fromTrustedPublicBridge({
    required String originalId,
    required DedaStage50PublicIdStyle? proof,
  }) {
    final fallback = originalOnly(originalId);
    if (proof == null || proof.requestedId != originalId ||
        proof.displayId == originalId ||
        !_alias.hasMatch(proof.displayId) ||
        !_colors.contains(proof.permanentColor)) {
      return fallback;
    }
    return DedaPoint13UnifiedIdentity._(
      originalId, proof.displayId, proof.permanentColor, true,
    );
  }
}
