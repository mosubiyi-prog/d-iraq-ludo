import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'deda_social_service.dart';

/// Stage51 — search friend by their original ID OR a server-verified premium
/// alias. Never store the premium alias as a friendship or location target.
class DedaStage51FriendAliasProof {
  final String requestedId;
  final String originalId;
  const DedaStage51FriendAliasProof({
    required this.requestedId,
    required this.originalId,
  });
  static final _premium = RegExp(r'^@DEDA-[A-Z0-9]{4,12}$');
  static final _original = RegExp(r'^@DEDA-[A-Z0-9]{6}$');

  static DedaStage51FriendAliasProof? parse(
      Object? raw, String expectedId) {
    if (!_premium.hasMatch(expectedId) || raw is! Map) {
      throw StateError('unverified-friend-alias');
    }
    final map = Map<String, dynamic>.from(raw);
    if (map.length != 3 || map['requestedId'] != expectedId ||
        map['serverConfirmed'] is! bool) {
      throw StateError('unverified-friend-alias');
    }
    if (map['serverConfirmed'] == false) {
      if (map['originalId'] != null) {
        throw StateError('unverified-friend-alias');
      }
      return null;
    }
    if (map['originalId'] is! String ||
        !_original.hasMatch(map['originalId'])) {
      throw StateError('unverified-friend-alias');
    }
    return DedaStage51FriendAliasProof(
      requestedId: expectedId,
      originalId: map['originalId'] as String,
    );
  }
}

class DedaStage51FriendSearch {
  /// All feature flags OFF by default. Original app search is unchanged.
  static const bool enabled = bool.fromEnvironment(
        'DEDA_PREMIUM_IDS_SERVER_LIVE', defaultValue: false) &&
      bool.fromEnvironment(
        'DEDA_STAGE51_FRIEND_ALIAS_SEARCH_LIVE', defaultValue: false);

  static final _premium = RegExp(r'^@DEDA-[A-Z0-9]{4,12}$');

  static bool acceptsInput(String normalized) =>
      DedaSocialService.looksLikePersonalId(normalized) ||
      (enabled && _premium.hasMatch(normalized));

  static Future<DedaSocialProfile?> findByUserInput(String normalized) async {
    if (!acceptsInput(normalized)) return null;
    // Old registered ID path gets FIRST priority, and remains functional
    // even if premium server is not deployed or has a temporary outage.
    if (DedaSocialService.looksLikePersonalId(normalized)) {
      final legacy = await DedaSocialService.findByPublicId(normalized);
      if (legacy != null) return legacy;
    }
    if (!enabled) return null;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('friend-alias-login-required');
    final response = await FirebaseFunctions.instance
        .httpsCallable(
          'dedaPremiumResolveFriendOriginal',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
        )
        .call<Map<String, dynamic>>(<String, dynamic>{
          'identifier': normalized,
        });
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('friend-alias-requester-changed');
    }
    final proof = DedaStage51FriendAliasProof.parse(
      response.data, normalized);
    if (proof == null) return null;
    // Existing authenticated friend profile, friend request and location
    // APIs operate on the canonical ORIGINAL ID, not the premium alias.
    final profile = await DedaSocialService.findByPublicId(proof.originalId);
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('friend-alias-requester-changed');
    }
    if (profile == null || profile.publicId != proof.originalId) {
      throw StateError('friend-alias-canonical-profile-mismatch');
    }
    return profile;
  }
}
