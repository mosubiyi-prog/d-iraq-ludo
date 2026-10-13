import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

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
