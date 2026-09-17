from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read(rel):
    return (ROOT / rel).read_text(encoding='utf-8')


def write(rel, text):
    (ROOT / rel).write_text(text, encoding='utf-8')


def replace_once(rel, old, new, label):
    text = read(rel)
    if new in text:
        print(f'[skip] {label}')
        return
    if old not in text:
        raise SystemExit(f'Could not find source for: {label}')
    write(rel, text.replace(old, new, 1))
    print(f'[ok] {label}')


def regex_once(rel, pattern, repl, marker, label):
    text = read(rel)
    if marker in text:
        print(f'[skip] {label}')
        return
    updated, count = re.subn(pattern, repl, text, count=1, flags=re.S | re.M)
    if count != 1:
        raise SystemExit(f'Could not match source for: {label} ({count})')
    write(rel, updated)
    print(f'[ok] {label}')


# ---------------------------------------------------------------------------
# 1/2/3/4 Backend: stable phone account key, support history across devices,
# robust read-only admin account review, and non-blocking support photo send.
# ---------------------------------------------------------------------------
replace_once(
    'lib/deda_backend.dart',
    "  static bool get isReady => Firebase.apps.isNotEmpty;\n",
    """  static bool get isReady => Firebase.apps.isNotEmpty;

  // Build 87 review fixes: one logical account key per normalized phone.
  // Firebase anonymous UIDs may differ per device, so DEDA data also carries
  // this stable key. Phone verification can later harden ownership without
  // changing the stored account linkage.
  static String accountKeyForPhone(String phone) =>
      phone.replaceAll(RegExp(r'[^0-9]'), '');

  static Future<String> _currentAccountKey(User user) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final key = (snapshot.data()?['accountKey'] ?? '').toString().trim();
      if (key.isNotEmpty) return key;
    } catch (_) {}
    return user.uid;
  }
""",
    'backend account key helpers',
)

replace_once(
    'lib/deda_backend.dart',
    """      'name': name.trim(),
      'phone': phone.trim(),
      'accountType': accountType.trim(),""",
    """      'name': name.trim(),
      'phone': phone.trim(),
      'accountKey': accountKeyForPhone(phone),
      'accountType': accountType.trim(),""",
    'profile stores account key',
)

replace_once(
    'lib/deda_backend.dart',
    """    final cleanName = name.trim();
    final cleanPhone = phone.trim();

    // Keep one account identity for support, admin review and notifications.
    await firestore.collection('users').doc(user.uid).set({
      'name': cleanName,
      'phone': cleanPhone,
      'updatedAt': FieldValue.serverTimestamp(),
      'lastSeenAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));""",
    """    final cleanName = name.trim();
    final cleanPhone = phone.trim();
    final accountKey = accountKeyForPhone(cleanPhone);

    // Best effort only: a stale deployed users rule must never block a support
    // message or photo. Login/profile sync can retry independently.
    try {
      await firestore.collection('users').doc(user.uid).set({
        'name': cleanName,
        'phone': cleanPhone,
        'accountKey': accountKey,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}""",
    'support profile sync is non-blocking',
)

replace_once(
    'lib/deda_backend.dart',
    """      'ownerUid': user.uid,
      'type': type,
      'name': cleanName,""",
    """      'ownerUid': user.uid,
      'accountKey': accountKey,
      'type': type,
      'name': cleanName,""",
    'support stores stable account key',
)

# Active place request guard by both device UID and stable account key.
regex_once(
    'lib/deda_backend.dart',
    r"  static Future<bool> _hasActivePlaceRequest\(String ownerUid\) async \{.*?^  \}\n\n  static Future<String> submitSupport",
    """  static Future<bool> _hasActivePlaceRequest(
    String ownerUid,
    String accountKey,
  ) async {
    final firestore = FirebaseFirestore.instance;
    try {
      final byAccount = await firestore
          .collection('place_requests')
          .where('accountKey', isEqualTo: accountKey)
          .limit(25)
          .get();
      if (byAccount.docs.any((doc) {
        final status = (doc.data()['status'] ?? '').toString();
        return status == 'pending' || status == 'reviewing';
      })) return true;
    } catch (_) {}

    final byUid = await firestore
        .collection('place_requests')
        .where('ownerUid', isEqualTo: ownerUid)
        .limit(25)
        .get();
    return byUid.docs.any((doc) {
      final status = (doc.data()['status'] ?? '').toString();
      return status == 'pending' || status == 'reviewing';
    });
  }

  static Future<String> submitSupport""",
    'static Future<bool> _hasActivePlaceRequest(\n    String ownerUid,',
    'active request guard uses account key',
)

