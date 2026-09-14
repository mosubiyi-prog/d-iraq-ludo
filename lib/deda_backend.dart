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
    final request =
        FirebaseFirestore.instance.collection('place_requests').doc();
    await request.set({
      ...data,
      'ownerUid': user.uid,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return request.id;
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

  static Future<void> updateRequestStatus({
    required String collection,
    required String id,
    required String status,
    String? note,
  }) async {
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

    if (status == 'approved' || status == 'rejected') {
      statusUpdate.addAll({
        'decisionAction': status,
        'decisionAt': FieldValue.serverTimestamp(),
        'decisionByUid': actor['uid'],
        'decisionByName': actor['name'],
        'decisionByRole': actor['role'],
        'decisionNote': note?.trim() ?? '',
      });
    }

    if (collection == 'place_requests') {
      final snapshot = await request.get();
      if (!snapshot.exists) throw StateError('place-request-not-found');
      final requestData = snapshot.data()!;

      if (status == 'approved' && !_hasRequiredPlaceData(requestData)) {
        throw StateError('incomplete-place-request');
      }

      final batch = firestore.batch();
      batch.update(request, statusUpdate);

      final published = firestore.collection('published_places').doc(id);
      if (status == 'approved') {
        batch.set(published, {
          ...requestData,
          'requestId': id,
          'published': true,
          'approvedByUid': actor['uid'],
          'approvedByName': actor['name'],
          'approvedByRole': actor['role'],
          'publishedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        batch.delete(published);
      }

      await batch.commit();
      return;
    }

    await request.update(statusUpdate);
  }

  static Future<void> signOutAdmin() => FirebaseAuth.instance.signOut();
}
