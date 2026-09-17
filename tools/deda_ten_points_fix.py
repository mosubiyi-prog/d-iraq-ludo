from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def write(rel, text):
    (ROOT / rel).write_text(text, encoding="utf-8")


def replace_once(rel, old, new, label):
    text = read(rel)
    if new in text:
        print(f"[skip] {label}")
        return
    if old not in text:
        raise SystemExit(f"Could not find source for: {label}")
    write(rel, text.replace(old, new, 1))
    print(f"[ok] {label}")


def insert_before(rel, anchor, block, marker, label):
    text = read(rel)
    if marker in text:
        print(f"[skip] {label}")
        return
    if anchor not in text:
        raise SystemExit(f"Could not find anchor for: {label}")
    write(rel, text.replace(anchor, block + "\n\n" + anchor, 1))
    print(f"[ok] {label}")


def regex_once(rel, pattern, repl, marker, label):
    text = read(rel)
    if marker in text:
        print(f"[skip] {label}")
        return
    updated, count = re.subn(pattern, repl, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"Could not match source for: {label} ({count})")
    write(rel, updated)
    print(f"[ok] {label}")


# ---------------------------------------------------------------------------
# Backend: identity, duplicate guard, support workflow, live place data,
# audit-only admin account view, robust image upload, seven-digit approvals.
# ---------------------------------------------------------------------------
replace_once(
    "lib/deda_backend.dart",
    "import 'dart:io';",
    "import 'dart:convert';\nimport 'dart:io';",
    "backend base64 import",
)

replace_once(
    "lib/deda_backend.dart",
    "next.toString().padLeft(6, '0')",
    "next.toString().padLeft(7, '0')",
    "seven-digit approval sequence",
)

backend_support = r'''  // DEDA 10-point fixes v1: unified user identity + robust support uploads.
  static Future<void> syncCurrentUserProfile({
    required String name,
    required String phone,
    required String accountType,
  }) async {
    final user = await _ensurePublicUser();
    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final existing = await ref.get();
    await ref.set({
      'name': name.trim(),
      'phone': phone.trim(),
      'accountType': accountType.trim(),
      if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastSeenAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<bool> _hasActivePlaceRequest(String ownerUid) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('place_requests')
        .where('ownerUid', isEqualTo: ownerUid)
        .limit(25)
        .get();
    return snapshot.docs.any((doc) {
      final status = (doc.data()['status'] ?? '').toString();
      return status == 'pending' || status == 'reviewing';
    });
  }

  static Future<String> submitSupport({
    required String type,
    required String name,
    required String phone,
    required String message,
    String? imagePath,
  }) async {
    final user = await _ensurePublicUser();
    final firestore = FirebaseFirestore.instance;
    final request = firestore.collection('support_requests').doc();
    final cleanName = name.trim();
    final cleanPhone = phone.trim();

    // Keep one account identity for support, admin review and notifications.
    await firestore.collection('users').doc(user.uid).set({
      'name': cleanName,
      'phone': cleanPhone,
      'updatedAt': FieldValue.serverTimestamp(),
      'lastSeenAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    String? imageUrl;
    String? imageBase64;
    String? imageMimeType;
    if (imagePath != null && imagePath.isNotEmpty) {
      final file = File(imagePath);
      if (!await file.exists()) throw StateError('support-image-missing');
      final bytes = await file.readAsBytes();
      if (bytes.length > 8 * 1024 * 1024) {
        throw StateError('support-image-too-large');
      }
      final extension = imagePath.contains('.')
          ? imagePath.split('.').last.toLowerCase()
          : 'jpg';
      final contentType = switch (extension) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        _ => 'image/jpeg',
      };
      imageMimeType = contentType;
      try {
        final reference = FirebaseStorage.instance
            .ref('support_uploads/${user.uid}/${request.id}.$extension');
        await reference.putData(
          bytes,
          SettableMetadata(contentType: contentType),
        );
        imageUrl = await reference.getDownloadURL();
      } catch (_) {
        // Small compressed photos can still be delivered through Firestore
        // if Storage is temporarily unavailable or its rules are not deployed yet.
        if (bytes.length <= 650 * 1024) {
          imageBase64 = base64Encode(bytes);
        } else {
          rethrow;
        }
      }
    }

    // If this is a place owner, link the support ticket directly to the
    // approved DEDA place so the employee never has to search for it manually.
    Map<String, dynamic>? linkedPlace;
    String? linkedPlaceId;
    try {
      final owned = await firestore
          .collection('published_places')
          .where('ownerUid', isEqualTo: user.uid)
          .limit(20)
          .get();
      for (final doc in owned.docs) {
        if (doc.data()['published'] == true) {
          linkedPlaceId = doc.id;
          linkedPlace = doc.data();
          break;
        }
      }
    } catch (_) {}

    await request.set({
      'ownerUid': user.uid,
      'type': type,
      'name': cleanName,
      'phone': cleanPhone,
      'message': message.trim(),
      'imageUrl': imageUrl,
      'imageBase64': imageBase64,
      'imageMimeType': imageMimeType,
      'status': 'new',
      if (linkedPlaceId != null) 'linkedPlaceId': linkedPlaceId,
      if (linkedPlace != null) ...{
        'linkedPlaceName': linkedPlace['placeName'],
        'linkedApprovalNumber': linkedPlace['approvalNumber'],
        'linkedLatitude': linkedPlace['latitude'],
        'linkedLongitude': linkedPlace['longitude'],
        'linkedSourceRequestId': linkedPlace['lastSourceRequestId'] ??
            linkedPlace['sourceRequestId'],
      },
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return request.id;
  }'''