replace_once(
    'lib/deda_backend.dart',
    """    final user = await _ensurePublicUser();
    if (await _hasActivePlaceRequest(user.uid)) {
      throw StateError('active-place-request');
    }
    await registerOwnerNotifications();
    final request =
        FirebaseFirestore.instance.collection('place_requests').doc();
    await request.set({
      ...data,
      'ownerUid': user.uid,
      'requestType': 'create',""",
    """    final user = await _ensurePublicUser();
    final accountKey = await _currentAccountKey(user);
    if (await _hasActivePlaceRequest(user.uid, accountKey)) {
      throw StateError('active-place-request');
    }
    await registerOwnerNotifications();
    final request =
        FirebaseFirestore.instance.collection('place_requests').doc();
    await request.set({
      ...data,
      'ownerUid': user.uid,
      'accountKey': accountKey,
      'requestType': 'create',""",
    'new place request uses account key',
)

replace_once(
    'lib/deda_backend.dart',
    """    final user = await _ensurePublicUser();
    if (await _hasActivePlaceRequest(user.uid)) {
      throw StateError('active-place-request');
    }
    await registerOwnerNotifications();
    final original = await FirebaseFirestore.instance
        .collection('published_places')
        .doc(originalPlaceId)
        .get();
    if (!original.exists || original.data()?['ownerUid'] != user.uid) {
      throw StateError('not-place-owner');
    }
    final request =
        FirebaseFirestore.instance.collection('place_requests').doc();
    await request.set({
      ...data,
      'ownerUid': user.uid,
      'requestType': 'update',""",
    """    final user = await _ensurePublicUser();
    final accountKey = await _currentAccountKey(user);
    if (await _hasActivePlaceRequest(user.uid, accountKey)) {
      throw StateError('active-place-request');
    }
    await registerOwnerNotifications();
    final original = await FirebaseFirestore.instance
        .collection('published_places')
        .doc(originalPlaceId)
        .get();
    final originalData = original.data();
    final sameOwner = originalData?['ownerUid'] == user.uid ||
        (originalData?['accountKey']?.toString() == accountKey);
    if (!original.exists || !sameOwner) {
      throw StateError('not-place-owner');
    }
    final request =
        FirebaseFirestore.instance.collection('place_requests').doc();
    await request.set({
      ...data,
      'ownerUid': user.uid,
      'accountKey': accountKey,
      'requestType': 'update',""",
    'place edit uses account key',
)

regex_once(
    'lib/deda_backend.dart',
    r"  static Future<Map<String, dynamic>\?> ownerRequestById\(String id\) async \{.*?^  \}\n\n  static Future<Map<String, dynamic>\?> publishedPlaceById",
    """  static Future<Map<String, dynamic>?> ownerRequestById(String id) async {
    final user = await _ensurePublicUser();
    final accountKey = await _currentAccountKey(user);
    final snapshot = await FirebaseFirestore.instance
        .collection('place_requests')
        .doc(id)
        .get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    final sameOwner = data['ownerUid'] == user.uid ||
        data['accountKey']?.toString() == accountKey;
    if (!sameOwner) return null;
    return {'id': snapshot.id, ...data};
  }

  static Future<Map<String, dynamic>?> publishedPlaceById""",
    'final sameOwner = data[\'ownerUid\'] == user.uid ||',
    'owner request read uses account key',
)

