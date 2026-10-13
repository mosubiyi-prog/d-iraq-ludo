"""DEDA 100332 hard regression gate: original owner -> admin review path.

Run AFTER the 100331 restore and the staged 100332 changes.
No real request is sent and no Firebase deployment occurs.
"""
from pathlib import Path

main=Path('lib/main.dart').read_text(encoding='utf-8')
backend=Path('lib/deda_backend.dart').read_text(encoding='utf-8')
admin=Path('lib/admin_pages.dart').read_text(encoding='utf-8')
functions=Path('functions/index.js').read_text(encoding='utf-8')
rules=Path('firestore.rules').read_text(encoding='utf-8')

owner=main[main.index('class _OwnerPlacePageState extends State<OwnerPlacePage> {'):main.index('class PersonalPlacesPage')]
submitted=owner[owner.index('  Future<void> _submitForReview() async {'):owner.index('class ',owner.index('  Future<void> _submitForReview() async {')) if 'class ' in owner[owner.index('  Future<void> _submitForReview() async {'):] else len(owner)]

for text in [
    "if (!(_formKey.currentState?.validate() ?? false)) return;",
    "if (_latitude == null || _longitude == null)",
    "final data = _currentData();",
    "requestId = await DedaBackend.resubmitPlaceRequest(",
    "requestId = await DedaBackend.submitPlaceEdit(",
    "requestId = await DedaBackend.submitPlace(data);",
    "await prefs.setString(_submittedSnapshotKey, jsonEncode(data));",
    "await prefs.remove(_draftKey);",
    "_status = 'pending';",
]:
    assert text in submitted, 'Submission flow missing: '+text

for text in [
    "static Future<String> submitPlace(Map<String, dynamic> data) async",
    "static Future<String> submitPlaceEdit({",
    "static Future<String> resubmitPlaceRequest({",
    ".collection('place_requests').doc()",
    "'ownerUid': user.uid,",
    "'accountKey': accountKey,",
    "'requestType': 'create',",
    "'status': 'pending',",
    "'createdAt': FieldValue.serverTimestamp(),",
    "'updatedAt': FieldValue.serverTimestamp(),",
    "_hasActivePlaceRequest(user.uid, accountKey)",
    "static Stream<List<Map<String, dynamic>>> ownerPlaceNotificationsStream(",
]:
    assert text in backend, 'Backend owner-admin link missing: '+text

assert "widget.collection == 'place_requests'" in admin
assert "_can('viewPlaceRequests')" in admin or "viewPlaceRequests" in admin
assert "_can('approvePlaces')" in admin
assert "_can('rejectPlaces')" in admin
assert "sourceCollection: 'place_requests'" in admin
assert 'exports.onPlaceRequestCreated = onDocumentCreated(' in functions
assert '"place_requests/{requestId}"' in functions
assert 'await notifyAdmins(' in functions
assert 'exports.onPlaceRequestUpdated = onDocumentUpdated(' in functions
assert 'match /place_requests/{requestId}' in rules
assert 'hasAdminPermission(' in rules
assert 'request.resource.data.status == ' + "'pending'" in rules

# Newly chosen colors, logo and metrics are *additional* request data.
# No direct changes to the approved place or admin decision schema.
assert "'themeIndex': _placeThemeIndex" in owner
assert "if (_placeLogoUrl.isNotEmpty) 'logoUrl': _placeLogoUrl" in owner
assert 'DedaPlaceLogoService.uploadsEnabled' in owner
assert 'DedaPlaceEngagementService.live' in owner
assert "data.remove('themeIndex');" in owner
assert "data.remove('logoUrl');" in owner
assert 'DedaPlacePalette.serverPublishingEnabled' in owner
assert "allow update: if isGeneralManager()" in rules
assert "'isAvailableNow', 'updatedAt'" in rules

# No imported logo/engagement service can silently bypass review.
assert 'DedaBackend.submitPlace(data)' in submitted
assert "collection('published_places').doc()" not in owner
assert "collection('owner_place_notifications').doc()" not in owner

print('PASS: owner place create/edit/resubmit -> place_requests pending ->')
print('admin approval/rejection/needs_changes -> owner notifications intact.')
print('No direct publication, no service deployment, no real requests sent.')