regex_once(
    "lib/deda_backend.dart",
    r"  static Future<String> submitSupport\(\{.*?^  \}\n\n  static Future<String> submitPlace\(",
    backend_support + "\n\n  static Future<String> submitPlace(",
    "DEDA 10-point fixes v1: unified user identity",
    "replace support submission",
)

# Server-side duplicate protection for place requests, including a fresh phone.
replace_once(
    "lib/deda_backend.dart",
    """    final user = await _ensurePublicUser();
    await registerOwnerNotifications();
    final request =
        FirebaseFirestore.instance.collection('place_requests').doc();""",
    """    final user = await _ensurePublicUser();
    if (await _hasActivePlaceRequest(user.uid)) {
      throw StateError('active-place-request');
    }
    await registerOwnerNotifications();
    final request =
        FirebaseFirestore.instance.collection('place_requests').doc();""",
    "block duplicate place requests",
)

replace_once(
    "lib/deda_backend.dart",
    """    final user = await _ensurePublicUser();
    await registerOwnerNotifications();
    final original = await FirebaseFirestore.instance
        .collection('published_places')""",
    """    final user = await _ensurePublicUser();
    if (await _hasActivePlaceRequest(user.uid)) {
      throw StateError('active-place-request');
    }
    await registerOwnerNotifications();
    final original = await FirebaseFirestore.instance
        .collection('published_places')""",
    "block duplicate place edit requests",
)

backend_admin_support = r'''  // DEDA 10-point fixes v1: support replies and read-only account review.
  static Stream<Map<String, dynamic>?> publishedPlaceStream(String id) {
    return FirebaseFirestore.instance
        .collection('published_places')
        .doc(id)
        .snapshots()
        .map((snapshot) => snapshot.exists && snapshot.data() != null
            ? <String, dynamic>{'id': snapshot.id, ...snapshot.data()!}
            : null);
  }

  static Future<List<Map<String, dynamic>>> mySupportRequests() async {
    final user = await _ensurePublicUser();
    final snapshot = await FirebaseFirestore.instance
        .collection('support_requests')
        .where('ownerUid', isEqualTo: user.uid)
        .limit(50)
        .get();
    final items = snapshot.docs
        .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
        .toList();
    int millis(dynamic value) => value is Timestamp
        ? value.millisecondsSinceEpoch
        : 0;
    items.sort((a, b) => millis(b['createdAt']).compareTo(millis(a['createdAt'])));
    return items;
  }

  static Future<void> updateSupportStatus({
    required String id,
    required String status,
  }) async {
    const allowed = {'new', 'in_progress', 'replied', 'closed'};
    if (!allowed.contains(status)) throw ArgumentError('invalid-support-status');
    final actor = await _adminIdentity();
    await FirebaseFirestore.instance.collection('support_requests').doc(id).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
      'reviewedBy': actor['uid'],
      'reviewedByName': actor['name'],
      'reviewedByRole': actor['role'],
      if (status == 'closed') 'closedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> replyToSupport({
    required String id,
    required String message,
  }) async {
    final clean = message.trim();
    if (clean.isEmpty) throw ArgumentError('empty-support-reply');
    final actor = await _adminIdentity();
    await FirebaseFirestore.instance.collection('support_requests').doc(id).update({
      'status': 'replied',
      'adminReply': clean,
      'adminReplyAt': FieldValue.serverTimestamp(),
      'adminReplyByUid': actor['uid'],
      'adminReplyByName': actor['name'],
      'adminReplyByRole': actor['role'],
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<Map<String, dynamic>> adminUserSnapshot({
    required String ownerUid,
    required String sourceCollection,
    required String sourceId,
  }) async {
    final actor = await _adminIdentity();
    final firestore = FirebaseFirestore.instance;
    final user = await firestore.collection('users').doc(ownerUid).get();
    final placeRequests = await firestore
        .collection('place_requests')
        .where('ownerUid', isEqualTo: ownerUid)
        .limit(50)
        .get();
    final published = await firestore
        .collection('published_places')
        .where('ownerUid', isEqualTo: ownerUid)
        .limit(50)
        .get();
    final support = await firestore
        .collection('support_requests')
        .where('ownerUid', isEqualTo: ownerUid)
        .limit(50)
        .get();

    // Every read-only account review is auditable.
    await firestore.collection('admin_audit').add({
      'action': 'read_user_account',
      'ownerUid': ownerUid,
      'sourceCollection': sourceCollection,
      'sourceId': sourceId,
      'adminUid': actor['uid'],
      'adminName': actor['name'],
      'adminRole': actor['role'],
      'createdAt': FieldValue.serverTimestamp(),
    });

    return <String, dynamic>{
      'uid': ownerUid,
      'profile': user.data() ?? <String, dynamic>{},
      'placeRequests': placeRequests.docs
          .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
          .toList(),
      'publishedPlaces': published.docs
          .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
          .toList(),
      'supportRequests': support.docs
          .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
          .toList(),
    };
  }'''