regex_once(
    'lib/deda_backend.dart',
    r"  static Future<List<Map<String, dynamic>>> mySupportRequests\(\) async \{.*?^  \}\n\n  static Future<void> updateSupportStatus",
    """  static Future<List<Map<String, dynamic>>> mySupportRequests({
    required String phone,
  }) async {
    final user = await _ensurePublicUser();
    final accountKey = accountKeyForPhone(phone);
    final firestore = FirebaseFirestore.instance;
    final byId = <String, Map<String, dynamic>>{};

    // New records are account-key based, so the same phone sees the same
    // support history on another device. Keep UID fallback for older tickets.
    try {
      final snapshot = await firestore
          .collection('support_requests')
          .where('accountKey', isEqualTo: accountKey)
          .limit(50)
          .get();
      for (final doc in snapshot.docs) {
        byId[doc.id] = <String, dynamic>{'id': doc.id, ...doc.data()};
      }
    } catch (_) {}

    try {
      final snapshot = await firestore
          .collection('support_requests')
          .where('ownerUid', isEqualTo: user.uid)
          .limit(50)
          .get();
      for (final doc in snapshot.docs) {
        byId[doc.id] = <String, dynamic>{'id': doc.id, ...doc.data()};
      }
    } catch (_) {}

    final items = byId.values.toList();
    int millis(dynamic value) =>
        value is Timestamp ? value.millisecondsSinceEpoch : 0;
    items.sort((a, b) =>
        millis(b['createdAt']).compareTo(millis(a['createdAt'])));
    return items;
  }

  static Future<void> updateSupportStatus""",
    'required String phone,\n  }) async {',
    'support history uses stable account key',
)

# Replace read-only admin snapshot with a defensive implementation that still
# opens when the deployed /users or /admin_audit rules are stale.
regex_once(
    'lib/deda_backend.dart',
    r"  static Future<Map<String, dynamic>> adminUserSnapshot\(\{.*?^  \}\n\n  static Future<void> signOutAdmin",
    """  static Future<Map<String, dynamic>> adminUserSnapshot({
    required String ownerUid,
    required String sourceCollection,
    required String sourceId,
  }) async {
    final actor = await _adminIdentity();
    final firestore = FirebaseFirestore.instance;

    Map<String, dynamic> sourceData = <String, dynamic>{};
    try {
      final source =
          await firestore.collection(sourceCollection).doc(sourceId).get();
      sourceData = source.data() ?? <String, dynamic>{};
    } catch (_) {}

    final sourcePhone = (sourceData['phone'] ?? '').toString().trim();
    final sourceKey = (sourceData['accountKey'] ?? '').toString().trim();
    final accountKey = sourceKey.isNotEmpty
        ? sourceKey
        : (sourcePhone.isNotEmpty ? accountKeyForPhone(sourcePhone) : '');

    Map<String, dynamic> profile = <String, dynamic>{};
    try {
      final user = await firestore.collection('users').doc(ownerUid).get();
      profile = user.data() ?? <String, dynamic>{};
    } catch (_) {}
    if (profile.isEmpty && accountKey.isNotEmpty) {
      try {
        final users = await firestore
            .collection('users')
            .where('accountKey', isEqualTo: accountKey)
            .limit(1)
            .get();
        if (users.docs.isNotEmpty) profile = users.docs.first.data();
      } catch (_) {}
    }
    profile = <String, dynamic>{
      'name': profile['name'] ?? sourceData['name'] ?? '',
      'phone': profile['phone'] ?? sourceData['phone'] ?? '',
      'accountType': profile['accountType'] ?? sourceData['accountType'] ?? '',
      'accountKey': profile['accountKey'] ?? accountKey,
      ...profile,
    };

    Future<List<Map<String, dynamic>>> owned(String collection) async {
      final byId = <String, Map<String, dynamic>>{};
      if (accountKey.isNotEmpty) {
        try {
          final snapshot = await firestore
              .collection(collection)
              .where('accountKey', isEqualTo: accountKey)
              .limit(50)
              .get();
          for (final doc in snapshot.docs) {
            byId[doc.id] = <String, dynamic>{'id': doc.id, ...doc.data()};
          }
        } catch (_) {}
      }
      try {
        final snapshot = await firestore
            .collection(collection)
            .where('ownerUid', isEqualTo: ownerUid)
            .limit(50)
            .get();
        for (final doc in snapshot.docs) {
          byId[doc.id] = <String, dynamic>{'id': doc.id, ...doc.data()};
        }
      } catch (_) {}
      return byId.values.toList();
    }

    final placeRequests = await owned('place_requests');
    final published = await owned('published_places');
    final support = await owned('support_requests');

    // Always attempt an audit record. If that collection has not been deployed
    // yet, record the review on the source ticket/request instead so the action
    // remains traceable and the read-only window still opens.
    try {
      await firestore.collection('admin_audit').add({
        'action': 'read_user_account',
        'ownerUid': ownerUid,
        'accountKey': accountKey,
        'sourceCollection': sourceCollection,
        'sourceId': sourceId,
        'adminUid': actor['uid'],
        'adminName': actor['name'],
        'adminRole': actor['role'],
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
    try {
      await firestore.collection(sourceCollection).doc(sourceId).update({
        'accountReviewedAt': FieldValue.serverTimestamp(),
        'accountReviewedByUid': actor['uid'],
        'accountReviewedByName': actor['name'],
        'accountReviewedByRole': actor['role'],
      });
    } catch (_) {}

    return <String, dynamic>{
      'uid': ownerUid,
      'accountKey': accountKey,
      'profile': profile,
      'placeRequests': placeRequests,
      'publishedPlaces': published,
      'supportRequests': support,
    };
  }

  static Future<void> signOutAdmin""",
    "'accountReviewedAt': FieldValue.serverTimestamp(),",
    'robust read-only admin account view',
)

