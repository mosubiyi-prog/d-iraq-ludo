import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'deda_place_palette.dart';

/// Changes the public place accent via a verified owner-only Cloud Function.
/// Kept gated until Firebase rules, backend, and multi-account QA are approved.
class DedaPlaceBrandingService {
  static Future<void> setPublicTheme({
    required String placeId,
    required int themeIndex,
  }) async {
    if (!DedaPlacePalette.serverPublishingEnabled ||
        Firebase.apps.isEmpty ||
        placeId.trim().isEmpty ||
        themeIndex < 0 || themeIndex >= DedaPlacePalette.colors.length) {
      throw StateError('place-theme-publication-not-ready');
    }
    // Same existing verified owner account, no profile/PIN/account mutation.
    // This is a separate isolated Spark-mode adapter; never enabled unless
    // reviewed security rules were published and on-device QA accepted.
    const sparkMode = bool.fromEnvironment(
      'DEDA_SPARK_FIRESTORE_LIVE', defaultValue: false,
    );
    if (sparkMode) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('verified-owner-required');
      final db = FirebaseFirestore.instance;
      final session = await db.collection('deda_sessions').doc(uid).get();
      final user = await db.collection('users').doc(uid).get();
      final key = (session.data()?['accountKey'] ?? '').toString().trim();
      if (key.isEmpty || key !=
          (user.data()?['accountKey'] ?? '').toString().trim()) {
        throw StateError('verified-owner-required');
      }
      // Only themeIndex is written. The rule independently proves owner role
      // using protected account session and published place ownership.
      final ref = db.collection('published_places').doc(placeId);
      await ref.update(<String, Object>{'themeIndex': themeIndex});
      final confirmed = await ref.get(const GetOptions(source: Source.server));
      if (confirmed.data()?['themeIndex'] != themeIndex) {
        throw StateError('place-theme-publication-not-confirmed');
      }
      return;
    }
    final result = await FirebaseFunctions.instance
        .httpsCallable(
          'dedaSetPlaceTheme',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 12)),
        ).call(<String, Object>{
          'placeId': placeId,
          'themeIndex': themeIndex,
        });
    if (result.data is! Map ||
        (result.data as Map)['themeIndex'] != themeIndex) {
      throw StateError('place-theme-publication-not-confirmed');
    }
  }
}