insert_before(
    "lib/deda_backend.dart",
    "  static Future<void> signOutAdmin() => FirebaseAuth.instance.signOut();",
    backend_admin_support,
    "DEDA 10-point fixes v1: support replies",
    "backend support workflow and account audit",
)

# ---------------------------------------------------------------------------
# Firestore/storage security: admin read-only user profiles and owner support
# replies visible to the same user.
# ---------------------------------------------------------------------------
replace_once(
    "firestore.rules",
    """    match /users/{uid} {
      allow read: if signedIn() && request.auth.uid == uid;
      allow create: if signedIn() && request.auth.uid == uid
        && request.resource.data.keys().hasOnly(['fcmTokens', 'lastSeenAt']);
      allow update: if signedIn() && request.auth.uid == uid
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['fcmTokens', 'lastSeenAt']);
      allow delete: if false;
    }""",
    """    match /users/{uid} {
      allow read: if isAdmin() || (signedIn() && request.auth.uid == uid);
      allow create: if signedIn() && request.auth.uid == uid
        && request.resource.data.keys().hasOnly([
          'fcmTokens', 'lastSeenAt', 'name', 'phone', 'accountType',
          'createdAt', 'updatedAt'
        ]);
      allow update: if signedIn() && request.auth.uid == uid
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly([
          'fcmTokens', 'lastSeenAt', 'name', 'phone', 'accountType',
          'createdAt', 'updatedAt'
        ]);
      allow delete: if false;
    }""",
    "admin read-only user profiles",
)

replace_once(
    "firestore.rules",
    "      allow read, update: if isAdmin();",
    """      allow read: if isAdmin()
        || (signedIn() && resource.data.ownerUid == request.auth.uid);
      allow update: if isAdmin();""",
    "support owner can read replies",
)

insert_before(
    "firestore.rules",
    "    match /system_counters/{counterId} {",
    """    // DEDA 10-point fixes v1: immutable audit trail for admin read-only review.
    match /admin_audit/{auditId} {
      allow read, create: if isAdmin();
      allow update, delete: if false;
    }""",
    "DEDA 10-point fixes v1: immutable audit trail",
    "admin audit rules",
)

replace_once(
    "storage.rules",
    """      allow read: if request.auth != null
        && firestore.exists(/databases/(default)/documents/admins/$(request.auth.uid));""",
    """      allow read: if request.auth != null
        && firestore.exists(/databases/(default)/documents/admins/$(request.auth.uid))
        && firestore.get(/databases/(default)/documents/admins/$(request.auth.uid)).data.active == true;""",
    "storage read requires active admin",
)

# ---------------------------------------------------------------------------
# Notifications: support replies/statuses reach the ticket owner.
# ---------------------------------------------------------------------------
replace_once(
    "functions/index.js",
    """async function notifyOwner(ownerUid, title, body, requestId) {
  if (!ownerUid) return;
  const user = await getFirestore().collection("users").doc(ownerUid).get();
  if (!user.exists) return;
  const values = user.data().fcmTokens;
  const tokens = Array.isArray(values) ? values : [];
  await notifyTokens(tokens, title, body, "place_result", requestId);
}""",
    """async function notifyOwner(ownerUid, title, body, requestId, type = "place_result") {
  if (!ownerUid) return;
  const user = await getFirestore().collection("users").doc(ownerUid).get();
  if (!user.exists) return;
  const values = user.data().fcmTokens;
  const tokens = Array.isArray(values) ? values : [];
  await notifyTokens(tokens, title, body, type, requestId);
}""",
    "support notification type support",
)