# ---------------------------------------------------------------------------
# Main app: keep the local name for a known phone, use phone-key support
# history, never let profile sync block a photo send, and improve DEDA marker.
# ---------------------------------------------------------------------------
replace_once(
    'lib/main.dart',
    """    userName = name;
    phone = normalizedPhone;
    accountPhone = normalizedPhone;
    accountType = type;
    isLoggedIn = true;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userNameKey, name);""",
    """    final prefs = await SharedPreferences.getInstance();
    final previousPhone = prefs.getString(_phoneKey) ?? '';
    final previousName = prefs.getString(_userNameKey) ?? '';
    final resolvedName = previousPhone == normalizedPhone &&
            previousName.trim().isNotEmpty
        ? previousName.trim()
        : name.trim();

    userName = resolvedName;
    phone = normalizedPhone;
    accountPhone = normalizedPhone;
    accountType = type;
    isLoggedIn = true;

    await prefs.setString(_userNameKey, resolvedName);""",
    'same phone reuses local account name',
)

replace_once(
    'lib/main.dart',
    """      await DedaBackend.syncCurrentUserProfile(
        name: name,
        phone: normalizedPhone,
        accountType: type.name,
      );""",
    """      await DedaBackend.syncCurrentUserProfile(
        name: resolvedName,
        phone: normalizedPhone,
        accountType: type.name,
      );""",
    'profile sync uses resolved account name',
)

replace_once(
    'lib/main.dart',
    """  Future<void> _showMySupportHistory() async {
    try {
      final items = await DedaBackend.mySupportRequests();""",
    """  Future<void> _showMySupportHistory() async {
    try {
      try {
        await DedaBackend.syncCurrentUserProfile(
          name: DedaPreferences.userName,
          phone: DedaPreferences.phone,
          accountType: DedaPreferences.accountType?.name ?? 'user',
        );
      } catch (_) {}
      final items = await DedaBackend.mySupportRequests(
        phone: DedaPreferences.phone,
      );""",
    'support history syncs account and uses phone key',
)

replace_once(
    'lib/main.dart',
    """      if (_usingAccountIdentity) {
        await DedaBackend.syncCurrentUserProfile(
          name: supportName,
          phone: supportPhone,
          accountType: DedaPreferences.accountType?.name ?? 'user',
        );
      }
      final requestId = await DedaBackend.submitSupport(""",
    """      // Do not block support/photo sending on a profile sync. submitSupport
      // performs its own best-effort sync and then sends the ticket.
      final requestId = await DedaBackend.submitSupport(""",
    'photo/support send no longer blocked by profile sync',
)

