import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';

class DedaBackend {
  static bool get isReady => Firebase.apps.isNotEmpty;

  static Future<User> _ensurePublicUser() async {
    if (!isReady) throw StateError('firebase-not-ready');
    final auth = FirebaseAuth.instance;
    final currentUser = auth.currentUser;
    if (currentUser != null) return currentUser;
    final credential = await auth.signInAnonymously();
    if (credential.user == null) throw StateError('anonymous-auth-failed');
    return credential.user!;
  }

  static Future<Map<String, String>> _adminIdentity() async {
    if (!isReady) throw StateError('firebase-not-ready');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('admin-not-signed-in');
    }
    final admin = await FirebaseFirestore.instance
        .collection('admins')
        .doc(user.uid)
        .get();
    final data = admin.data();
    if (!admin.exists || data?['active'] != true) {
      throw StateError('admin-not-authorized');
    }
    final configuredName =
        (data?['displayName'] ?? data?['name'] ?? '').toString().trim();
    final configuredRole =
        (data?['role'] ?? data?['jobTitle'] ?? 'manager').toString().trim();
    return <String, String>{
      'uid': user.uid,
      'name': configuredName.isNotEmpty
          ? configuredName
          : (user.email?.trim().isNotEmpty == true
              ? user.email!.trim()
              : 'DEDA Admin'),
      'role': configuredRole.isEmpty ? 'manager' : configuredRole,
    };
  }

  static bool _hasRequiredPlaceData(Map<String, dynamic> data) {
    const requiredTextFields = [
      'placeName',
      'phone',
      'governorate',
      'address',
      'openingHours',
      'description',
    ];
    final hasText = requiredTextFields.every(
      (key) => data[key]?.toString().trim().isNotEmpty == true,
    );
    final hasLocation = data['latitude'] is num && data['longitude'] is num;
    final hasCategory = data['category']?.toString().trim().isNotEmpty == true;
    final hasCustomType = data['category'] != 'other' ||
        data['otherCategoryText']?.toString().trim().isNotEmpty == true;
    return hasText && hasLocation && hasCategory && hasCustomType;
  }

  // DEDA 10-point fixes v1: unified user identity + robust support uploads.
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
  }

  static Future<String> submitPlace(Map<String, dynamic> data) async {
    if (!_hasRequiredPlaceData(data)) {
      throw ArgumentError('incomplete-place-request');
    }
    final user = await _ensurePublicUser();
    if (await _hasActivePlaceRequest(user.uid)) {
      throw StateError('active-place-request');
    }
    await registerOwnerNotifications();
    final request =
        FirebaseFirestore.instance.collection('place_requests').doc();
    await request.set({
      ...data,
      'ownerUid': user.uid,
      'requestType': 'create',
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return request.id;
  }

  static Future<String> submitPlaceEdit({
    required String originalPlaceId,
    required Map<String, dynamic> data,
  }) async {
    if (!_hasRequiredPlaceData(data)) {
      throw ArgumentError('incomplete-place-request');
    }
    final user = await _ensurePublicUser();
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
      'requestType': 'update',
      'originalPlaceId': originalPlaceId,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return request.id;
  }

  static Future<Map<String, dynamic>?> ownerRequestById(String id) async {
    final user = await _ensurePublicUser();
    final snapshot = await FirebaseFirestore.instance
        .collection('place_requests')
        .doc(id)
        .get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null || data['ownerUid'] != user.uid) {
      return null;
    }
    return {'id': snapshot.id, ...data};
  }

  static Future<Map<String, dynamic>?> publishedPlaceById(String id) async {
    if (!isReady) return null;
    final snapshot = await FirebaseFirestore.instance
        .collection('published_places')
        .doc(id)
        .get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    return {'id': snapshot.id, ...data};
  }

  static Future<void> registerOwnerNotifications() async {
    final user = await _ensurePublicUser();
    await FirebaseMessaging.instance.requestPermission();
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
      'lastSeenAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> updateOwnerAvailability({
    required String placeId,
    required bool isAvailableNow,
  }) async {
    await _ensurePublicUser();
    await FirebaseFirestore.instance
        .collection('published_places')
        .doc(placeId)
        .update({
      'isAvailableNow': isAvailableNow,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<bool> signInAdmin({
    required String email,
    required String password,
  }) async {
    if (!isReady) throw StateError('firebase-not-ready');
    final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final uid = credential.user?.uid;
    if (uid == null) return false;
    final admin =
        await FirebaseFirestore.instance.collection('admins').doc(uid).get();
    if (admin.exists && admin.data()?['active'] == true) {
      await registerAdminNotifications();
      return true;
    }
    await FirebaseAuth.instance.signOut();
    return false;
  }

  static Future<bool> currentUserIsAdmin() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (!isReady ||
        uid == null ||
        FirebaseAuth.instance.currentUser!.isAnonymous) {
      return false;
    }
    final admin =
        await FirebaseFirestore.instance.collection('admins').doc(uid).get();
    return admin.exists && admin.data()?['active'] == true;
  }

  static Future<void> registerAdminNotifications() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    await FirebaseMessaging.instance.requestPermission();
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    await FirebaseFirestore.instance.collection('admins').doc(user.uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
      'lastSeenAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> supportRequests() {
    return FirebaseFirestore.instance
        .collection('support_requests')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> placeRequests() {
    return FirebaseFirestore.instance
        .collection('place_requests')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots();
  }

  static Future<List<Map<String, dynamic>>> publishedPlaces() async {
    if (!isReady) return const [];
    final snapshot = await FirebaseFirestore.instance
        .collection('published_places')
        .where('published', isEqualTo: true)
        .limit(500)
        .get();
    return snapshot.docs
        .map((document) => {'id': document.id, ...document.data()})
        .toList();
  }

  static Future<void> markRequestViewed({
    required String collection,
    required String id,
  }) async {
    final actor = await _adminIdentity();
    final firestore = FirebaseFirestore.instance;
    final request = firestore.collection(collection).doc(id);
    await firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(request);
      if (!snapshot.exists) throw StateError('request-not-found');
      final data = snapshot.data() ?? <String, dynamic>{};
      final update = <String, dynamic>{
        'lastViewedAt': FieldValue.serverTimestamp(),
        'lastViewedByUid': actor['uid'],
        'lastViewedByName': actor['name'],
        'lastViewedByRole': actor['role'],
      };
      if (data['firstViewedAt'] == null) {
        update.addAll({
          'firstViewedAt': FieldValue.serverTimestamp(),
          'firstViewedByUid': actor['uid'],
          'firstViewedByName': actor['name'],
          'firstViewedByRole': actor['role'],
        });
      }
      transaction.update(request, update);
    });
  }

  static String _formatApprovalDate(DateTime value) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year}';
  }

  static String _approvalMessage({
    required String placeName,
    required String approvalNumber,
    required String approvalDate,
  }) {
    return 'تم اعتماد: $placeName\n'
        'رقم الاعتماد: $approvalNumber\n'
        'تاريخ الاعتماد: $approvalDate\n'
        'DEDA - الدليل الدقيق';
  }

  static Future<Map<String, dynamic>> preparePlaceApproval(String id) async {
    final actor = await _adminIdentity();
    final firestore = FirebaseFirestore.instance;
    final request = firestore.collection('place_requests').doc(id);
    final counter = firestore.collection('system_counters').doc('place_approval');

    return firestore.runTransaction<Map<String, dynamic>>((transaction) async {
      final requestSnapshot = await transaction.get(request);
      if (!requestSnapshot.exists) throw StateError('place-request-not-found');
      final data = requestSnapshot.data()!;
      if (!_hasRequiredPlaceData(data)) {
        throw StateError('incomplete-place-request');
      }

      var approvalNumber = (data['approvalNumber'] ?? '').toString().trim();
      var approvalDate = (data['approvalDate'] ?? '').toString().trim();
      if (approvalNumber.isEmpty) {
        final counterSnapshot = await transaction.get(counter);
        final current = (counterSnapshot.data()?['value'] as num?)?.toInt() ?? 0;
        final next = current + 1;
        final now = DateTime.now();
        approvalNumber = 'DEDA-${now.year}-${next.toString().padLeft(7, '0')}';
        approvalDate = _formatApprovalDate(now);
        transaction.set(
          counter,
          {'value': next, 'updatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );
      }
      if (approvalDate.isEmpty) {
        approvalDate = _formatApprovalDate(DateTime.now());
      }
      final placeName = (data['placeName'] ?? '').toString().trim();
      final message = _approvalMessage(
        placeName: placeName,
        approvalNumber: approvalNumber,
        approvalDate: approvalDate,
      );
      transaction.update(request, {
        'approvalNumber': approvalNumber,
        'approvalDate': approvalDate,
        'approvalMessageDraft': message,
        'approvalPreparedAt': FieldValue.serverTimestamp(),
        'approvalPreparedByUid': actor['uid'],
        'approvalPreparedByName': actor['name'],
      });
      return {
        'approvalNumber': approvalNumber,
        'approvalDate': approvalDate,
        'placeName': placeName,
        'message': message,
      };
    });
  }

  static Future<void> finalizePlaceApproval({
    required String id,
    required String message,
  }) async {
    final actor = await _adminIdentity();
    final firestore = FirebaseFirestore.instance;
    final request = firestore.collection('place_requests').doc(id);

    await firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(request);
      if (!snapshot.exists) throw StateError('place-request-not-found');
      final data = snapshot.data()!;
      if (!_hasRequiredPlaceData(data)) {
        throw StateError('incomplete-place-request');
      }
      final approvalNumber = (data['approvalNumber'] ?? '').toString().trim();
      final approvalDate = (data['approvalDate'] ?? '').toString().trim();
      if (approvalNumber.isEmpty || approvalDate.isEmpty) {
        throw StateError('approval-not-prepared');
      }
      final cleanMessage = message.trim().isEmpty
          ? _approvalMessage(
              placeName: (data['placeName'] ?? '').toString(),
              approvalNumber: approvalNumber,
              approvalDate: approvalDate,
            )
          : message.trim();

      final originalPlaceId = (data['originalPlaceId'] ?? '').toString().trim();
      final publishedId = originalPlaceId.isNotEmpty ? originalPlaceId : id;
      final published = firestore.collection('published_places').doc(publishedId);

      transaction.update(request, {
        'status': 'approved',
        'updatedAt': FieldValue.serverTimestamp(),
        'reviewedBy': actor['uid'],
        'reviewedByName': actor['name'],
        'reviewedByRole': actor['role'],
        'decisionAction': 'approved',
        'decisionAt': FieldValue.serverTimestamp(),
        'decisionByUid': actor['uid'],
        'decisionByName': actor['name'],
        'decisionByRole': actor['role'],
        'decisionNote': '',
        'approvalMessage': cleanMessage,
      });

      transaction.set(
        published,
        {
          ...data,
          'requestId': publishedId,
          'sourceRequestId': id,
          'lastSourceRequestId': id,
          'published': true,
          'status': 'approved',
          'approvalNumber': approvalNumber,
          'approvalDate': approvalDate,
          'approvalMessage': cleanMessage,
          'approvedByUid': actor['uid'],
          'approvedByName': actor['name'],
          'approvedByRole': actor['role'],
          'publishedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  static Future<void> updateRequestStatus({
    required String collection,
    required String id,
    required String status,
    String? note,
  }) async {
    if (collection == 'place_requests' && status == 'approved') {
      final prepared = await preparePlaceApproval(id);
      await finalizePlaceApproval(id: id, message: prepared['message'].toString());
      return;
    }

    final actor = await _adminIdentity();
    final firestore = FirebaseFirestore.instance;
    final request = firestore.collection(collection).doc(id);
    final statusUpdate = <String, dynamic>{
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
      'reviewedBy': actor['uid'],
      'reviewedByName': actor['name'],
      'reviewedByRole': actor['role'],
    };
    if (status == 'rejected' || status == 'needs_changes') {
      statusUpdate.addAll({
        'decisionAction': status,
        'decisionAt': FieldValue.serverTimestamp(),
        'decisionByUid': actor['uid'],
        'decisionByName': actor['name'],
        'decisionByRole': actor['role'],
        'decisionNote': note?.trim() ?? '',
      });
    }
    await request.update(statusUpdate);
  }

  // DEDA 10-point fixes v1: support replies and read-only account review.
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
  }

  static Future<void> signOutAdmin() => FirebaseAuth.instance.signOut();
}