insert_before(
    "functions/index.js",
    "exports.onPlaceRequestCreated = onDocumentCreated(",
    r'''// DEDA 10-point fixes v1: notify users when support is handled or replied to.
exports.onSupportRequestUpdated = onDocumentUpdated(
    "support_requests/{requestId}",
    async (event) => {
      const before = event.data && event.data.before.data();
      const after = event.data && event.data.after.data();
      if (!before || !after) return;
      if (before.status === after.status && before.adminReply === after.adminReply) return;

      let title = "تحديث من دعم DEDA";
      let body = "تم تحديث حالة رسالتك لدى فريق DEDA.";
      if (after.status === "in_progress") {
        body = "رسالتك قيد المعالجة لدى فريق DEDA.";
      } else if (after.status === "replied") {
        title = "رد جديد من دعم DEDA";
        body = after.adminReply || "لديك رد جديد من فريق DEDA.";
      } else if (after.status === "closed") {
        title = "تم إغلاق طلب الدعم في DEDA";
        body = after.adminReply || "تمت معالجة طلب الدعم وإغلاقه.";
      }
      await notifyOwner(
          after.ownerUid,
          title,
          body,
          event.params.requestId,
          "support_result",
      );
    },
);''',
    "DEDA 10-point fixes v1: notify users",
    "support reply notifications",
)

# ---------------------------------------------------------------------------
# Main app: persist account identity, lock names in support when logged in,
# support-history replies, robust image size, map-search normalization.
# ---------------------------------------------------------------------------
replace_once(
    "lib/main.dart",
    """    await prefs.setString(_accountTypeKey, type.name);
    await prefs.setBool(_loggedInKey, true);
  }""",
    """    await prefs.setString(_accountTypeKey, type.name);
    await prefs.setBool(_loggedInKey, true);
    try {
      await DedaBackend.syncCurrentUserProfile(
        name: name,
        phone: normalizedPhone,
        accountType: type.name,
      );
    } catch (_) {
      // Local sign-in remains usable if the network is temporarily unavailable.
    }
  }""",
    "sync login identity to backend",
)

replace_once(
    "lib/main.dart",
    """    _nameController = TextEditingController(text: widget.initialName);
    _phoneController = TextEditingController(text: widget.initialPhone);
    _loadDraft();""",
    """    final loggedInName = DedaPreferences.isLoggedIn
        ? DedaPreferences.userName.trim()
        : '';
    final loggedInPhone = DedaPreferences.isLoggedIn
        ? DedaPreferences.phone.trim()
        : '';
    _nameController = TextEditingController(
      text: loggedInName.isNotEmpty ? loggedInName : widget.initialName,
    );
    _phoneController = TextEditingController(
      text: loggedInPhone.isNotEmpty ? loggedInPhone : widget.initialPhone,
    );
    _loadDraft();""",
    "support uses logged-in identity",
)

insert_before(
    "lib/main.dart",
    "  Future<void> _loadDraft() async {",
    """  // DEDA 10-point fixes v1: account identity is authoritative after sign-in.
  bool get _usingAccountIdentity =>
      DedaPreferences.isLoggedIn &&
      DedaPreferences.userName.trim().isNotEmpty &&
      DedaPreferences.phone.trim().isNotEmpty;

  String _supportStatusLabel(String status) {
    switch (status) {
      case 'in_progress':
        return dedaText('قيد المعالجة', 'In progress');
      case 'replied':
        return dedaText('تم الرد', 'Replied');
      case 'closed':
        return dedaText('تم الحل / مغلق', 'Resolved / closed');
      default:
        return dedaText('جديد', 'New');
    }
  }

  Future<void> _showMySupportHistory() async {
    try {
      final items = await DedaBackend.mySupportRequests();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.72,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                  child: Text(
                    dedaText('رسائلي مع دعم DEDA', 'My DEDA support messages'),
                    style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: items.isEmpty
                      ? Center(child: Text(dedaText('لا توجد رسائل دعم بعد.', 'No support messages yet.')))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, index) {
                            final item = items[index];
                            final reply = (item['adminReply'] ?? '').toString().trim();
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      '${dedaText('الحالة', 'Status')}: ${_supportStatusLabel((item['status'] ?? 'new').toString())}',
                                      style: const TextStyle(fontWeight: FontWeight.w800),
                                    ),
                                    const SizedBox(height: 8),
                                    Text((item['message'] ?? '').toString()),
                                    if (reply.isNotEmpty) ...[
                                      const Divider(height: 24),
                                      Text(
                                        dedaText('رد إدارة DEDA', 'DEDA reply'),
                                        style: const TextStyle(
                                          color: Color(0xFF17652F),
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      SelectableText(reply),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dedaText('تعذر تحميل رسائل الدعم الآن.', 'Could not load support messages now.'))),
      );
    }
  }""",
    "DEDA 10-point fixes v1: account identity",
    "support identity/history helpers",
)

