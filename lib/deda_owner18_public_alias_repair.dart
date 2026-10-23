import 'package:firebase_auth/firebase_auth.dart';
import 'deda_qa32_spark_public_identifier_directory.dart';

/// Rebuild ONLY missing public display projections from an already verified,
/// immutable grant and active selection. Never grants or switches an ID.
class DedaOwner18PublicAliasRepair {
  static final Set<String> _confirmed = {};
  static final Map<String, Future<void>> _pending = {};
  static Future<void> ensure(
      {required String original,
      required String alias,
      required String color,
      required String uid}) async {
    if (!DedaQa32SparkPublicIdentifierDirectory.enabled) return;
    if (FirebaseAuth.instance.currentUser?.uid != uid)
      throw StateError('account-changed');
    final key = '$uid/$original/$alias/$color';
    if (_confirmed.contains(key)) return;
    return _pending.putIfAbsent(key, () async {
      try {
        final visible =
            await DedaQa32SparkPublicIdentifierDirectory.readVerifiedStyle(
                original);
        final route =
            await DedaQa32SparkPublicIdentifierDirectory.resolveActiveAlias(
                alias);
        if (FirebaseAuth.instance.currentUser?.uid != uid)
          throw StateError('account-changed');
        if (visible?['displayId'] != alias ||
            visible?['permanentColor'] != color ||
            route != original) {
          await DedaQa32SparkPublicIdentifierDirectory.publishOwnerVerified(
              originalId: original,
              selectedAlias: alias,
              permanentColor: color);
          final confirmed =
              await DedaQa32SparkPublicIdentifierDirectory.readVerifiedStyle(
                  original);
          final confirmedRoute =
              await DedaQa32SparkPublicIdentifierDirectory.resolveActiveAlias(
                  alias);
          if (confirmed?['displayId'] != alias ||
              confirmedRoute != original ||
              FirebaseAuth.instance.currentUser?.uid != uid) {
            throw StateError('public-alias-sync-unconfirmed');
          }
        }
        _confirmed.add(key);
      } finally {
        _pending.remove(key);
      }
    });
  }
}
