import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';

class DedaBackend {
  static bool get isReady => Firebase.apps.isNotEmpty;

  static Future<User> _ensureUser() async {
    if (!isReady) throw StateError('firebase-not-ready');
    final auth = FirebaseAuth.instance;
    if (auth.currentUser != null) return auth.currentUser!;
    final credential = await auth.signInAnonymously();
    if (credential.user == null) throw StateError('anonymous-auth-failed');
    return credential.user!;
  }

  static Future<String> submitSupport({
    required String type,
    required String name,
    required String phone,
    required String message,
    String? imagePath,
  }) async {
    final user = await _ensureUser();
    final request = FirebaseFirestore.instance.collection('support_requests').doc();
    String? imageUrl;

    if (imagePath != null && imagePath.isNotEmpty) {
      final extension = imagePath.contains('.')
          ? imagePath.split('.').last.toLowerCase()
          : 'jpg';
      final reference = FirebaseStorage.instance
          .ref('support_uploads/${user.uid}/${request.id}.$extension');
      await reference.putFile(
        File(imagePath),
        SettableMetadata(contentType: 'image/$extension'),
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
    final user = await _ensureUser();
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