replace_once(
    "lib/main.dart",
    """        imageQuality: 85,
        maxWidth: 1600,""",
    """        imageQuality: 55,
        maxWidth: 1024,""",
    "compress support image for reliable send",
)

replace_once(
    "lib/main.dart",
    """      final requestId = await DedaBackend.submitSupport(
        type: _contactType,
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        message: _messageController.text.trim(),
        imagePath: _attachedImagePath,
      );""",
    """      final supportName = _usingAccountIdentity
          ? DedaPreferences.userName.trim()
          : _nameController.text.trim();
      final supportPhone = _usingAccountIdentity
          ? DedaPreferences.phone.trim()
          : _phoneController.text.trim();
      if (_usingAccountIdentity) {
        await DedaBackend.syncCurrentUserProfile(
          name: supportName,
          phone: supportPhone,
          accountType: DedaPreferences.accountType?.name ?? 'user',
        );
      }
      final requestId = await DedaBackend.submitSupport(
        type: _contactType,
        name: supportName,
        phone: supportPhone,
        message: _messageController.text.trim(),
        imagePath: _attachedImagePath,
      );""",
    "submit support with account identity",
)

replace_once(
    "lib/main.dart",
    """      appBar: AppBar(
        title: Text(dedaText('التواصل مع الشركة', 'Contact company')),
        centerTitle: true,
      ),""",
    """      appBar: AppBar(
        title: Text(dedaText('التواصل مع الشركة', 'Contact company')),
        centerTitle: true,
        actions: [
          if (DedaPreferences.isLoggedIn)
            IconButton(
              tooltip: dedaText('رسائلي وردود الإدارة', 'My messages and replies'),
              onPressed: _showMySupportHistory,
              icon: const Icon(Icons.mark_chat_read_outlined),
            ),
        ],
      ),""",
    "support history button",
)

# Make identity read-only for logged-in users. There are exactly two support fields
# in this page; target the controller-specific snippets.
replace_once(
    "lib/main.dart",
    """                    TextFormField(
                      controller: _nameController,
                      textDirection: DedaLanguageState.direction,""",
    """                    TextFormField(
                      controller: _nameController,
                      readOnly: _usingAccountIdentity,
                      textDirection: DedaLanguageState.direction,""",
    "support name read-only when logged in",
)
replace_once(
    "lib/main.dart",
    """                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,""",
    """                    TextFormField(
                      controller: _phoneController,
                      readOnly: _usingAccountIdentity,
                      keyboardType: TextInputType.phone,""",
    "support phone read-only when logged in",
)

# Map search: Arabic/digit normalization + current visible DEDA data + fresh merge.
insert_before(
    "lib/main.dart",
    "  Future<void> searchInsideMap() async {",
    r'''  // DEDA 10-point fixes v1: normalize Arabic names and digits for local DEDA search.
  String _normalizeDedaSearchText(String value) {
    const digitMap = <String, String>{
      '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4',
      '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9',
      '۰': '0', '۱': '1', '۲': '2', '۳': '3', '۴': '4',
      '۵': '5', '۶': '6', '۷': '7', '۸': '8', '۹': '9',
    };
    var text = value.toLowerCase().trim();
    digitMap.forEach((from, to) => text = text.replaceAll(from, to));
    text = text
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
        .replaceAll(RegExp(r'[إأآٱ]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي')
        .replaceAll('ـ', '')
        .replaceAll(RegExp(r'\s+'), ' ');
    return text;
  }''',
    "DEDA 10-point fixes v1: normalize Arabic names",
    "map search normalization helper",
)

regex_once(
    "lib/main.dart",
    r"      final activePosition = currentPosition!;\n      final registered = await DedaRegisteredPlacesStore\.readAll\(\);\n      final needle = query\.toLowerCase\(\);\n      final results = <PlaceInfo>\[\];\n      for \(final place in registered\) \{\n        if \(place\.name\.toLowerCase\(\)\.contains\(needle\)\) results\.add\(place\);\n      \}\n      if \(results\.isEmpty\) \{",
    """      final activePosition = currentPosition!;
      final freshRegistered = await DedaRegisteredPlacesStore.readAll();
      final mergedRegistered = <PlaceInfo>[];
      final seenDeda = <String>{};
      for (final place in <PlaceInfo>[...registeredPlaces, ...freshRegistered]) {
        final key = '${place.name}|${place.location.latitude.toStringAsFixed(6)}|${place.location.longitude.toStringAsFixed(6)}';
        if (seenDeda.add(key)) mergedRegistered.add(place);
      }
      registeredPlaces = mergedRegistered;
      final needle = _normalizeDedaSearchText(query);
      final results = <PlaceInfo>[];
      for (final place in mergedRegistered) {
        final searchable = _normalizeDedaSearchText(
          '${place.name} ${place.type} ${place.address ?? ''}',
        );
        if (searchable.contains(needle)) results.add(place);
      }
      if (results.isEmpty) {""",
    "freshRegistered = await DedaRegisteredPlacesStore.readAll();",
    "map search uses approved DEDA places first",
)

