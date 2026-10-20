#!/usr/bin/env python3
"""Stage64: recover an existing published owner place after a phone change.

Run AFTER exact original 100359 Flutter source reconstruction. This only
edits reconstructed Dart source; never writes Firebase data, deploys or builds.
Fail closed whenever a known source anchor changed.
"""
from pathlib import Path

BACKEND = Path("lib/deda_backend.dart")
MAIN = Path("lib/main.dart")

def replace_one(source: str, old: str, new: str, name: str) -> str:
    if source.count(old) != 1:
        raise RuntimeError("SAFE_STOP_STAGE64_" + name + "_ANCHOR")
    return source.replace(old, new, 1)

backend = BACKEND.read_text()
if "STAGE64_CROSS_DEVICE_OWNER_RECOVERY" in backend:
    raise RuntimeError("SAFE_STOP_STAGE64_ALREADY_PATCHED")

method = """
  // STAGE64_CROSS_DEVICE_OWNER_RECOVERY: read-only. The old installation
  // cached a place ID in SharedPreferences; a new phone has no such ID.
  // NEVER infer ownership merely from an entered name/phone, a public map
  // result, or old ownerUid. Require the authenticated DEDA PIN/trusted
  // session accountKey and leave the published document immutable.
  static Future<Map<String, dynamic>?> recoverPublishedPlaceForSignedInOwner({
    required String expectedAccountKey,
  }) async {
    final expected = expectedAccountKey.trim();
    final user = FirebaseAuth.instance.currentUser;
    if (!isReady ||
        expected.isEmpty ||
        user == null ||
        !user.isAnonymous) {
      throw StateError('owner-recovery-login-required');
    }

    final session = await FirebaseFirestore.instance
        .collection('deda_sessions')
        .doc(user.uid)
        .get();
    final trustedKey = (session.data()?['accountKey'] ?? '').toString().trim();
    if (!session.exists || trustedKey.isEmpty || trustedKey != expected) {
      throw StateError('owner-recovery-session-mismatch');
    }

    // Require an explicit published==true filter so Firestore public-read
    // rules cannot accidentally include unpublished/hidden private records.
    // Index readiness must be checked against the real deployed rules/indexes.
    final matches = await FirebaseFirestore.instance
        .collection('published_places')
        .where('accountKey', isEqualTo: trustedKey)
        .where('published', isEqualTo: true)
        .limit(2)
        .get();
    if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
      throw StateError('owner-recovery-session-changed');
    }
    if (matches.docs.length > 1) {
      // Never guess between multiple places or overwrite ownerUid.
      throw StateError('owner-recovery-ambiguous');
    }
    if (matches.docs.isEmpty) return null;
    final place = matches.docs.single;
    if (place.data()['accountKey']?.toString().trim() != trustedKey ||
        place.data()['published'] != true) {
      throw StateError('owner-recovery-invalid-record');
    }
    return <String, dynamic>{'id': place.id, ...place.data()};
  }

"""
backend = replace_one(
    backend,
    "  static Future<Map<String, dynamic>?> currentOwnerPublishedPlace(\n",
    method + "  static Future<Map<String, dynamic>?> currentOwnerPublishedPlace(\n",
    "BACKEND",
)
main = MAIN.read_text()
owner_start = main.find("class _OwnerPlacePageState extends State<OwnerPlacePage> {")
owner_end = main.find("class DedaPersonalPlace", owner_start)
if owner_start < 0 or owner_end <= owner_start:
    raise RuntimeError("SAFE_STOP_STAGE64_OWNER_SCREEN_NOT_RECONSTRUCTED")
owner = main[owner_start:owner_end]
if "_ownerRecoveryIssue" in owner:
    raise RuntimeError("SAFE_STOP_STAGE64_ALREADY_IN_OWNER")

owner = replace_one(
    owner,
    "  String? _decisionNote;\n",
    "  String? _decisionNote;\n  String? _ownerRecoveryIssue;\n",
    "OWNER_FIELD",
)
owner = replace_one(
    owner,
    "      _placeId = prefs.getString(_placeIdKey);\n"
    "      _pendingEditId = prefs.getString(_pendingEditIdKey);\n",
    """      _placeId = prefs.getString(_placeIdKey);
      _pendingEditId = prefs.getString(_pendingEditIdKey);
      _ownerRecoveryIssue = null;

      // On a replacement phone, local SharedPreferences contains no old
      // place ID. Recover by an existing verified DEDA login session, never
      // by raw entered phone text or an anonymous UID match.
      if (_placeId == null || _placeId!.trim().isEmpty) {
        try {
          final recovered =
              await DedaBackend.recoverPublishedPlaceForSignedInOwner(
            expectedAccountKey: _ownerStorageAccountKey,
          );
          if (recovered != null) {
            final recoveredId = (recovered['id'] ?? '').toString().trim();
            if (recoveredId.isEmpty) {
              throw StateError('owner-recovery-missing-place-id');
            }
            _placeId = recoveredId;
            await prefs.setString(_placeIdKey, recoveredId);
          }
        } catch (_) {
          // Do not silently display an empty editable new-place form when
          // ownership/session verification or Firestore index lookup fails.
          // No existing place, approval, engagement or owner UID is changed.
          _ownerRecoveryIssue = dedaText(
            'تعذر التحقق من ملكية مكانك. سجل الدخول إلى حسابك الأصلي '
            'برمز الدخول، ثم اضغط تحديث الحالة. لن نحذف مكانك القديم.',
            'Could not verify your place ownership. Sign in to your '
            'original account with your PIN and refresh. Your old '
            'published place is not deleted.',
          );
          _status = 'recovery_blocked';
          return;
        }
      }
""",
    "OWNER_LOAD",
)
owner = replace_one(
    owner,
    "                          _statusCard(),\n",
    """                          _statusCard(),
                          if (_ownerRecoveryIssue != null)
                            Card(
                              color: const Color(0xFFFFF3E4),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Text(
                                  _ownerRecoveryIssue!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
""",
    "OWNER_WARNING",
)
main = main[:owner_start] + owner + main[owner_end:]
BACKEND.write_text(backend)
MAIN.write_text(main)
print("PASS Stage64 recovered-place lookup is authenticated, read-only and fail-closed")
