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

  static Future<String> submitSupport({
    required String type,
    required String name,
    required String phone,
    required String message,
    String? imagePath,
  }) async {
    final user = await _ensurePublicUser();
    final request =
        FirebaseFirestore.instance.collection('support_requests').doc();
    String? imageUrl;
    if (imagePath != null && imagePath.isNotEmpty) {
      final extension = imagePath.contains('.')
          ? imagePath.split('.').last.toLowerCase()
          : 'jpg';
      final reference = FirebaseStorage.instance
          .ref('support_uploads/${user.uid}/${request.id}.$extension');
      final contentType = switch (extension) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        _ => 'image/jpeg',
      };
      await reference.putFile(
        File(imagePath),
        SettableMetadata(contentType: contentType),
      );
      imageUrl = await reference.getDownloadURL();
    }
    await request.set({
      'ownerUid': user.uid,
      'type': type,
      'name': name,
      'phone': phone,
      'message': message,
      'imageUrl': imageUrl,
      'status': 'new',
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
        approvalNumber = 'DEDA-${now.year}-${next.toString().padLeft(6, '0')}';
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

  static Future<void> signOutAdmin() => FirebaseAuth.instance.signOut();
}