# ---------------------------------------------------------------------------
# Admin UI: live availability, support-only actions, replies, linked place,
# read-only account view and appropriate support sections.
# ---------------------------------------------------------------------------
replace_once(
    "lib/admin_pages.dart",
    "import 'package:cloud_firestore/cloud_firestore.dart';",
    "import 'dart:convert';\n\nimport 'package:cloud_firestore/cloud_firestore.dart';",
    "admin base64 image import",
)

replace_once(
    "lib/admin_pages.dart",
    """      case 'new':
        return t('جديد', 'New');
      default:""",
    """      case 'new':
        return t('جديد', 'New');
      case 'in_progress':
        return t('قيد المعالجة', 'In progress');
      case 'replied':
        return t('تم الرد', 'Replied');
      case 'closed':
        return t('تم الحل / مغلق', 'Resolved / closed');
      default:""",
    "support status labels",
)

admin_helpers = r'''  // DEDA 10-point fixes v1: support workflow and read-only account review.
  Widget _liveAvailability(Map<String, dynamic> data, String requestId) {
    final fallback = data['isAvailableNow'] == true;
    if (_text(data['status']) != 'approved') {
      return _detailRow(
        t('حالة التواجد', 'Availability'),
        fallback
            ? t('متواجد الآن', 'Available now')
            : t('غير متواجد حاليًا', 'Not available now'),
      );
    }
    final original = _text(data['originalPlaceId']);
    final publishedId = original.isNotEmpty ? original : requestId;
    return StreamBuilder<Map<String, dynamic>?>(
      stream: DedaBackend.publishedPlaceStream(publishedId),
      builder: (context, snapshot) {
        final live = snapshot.data?['isAvailableNow'];
        final available = live is bool ? live : fallback;
        return _detailRow(
          t('حالة التواجد', 'Availability'),
          available
              ? t('متواجد الآن', 'Available now')
              : t('غير متواجد حاليًا', 'Not available now'),
        );
      },
    );
  }

  Future<String?> _askSupportReply() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('الرد على المستخدم', 'Reply to user')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 6,
              children: [
                ActionChip(
                  label: Text(t('جاري المراجعة', 'Under review')),
                  onPressed: () => controller.text = t(
                    'جاري مراجعة المشكلة وسنوافيك بالتحديث.',
                    'We are reviewing the issue and will update you.',
                  ),
                ),
                ActionChip(
                  label: Text(t('تم حل المشكلة', 'Issue resolved')),
                  onPressed: () => controller.text = t(
                    'تم حل المشكلة. شكرًا لتواصلك مع DEDA.',
                    'The issue has been resolved. Thank you for contacting DEDA.',
                  ),
                ),
                ActionChip(
                  label: Text(t('نحتاج معلومات إضافية', 'Need more information')),
                  onPressed: () => controller.text = t(
                    'نحتاج معلومات إضافية حتى نكمل معالجة طلبك.',
                    'We need additional information to continue handling your request.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              minLines: 3,
              maxLines: 7,
              decoration: InputDecoration(
                labelText: t('رد الإدارة', 'Administration reply'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t('إلغاء', 'Cancel')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            icon: const Icon(Icons.send_outlined),
            label: Text(t('إرسال الرد', 'Send reply')),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _replySupport(String id) async {
    final message = await _askSupportReply();
    if (message == null || message.trim().isEmpty) return;
    try {
      await DedaBackend.replyToSupport(id: id, message: message);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('تم إرسال الرد للمستخدم.', 'Reply sent to the user.'))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('تعذر إرسال الرد الآن.', 'Could not send the reply now.'))),
      );
    }
  }

  Future<void> _setSupportStatus(String id, String status) async {
    try {
      await DedaBackend.updateSupportStatus(id: id, status: status);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('تعذر تحديث حالة الدعم.', 'Could not update support status.'))),
      );
    }
  }

  Widget _supportActions({required String status, required String id}) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: status == 'in_progress'
              ? null
              : () => _setSupportStatus(id, 'in_progress'),
          icon: const Icon(Icons.hourglass_top),
          label: Text(t('قيد المعالجة', 'In progress')),
        ),
        FilledButton.icon(
          onPressed: () => _replySupport(id),
          icon: const Icon(Icons.reply),
          label: Text(t('إرسال رد', 'Send reply')),
        ),
        OutlinedButton.icon(
          onPressed: status == 'closed'
              ? null
              : () => _setSupportStatus(id, 'closed'),
          icon: const Icon(Icons.task_alt),
          label: Text(t('تم الحل / إغلاق', 'Resolve / close')),
        ),
      ],
    );
  }

  Future<void> _showUserAccount({
    required String ownerUid,
    required String sourceId,
  }) async {
    if (ownerUid.isEmpty) return;
    try {
      final snapshot = await DedaBackend.adminUserSnapshot(
        ownerUid: ownerUid,
        sourceCollection: widget.collection,
        sourceId: sourceId,
      );
      if (!mounted) return;
      final profile = Map<String, dynamic>.from(
        snapshot['profile'] as Map? ?? const <String, dynamic>{},
      );
      final places = (snapshot['publishedPlaces'] as List? ?? const []);
      final requests = (snapshot['placeRequests'] as List? ?? const []);
      final support = (snapshot['supportRequests'] as List? ?? const []);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.visibility_outlined),
              const SizedBox(width: 8),
              Expanded(child: Text(t('حساب المستخدم • قراءة فقط', 'User account • read only'))),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _detailRow(t('الاسم', 'Name'), profile['name']),
                _detailRow(t('الهاتف', 'Phone'), profile['phone'], ltr: true),
                _detailRow(t('نوع الحساب', 'Account type'), profile['accountType']),
                const Divider(),
                _detailRow(t('الأماكن المعتمدة', 'Approved places'), places.length),
                _detailRow(t('طلبات الأماكن', 'Place requests'), requests.length),
                _detailRow(t('رسائل الدعم', 'Support messages'), support.length),
                if (places.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(t('أماكن المستخدم', 'User places'), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ...places.take(10).map((raw) {
                    final item = Map<String, dynamic>.from(raw as Map);
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.storefront_outlined),
                      title: Text(_text(item['placeName'])),
                      subtitle: Text(_text(item['approvalNumber'])),
                    );
                  }),
                ],
                const SizedBox(height: 8),
                Text(
                  t(
                    'لا يمكن تعديل بيانات المستخدم من هذه النافذة. تم تسجيل هذه المشاهدة في السجل الإداري.',
                    'User data cannot be edited here. This review was recorded in the admin audit log.',
                  ),
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFF5B665D)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(t('إغلاق', 'Close')),
            ),
          ],
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('تعذر فتح حساب المستخدم الآن.', 'Could not open the user account now.'))),
      );
    }
  }'''

