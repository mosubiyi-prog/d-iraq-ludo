import 'package:cloud_firestore/cloud_firestore.dart';

import 'deda_geo_window.dart';

/// PREPARATION ONLY: indexed/region-scoped Firestore query implementation.
///
/// IMPORTANT: existing DedaBackend.roadHazards() and publishedPlaces() remain
/// unchanged; this repository is NOT connected to the live 100318 map.
///
/// Before activation: create the reviewed Firestore indexes, verify old docs
/// contain numeric latitude/longitude, ensure route-corridor hazard coverage,
/// handle scan.complete=false, and field-test against the 100318 reference.
class DedaGeoFirestoreReader {
  DedaGeoFirestoreReader(this.firestore);

  final FirebaseFirestore firestore;

  Future<DedaGeoScan<Map<String, dynamic>>> nearbyRoadHazards({
    required double latitude,
    required double longitude,
    required double radiusMeters,
    DedaGeoQueryBudget budget = const DedaGeoQueryBudget(),
  }) {
    return _fetchArea(
      collection: 'road_hazards',
      selectorField: 'status',
      selectorValue: 'active',
      window: DedaGeoWindow.around(
        latitude: latitude,
        longitude: longitude,
        radiusMeters: radiusMeters,
      ),
      budget: budget,
    );
  }

  Future<DedaGeoScan<Map<String, dynamic>>> nearbyPublishedPlaces({
    required double latitude,
    required double longitude,
    required double radiusMeters,
    DedaGeoQueryBudget budget = const DedaGeoQueryBudget(),
  }) {
    return _fetchArea(
      collection: 'published_places',
      selectorField: 'published',
      selectorValue: true,
      window: DedaGeoWindow.around(
        latitude: latitude,
        longitude: longitude,
        radiusMeters: radiusMeters,
      ),
      budget: budget,
    );
  }

  Future<DedaGeoScan<Map<String, dynamic>>> _fetchArea({
    required String collection,
    required String selectorField,
    required Object selectorValue,
    required DedaGeoWindow window,
    required DedaGeoQueryBudget budget,
  }) async {
    final unique = <String, Map<String, dynamic>>{};
    var complete = true;

    for (final longitudeRange in window.longitudeRanges) {
      Query<Map<String, dynamic>> query = firestore
          .collection(collection)
          .where(selectorField, isEqualTo: selectorValue)
          .where('latitude', isGreaterThanOrEqualTo: window.south)
          .where('latitude', isLessThanOrEqualTo: window.north)
          .where('longitude', isGreaterThanOrEqualTo: longitudeRange.west)
          .where('longitude', isLessThanOrEqualTo: longitudeRange.east)
          .orderBy('latitude')
          .orderBy('longitude');

      final region = await dedaCollectGeoPages<
          QueryDocumentSnapshot<Map<String, dynamic>>>(
        budget: budget,
        loadPage: (pageSize, after) async {
          Query<Map<String, dynamic>> paged = query.limit(pageSize);
          if (after != null) {
            paged = paged.startAfterDocument(after);
          }
          return (await paged.get()).docs;
        },
      );

      if (!region.complete) complete = false;
      for (final doc in region.items) {
        // Preserve Firestore document ID; never generate a new hazard ID.
        unique[doc.id] = <String, dynamic>{
          'id': doc.id,
          ...doc.data(),
        };
      }
    }

    return DedaGeoScan<Map<String, dynamic>>(
      items: unique.values.toList(growable: false),
      complete: complete,
    );
  }
}
