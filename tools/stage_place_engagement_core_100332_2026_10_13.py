"""Prepare secure DEDA place engagements without deployment.

Apply after all 100331 + earlier 100332 stage scripts.
"""
from pathlib import Path

places_path = Path('lib/places_service.dart')
main_path = Path('lib/main.dart')
rules_path = Path('firestore.rules')
functions_path = Path('functions/index.js')
places = places_path.read_text()
main = main_path.read_text()
rules = rules_path.read_text()
server = functions_path.read_text()

def swap(src, a, b, name):
    assert src.count(a) == 1, name + ': expected one exact anchor'
    return src.replace(a, b, 1)

if 'publishedPlaceId' in places and 'dedaReadPlaceEngagement' in server:
    print('Staged already.')
    raise SystemExit(0)

places = swap(places,
    '  final bool isDedaRegistered;\n  final bool isAvailableNow;',
    '  final bool isDedaRegistered;\n  final bool isAvailableNow;\n  final String publishedPlaceId;',
    'stable id')
places = swap(places,
    '    this.isDedaRegistered = false,\n    this.isAvailableNow = false,',
    "    this.isDedaRegistered = false,\n    this.isAvailableNow = false,\n    this.publishedPlaceId = '',",
    'id constructor')
places = swap(places,
    "        'isAvailableNow': isAvailableNow,",
    "        'isAvailableNow': isAvailableNow,\n        'publishedPlaceId': publishedPlaceId,",
    'id JSON')
places = swap(places,
    "      isAvailableNow: json['isAvailableNow'] == true,",
    "      isAvailableNow: json['isAvailableNow'] == true,\n      publishedPlaceId: (json['publishedPlaceId'] ?? '').toString(),",
    'id from JSON')
main = swap(main,
    "            isDedaRegistered: true,\n            isAvailableNow: data['isAvailableNow'] == true,",
    "            isDedaRegistered: true,\n            isAvailableNow: data['isAvailableNow'] == true,\n            publishedPlaceId: (data['id'] ?? '').toString(),",
    'published Firestore ID')
server += """

// DEDA 100332 staged Cloud Functions. Do not deploy without QA and approval.
const placeEngagement = require("./deda_place_engagement");
exports.dedaReadPlaceEngagement = onCall(async (request) => {
  try {
    return await placeEngagement.readPlaceEngagement(getFirestore(), {
      placeId: request.data?.placeId, uid: request.auth?.uid || "",
    });
  } catch (error) {
    throw new HttpsError(error.code || "unavailable",
        String(error.message || "place-engagement-unavailable"));
  }
});
exports.dedaSetPlaceEngagement = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "session-required");
  }
  try {
    return await placeEngagement.setPlaceEngagement(getFirestore(), {
      placeId: request.data?.placeId, uid: request.auth.uid,
      kind: request.data?.kind, active: request.data?.active,
    });
  } catch (error) {
    throw new HttpsError(error.code || "unavailable",
        String(error.message || "place-engagement-unavailable"));
  }
});
"""
rules = swap(rules,
    '    match /admin_trash_places/{trashId} {',
    '''    // DEDA 100332: engagement is callable-only (Admin SDK).
    match /deda_place_engagement/{placeId}/users/{accountHash} {
      allow read, write: if false;
    }
    match /deda_place_engagement_totals/{placeId} {
      allow read, write: if false;
    }

    match /admin_trash_places/{trashId} {''',
    'security rules')
places_path.write_text(places)
main_path.write_text(main)
functions_path.write_text(server)
rules_path.write_text(rules)
print('PASS: stable place doc IDs, callable backend and explicit-deny rules.')
print('No release build or deployment.')