insert_before(
    "lib/admin_pages.dart",
    "  Future<String?> _askDecisionNote(String status) async {",
    admin_helpers,
    "DEDA 10-point fixes v1: support workflow",
    "admin support/live/account helpers",
)

# Add id parameter to details and render robust image + linked context + reply.
replace_once(
    "lib/admin_pages.dart",
    "  Widget _requestDetails(Map<String, dynamic> data) {",
    "  Widget _requestDetails(Map<String, dynamic> data, String id) {",
    "admin details receives request id",
)

replace_once(
    "lib/admin_pages.dart",
    """    if (widget.collection == 'support_requests') {
      final imageUrl = _text(data['imageUrl']);
      return Column(""",
    """    if (widget.collection == 'support_requests') {
      final imageUrl = _text(data['imageUrl']);
      final imageBase64 = _text(data['imageBase64']);
      final linkedPlaceId = _text(data['linkedPlaceId']);
      final linkedPlaceName = _text(data['linkedPlaceName']);
      final linkedLatitude = (data['linkedLatitude'] as num?)?.toDouble();
      final linkedLongitude = (data['linkedLongitude'] as num?)?.toDouble();
      final reply = _text(data['adminReply']);
      final ownerUid = _text(data['ownerUid']);
      return Column(""",
    "support details context variables",
)