marker_class = r'''class DedaMapPlaceMarker extends StatelessWidget {
  final PlaceInfo place;
  final IconData icon;
  final VoidCallback onTap;

  const DedaMapPlaceMarker({
    super.key,
    required this.place,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (!place.isDedaRegistered) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(blurRadius: 4, color: Colors.black26)],
          ),
          child: Icon(icon, size: 30, color: const Color(0xFF39733D)),
        ),
      );
    }

    final active = place.isAvailableNow;
    final pinColor = active ? const Color(0xFF159447) : const Color(0xFF707873);

    // The map's Marker keeps a compact anchor, while OverflowBox lets the
    // approved place name appear above it without covering nearby roads.
    return GestureDetector(
      onTap: onTap,
      child: OverflowBox(
        maxWidth: 140,
        maxHeight: 92,
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: 136,
          height: 88,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 132),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.96),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: pinColor.withOpacity(0.72)),
                  boxShadow: const [
                    BoxShadow(blurRadius: 5, color: Color(0x33000000)),
                  ],
                ),
                child: Directionality(
                  textDirection: DedaLanguageState.direction,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          place.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF203326),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: pinColor.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Icon(icon, size: 12, color: pinColor),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: pinColor, width: 3),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: active ? 10 : 5,
                          spreadRadius: active ? 2 : 1,
                          color: pinColor.withOpacity(active ? 0.52 : 0.25),
                        ),
                      ],
                    ),
                    child: Icon(icon, size: 23, color: pinColor),
                  ),
                  Positioned(
                    right: -17,
                    bottom: 1,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF17652F),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white, width: 1.2),
                      ),
                      child: const Text(
                        'DEDA',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 7,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}'''

regex_once(
    'lib/main.dart',
    r"class DedaMapPlaceMarker extends StatelessWidget \{.*?^\}\n\n(?=class DedaPlaceSearchPage)",
    marker_class + '\n\n',
    'approved place name appear above it',
    'map marker shows place name and small place logo',
)

# ---------------------------------------------------------------------------
# Firestore rules: user support reads by stable phone account key while
# preserving old UID tickets; account-key ownership for place data.
# ---------------------------------------------------------------------------
replace_once(
    'firestore.rules',
    """          'fcmTokens', 'lastSeenAt', 'name', 'phone', 'accountType',
          'createdAt', 'updatedAt'""",
    """          'fcmTokens', 'lastSeenAt', 'name', 'phone', 'accountType',
          'accountKey', 'createdAt', 'updatedAt'""",
    'users create allows account key',
)
replace_once(
    'firestore.rules',
    """          'fcmTokens', 'lastSeenAt', 'name', 'phone', 'accountType',
          'createdAt', 'updatedAt'""",
    """          'fcmTokens', 'lastSeenAt', 'name', 'phone', 'accountType',
          'accountKey', 'createdAt', 'updatedAt'""",
    'users update allows account key',
)

replace_once(
    'firestore.rules',
    """      allow read, update: if isAdmin();
      allow delete: if false;
    }

    match /place_requests/{requestId} {""",
    """      allow read: if isAdmin()
        || (signedIn() && resource.data.ownerUid == request.auth.uid)
        || (signedIn()
          && resource.data.accountKey is string
          && exists(/databases/$(database)/documents/users/$(request.auth.uid))
          && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.accountKey == resource.data.accountKey);
      allow update: if isAdmin();
      allow delete: if false;
    }

    match /place_requests/{requestId} {""",
    'support owner reads replies by account key',
)

replace_once(
    'firestore.rules',
    """      allow read: if isAdmin()
        || (signedIn() && resource.data.ownerUid == request.auth.uid);
      allow update: if isAdmin();""",
    """      allow read: if isAdmin()
        || (signedIn() && resource.data.ownerUid == request.auth.uid)
        || (signedIn()
          && resource.data.accountKey is string
          && exists(/databases/$(database)/documents/users/$(request.auth.uid))
          && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.accountKey == resource.data.accountKey);
      allow update: if isAdmin();""",
    'place request owner reads by account key',
)

replace_once(
    'firestore.rules',
    """      allow update: if isAdmin()
        || (signedIn()
          && resource.data.ownerUid == request.auth.uid
          && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['isAvailableNow', 'updatedAt']));""",
    """      allow update: if isAdmin()
        || (signedIn()
          && (resource.data.ownerUid == request.auth.uid
            || (resource.data.accountKey is string
              && exists(/databases/$(database)/documents/users/$(request.auth.uid))
              && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.accountKey == resource.data.accountKey))
          && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['isAvailableNow', 'updatedAt']));""",
    'published place ownership by account key',
)

print('Build 87 five-point patch completed successfully.')
