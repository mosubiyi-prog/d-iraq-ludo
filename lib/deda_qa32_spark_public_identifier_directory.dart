import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// SPARK (no Cloud Functions, no billing): verified, minimal public ID projection.
///
/// IMPORTANT: production Firestore rules must first be merged with the
/// *actual live rules*, security-tested and owner-approved. By default this
/// bridge is completely OFF. Without audited rules, never publish any data.
class DedaQa32SparkPublicIdentifierDirectory {
  DedaQa32SparkPublicIdentifierDirectory._();

  static const bool enabled = bool.fromEnvironment(
    'DEDA_QA32_SPARK_PUBLIC_IDS_LIVE', defaultValue: false);

  static final RegExp _original = RegExp(r'^@DEDA-[A-Z0-9]{6}$');
  static final RegExp _alias = RegExp(r'^@DEDA-[A-Z0-9]{4,12}$');
  static const Set<String> _colors = {'gold','diamond','royal','pink'};

  static String? originalFromProjection(
    String requestedAlias,
    Map<String, dynamic>? route,
    Map<String, dynamic>? active,
  ) {
    if (!_alias.hasMatch(requestedAlias) || route == null || active == null) {
      return null;
    }
    final original = route['originalId'];
    if (original is! String || !_original.hasMatch(original) ||
        route.length != 4 ||
        route['aliasId'] != requestedAlias ||
        route['baseColor'] == null ||
        !_colors.contains(route['baseColor']) ||
        active.length != 4 ||
        active['originalId'] != original ||
        active['activeId'] != requestedAlias ||
        active['baseColor'] != route['baseColor']) return null;
    // Stale alias route remains harmless when user switched premium IDs:
    // its original's CURRENT live projection must match the requested alias.
    return original;
  }

  static Map<String, dynamic>? styleFromProjection(
    String originalId,
    Map<String, dynamic>? active,
  ) {
    if (!_original.hasMatch(originalId) || active == null ||
        active.length != 4 || active['originalId'] != originalId) return null;
    final alias = active['activeId'];
    if (alias is! String || !_alias.hasMatch(alias) ||
        alias == originalId || !_colors.contains(active['baseColor'])) {
      return null;
    }
    return <String, dynamic>{
      'requestedId': originalId,
      'displayId': alias,
      'permanentColor': active['baseColor'],
      'serverConfirmed': true,
    };
  }

  static Future<String?> resolveActiveAlias(String submittedAlias) async {
    final alias = submittedAlias.trim().toUpperCase();
    if (!enabled || !_alias.hasMatch(alias)) return null;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return null;
    final db = FirebaseFirestore.instance;
    final route = await db.collection('deda_public_alias_routes')
        .doc(alias).get(const GetOptions(source: Source.server));
    if (!route.exists) return null;
    final original = route.data()?['originalId'];
    if (original is! String || !_original.hasMatch(original)) return null;
    final active = await db.collection('deda_public_active_aliases')
        .doc(original).get(const GetOptions(source: Source.server));
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('spark-alias-requester-changed');
    }
    return originalFromProjection(alias, route.data(), active.data());
  }

  static Future<Map<String, dynamic>?> readVerifiedStyle(
      String originalId) async {
    if (!enabled || !_original.hasMatch(originalId)) return null;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return null;
    final row = await FirebaseFirestore.instance
        .collection('deda_public_active_aliases').doc(originalId)
        .get(const GetOptions(source: Source.server));
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('spark-style-requester-changed');
    }
    return styleFromProjection(originalId, row.data());
  }

  /// Publish ONLY after verified owner use() confirms the genuine Stage71
  /// selection/grant/receipt. Firestore Security Rules repeat all proof checks;
  /// the client result is never sufficient to authorize a public mapping.
  static Future<void> publishOwnerVerified({
    required String originalId,
    required String selectedAlias,
    String? permanentColor,
  }) async {
    if (!enabled) return;
    if (!_original.hasMatch(originalId) || !_alias.hasMatch(selectedAlias)) {
      throw StateError('spark-publish-id-invalid');
    }
    if (selectedAlias == originalId && permanentColor != null ||
        selectedAlias != originalId && !_colors.contains(permanentColor)) {
      throw StateError('spark-publish-color-invalid');
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('spark-publish-signed-in-required');
    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    final now = FieldValue.serverTimestamp();
    batch.set(db.collection('deda_public_active_aliases').doc(originalId), {
      'originalId': originalId,
      'activeId': selectedAlias,
      'baseColor': permanentColor,
      'updatedAt': now,
    });
    if (selectedAlias != originalId) {
      batch.set(db.collection('deda_public_alias_routes').doc(selectedAlias), {
        'aliasId': selectedAlias,
        'originalId': originalId,
        'baseColor': permanentColor,
        'updatedAt': now,
      });
    }
    await batch.commit();
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('spark-publish-account-rotated');
    }
  }
}