replace_once(
    "lib/admin_pages.dart",
    """          if (imageUrl.isNotEmpty) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                imageUrl,
                height: 190,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 70,
                  alignment: Alignment.center,
                  color: const Color(0xFFEAF4E7),
                  child: Text(
                    t('تعذر عرض الصورة.', 'Could not display image.'),
                  ),
                ),
              ),
            ),
          ],
          commonAudit,""",
    """          if (imageUrl.isNotEmpty || imageBase64.isNotEmpty) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: imageUrl.isNotEmpty
                  ? Image.network(
                      imageUrl,
                      height: 190,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        height: 70,
                        alignment: Alignment.center,
                        color: const Color(0xFFEAF4E7),
                        child: Text(t('تعذر عرض الصورة.', 'Could not display image.')),
                      ),
                    )
                  : Image.memory(
                      base64Decode(imageBase64),
                      height: 190,
                      fit: BoxFit.cover,
                    ),
            ),
          ],
          if (linkedPlaceId.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              color: const Color(0xFFEAF4E7),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${t('المكان المرتبط', 'Linked place')}: ${linkedPlaceName.isEmpty ? linkedPlaceId : linkedPlaceName}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (_text(data['linkedApprovalNumber']).isNotEmpty)
                      Text('${t('رقم الاعتماد', 'Approval number')}: ${_text(data['linkedApprovalNumber'])}'),
                    if (linkedLatitude != null && linkedLongitude != null)
                      OutlinedButton.icon(
                        onPressed: () => _openMap(
                          latitude: linkedLatitude,
                          longitude: linkedLongitude,
                          placeName: linkedPlaceName,
                        ),
                        icon: const Icon(Icons.map_outlined),
                        label: Text(t('فتح المكان مباشرة', 'Open linked place')),
                      ),
                  ],
                ),
              ),
            ),
          ],
          if (reply.isNotEmpty) ...[
            const SizedBox(height: 10),
            _detailRow(t('رد الإدارة', 'Administration reply'), reply),
          ],
          if (ownerUid.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => _showUserAccount(ownerUid: ownerUid, sourceId: id),
              icon: const Icon(Icons.visibility_outlined),
              label: Text(t('عرض حساب المستخدم • قراءة فقط', 'View user account • read only')),
            ),
          commonAudit,""",
    "support image/link/reply/account details",
)

replace_once(
    "lib/admin_pages.dart",
    """        _detailRow(
          t('حالة التواجد', 'Availability'),
          data['isAvailableNow'] == true
              ? t('متواجد الآن', 'Available now')
              : t('غير متواجد حاليًا', 'Not available now'),
        ),""",
    """        _liveAvailability(data, id),""",
    "admin reads live published availability",
)

replace_once(
    "lib/admin_pages.dart",
    """  Widget _actionsForStatus({
    required String status,
    required String id,
  }) {
    if (status == 'approved' || status == 'rejected') {""",
    """  Widget _actionsForStatus({
    required String status,
    required String id,
  }) {
    if (widget.collection == 'support_requests') {
      return _supportActions(status: status, id: id);
    }
    if (status == 'approved' || status == 'rejected') {""",
    "separate support actions from place actions",
)

# Support section mapping reuses three visual chips but with support semantics.
replace_once(
    "lib/admin_pages.dart",
    """  bool _matchesSection(String status) {
    switch (_section) {
      case 'approved':
        return status == 'approved';
      case 'rejected':
        return status == 'rejected';
      default:
        return status != 'approved' && status != 'rejected';
    }
  }""",
    """  bool _matchesSection(String status) {
    if (widget.collection == 'support_requests') {
      switch (_section) {
        case 'approved':
          return status == 'replied';
        case 'rejected':
          return status == 'closed';
        default:
          return status == 'new' || status == 'in_progress';
      }
    }
    switch (_section) {
      case 'approved':
        return status == 'approved';
      case 'rejected':
        return status == 'rejected';
      default:
        return status != 'approved' && status != 'rejected';
    }
  }""",
    "support section matching",
)

replace_once(
    "lib/admin_pages.dart",
    """      if (section == 'approved') return status == 'approved';
      if (section == 'rejected') return status == 'rejected';
      return status != 'approved' && status != 'rejected';""",
    """      if (widget.collection == 'support_requests') {
        if (section == 'approved') return status == 'replied';
        if (section == 'rejected') return status == 'closed';
        return status == 'new' || status == 'in_progress';
      }
      if (section == 'approved') return status == 'approved';
      if (section == 'rejected') return status == 'rejected';
      return status != 'approved' && status != 'rejected';""",
    "support section counts",
)

replace_once(
    "lib/admin_pages.dart",
    """                      value: 'approved',
                      arLabel: 'المعتمدات',
                      enLabel: 'Approved',""",
    """                      value: 'approved',
                      arLabel: widget.collection == 'support_requests' ? 'تم الرد' : 'المعتمدات',
                      enLabel: widget.collection == 'support_requests' ? 'Replied' : 'Approved',""",
    "support replied chip label",
)
replace_once(
    "lib/admin_pages.dart",
    """                      value: 'rejected',
                      arLabel: 'المرفوضات',
                      enLabel: 'Rejected',""",
    """                      value: 'rejected',
                      arLabel: widget.collection == 'support_requests' ? 'المغلقة' : 'المرفوضات',
                      enLabel: widget.collection == 'support_requests' ? 'Closed' : 'Rejected',""",
    "support closed chip label",
)

replace_once(
    "lib/admin_pages.dart",
    "                              _requestDetails(data),",
    "                              _requestDetails(data, doc.id),",
    "pass request id into admin details",
)

print("DEDA 10-point patch completed successfully.")
