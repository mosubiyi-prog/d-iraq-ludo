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
    if (currentUser != null && currentUser.isAnonymous) return currentUser;
    if (currentUser != null) {
      await auth.signOut();
    }
    final credential = await auth.signInAnonymously();
    if (credential.user == null) throw StateError('anonymous-auth-failed');
    return credential.user!;
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
    final request = FirebaseFirestore.instance.collection('support_requests').doc();
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
    final request = FirebaseFirestore.instance.collection('place_requests').doc();
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
    final admin = await FirebaseFirestore.instance.collection('admins').doc(uid).get();
    if (admin.exists && admin.data()?['active'] == true) {
      await registerAdminNotifications();
      return true;
    }
    await FirebaseAuth.instance.signOut();
    return false;
  }

  static Future<bool> currentUserIsAdmin() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (!isReady || uid == null || FirebaseAuth.instance.currentUser!.isAnonymous) {
      return false;
    }
    final admin = await FirebaseFirestore.instance.collection('admins').doc(uid).get();
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

  static Future<void> updateRequestStatus({
    required String collection,
    required String id,
    required String status,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final request = firestore.collection(collection).doc(id);
    if (collection == 'place_requests') {
      final snapshot = await request.get();
      if (!snapshot.exists) throw StateError('place-request-not-found');
      if (status == 'approved' && !_hasRequiredPlaceData(snapshot.data()!)) {
        throw StateError('incomplete-place-request');
      }
      final batch = firestore.batch();
      batch.update(request, {
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
        'reviewedBy': FirebaseAuth.instance.currentUser?.uid,
      });
      final published = firestore.collection('published_places').doc(id);
      if (status == 'approved') {
        final data = snapshot.data()!;
        batch.set(published, {
          ...data,
          'requestId': id,
          'published': true,
          'publishedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else if (status == 'rejected') {
        batch.delete(published);
      }
      await batch.commit();
      return;
    }
    await request.update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
      'reviewedBy': FirebaseAuth.instance.currentUser?.uid,
    });
  }

  static Future<void> signOutAdmin() => FirebaseAuth.instance.signOut();
}
