import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';

class DedaBackend {
  static bool get isReady => Firebase.apps.isNotEmpty;

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

  static Future<User> _ensurePublicUser() async {
    if (!isReady) throw StateError('firebase-not-ready');
    final auth = FirebaseAuth.instance;
    final currentUser = auth.currentUser;
    if (currentUser != null) return currentUser;
    final credential = await auth.signInAnonymously();
    if (credential.user == null) throw StateError('anonymous-auth-failed');
    return credential.user!;
  }

  static String normalizeAdminRole(dynamic value) {
    final raw = (value ?? '').toString().trim().toLowerCase();
    if (raw.isEmpty ||
        raw == 'manager' ||
        raw == 'director' ||
        raw == 'admin' ||
        raw == 'general_manager') {
      return 'general_manager';
    }
    if (raw == 'assistant' ||
        raw == 'assistant_manager' ||
        raw == 'assistant-manager' ||
        raw == 'deputy_manager') {
      return 'deputy_manager';
    }
    if (raw == 'staff' || raw == 'employee') return 'employee';
    if (raw == 'agent' ||
        raw == 'governorate_agent' ||
        raw == 'province_agent') {
      return 'province_agent';
    }
    return raw;
  }

  static String normalizeAdminStatus(Map<String, dynamic>? data) {
    if (data == null) return 'disabled';
    final raw = (data['status'] ?? '').toString().trim().toLowerCase();
    if (raw == 'active' ||
        raw == 'temporarily_stopped' ||
        raw == 'disabled') {
      return raw;
    }
    return data['active'] == true ? 'active' : 'disabled';
  }

  static bool adminHasPermission(
    Map<String, dynamic>? profile,
    String permission,
  ) {
    if (profile == null) return false;
    final role = normalizeAdminRole(profile['role'] ?? profile['jobTitle']);
    if (role == 'general_manager') return true;
    final permissions = profile['permissions'];
    return permissions is Map && permissions[permission] == true;
  }

  static Future<Map<String, dynamic>> currentAdminProfile() async {
    if (!isReady) throw StateError('firebase-not-ready');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('admin-not-signed-in');
    }

    final ref =
        FirebaseFirestore.instance.collection('admins').doc(user.uid);
    var snapshot = await ref.get();
    var data = snapshot.data();
    if (!snapshot.exists ||
        data?['active'] != true ||
        normalizeAdminStatus(data) != 'active') {
      throw StateError('admin-not-authorized');
    }

    final role = normalizeAdminRole(data?['role'] ?? data?['jobTitle']);
    return <String, dynamic>{
      ...?data,
      'uid': user.uid,
      'email': user.email ?? data?['email'] ?? '',
      'displayName':
          (data?['displayName'] ?? data?['name'] ?? user.email ?? 'DEDA Admin')
              .toString(),
      'role': role,
      'status': normalizeAdminStatus(data),
      'roleNormalized': role,
    };
  }

  static Future<Map<String, String>> _adminIdentity() async {
    final data = await currentAdminProfile();
    return <String, String>{
      'uid': data['uid'].toString(),
      'name': data['displayName'].toString(),
      'role': normalizeAdminRole(data['role']),
    };
  }

  static Future<void> _writeAdminAudit(
    String action, {
    Map<String, dynamic> details = const <String, dynamic>{},
  }) async {
    try {
      final actor = await _adminIdentity();
      await FirebaseFirestore.instance.collection('admin_audit').add({
        'action': action,
        'adminUid': actor['uid'],
        'adminName': actor['name'],
        'adminRole': actor['role'],
        ...details,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
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
      'accountKey': accountKeyForPhone(phone),
      'accountType': accountType.trim(),
      if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastSeenAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<bool> _hasActivePlaceRequest(
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
    } catch (_) {}

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
      'accountKey': accountKey,
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


  static int _hazardLifetimeHours(String type) {
    switch (type) {
      case 'congestion':
        return 1;
      case 'accident':
      case 'road_object':
        return 2;
      case 'checkpoint':
        return 4;
      case 'flooded':
        return 6;
      case 'detour':
      case 'roadworks':
      case 'maintenance':
        return 12;
      case 'bump':
      case 'speed_camera':
        return 24 * 30;
      default:
        return 6;
    }
  }

  static const Set<String> _hazardTypes = <String>{
    'bump',
    'roadworks',
    'maintenance',
    'detour',
    'speed_camera',
    'checkpoint',
    'accident',
    'congestion',
    'road_object',
    'flooded',
  };

  static Future<List<Map<String, dynamic>>> roadHazards() async {
    if (!isReady) return const <Map<String, dynamic>>[];
    await _ensurePublicUser();
    final snapshot = await FirebaseFirestore.instance
        .collection('road_hazards')
        .where('status', isEqualTo: 'active')
        .limit(500)
        .get();
    final now = DateTime.now().millisecondsSinceEpoch;
    final items = <Map<String, dynamic>>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final expiresAt = data['expiresAt'];
      final expiresMillis =
          expiresAt is Timestamp ? expiresAt.millisecondsSinceEpoch : 0;
      final resolved = (data['resolvedReports'] as num?)?.toInt() ?? 0;
      if (expiresMillis > 0 && expiresMillis <= now) continue;
      if (resolved >= 3) continue;
      items.add(<String, dynamic>{
        'id': doc.id,
        ...data,
        'expiresAtMillis': expiresMillis,
      });
    }
    return items;
  }

  static Future<String> submitRoadHazard({
    required String type,
    required double latitude,
    required double longitude,
    double? heading,
  }) async {
    if (!_hazardTypes.contains(type)) {
      throw ArgumentError('invalid-road-hazard-type');
    }
    if (latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw ArgumentError('invalid-road-hazard-location');
    }

    final user = await _ensurePublicUser();
    final expires =
        DateTime.now().add(Duration(hours: _hazardLifetimeHours(type)));
    final ref =
        FirebaseFirestore.instance.collection('road_hazards').doc();
    await ref.set(<String, dynamic>{
      'reporterUid': user.uid,
      'type': type,
      'latitude': latitude,
      'longitude': longitude,
      'heading': heading,
      'status': 'active',
      'confirmations': 1,
      'resolvedReports': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastConfirmedAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expires),
    });
    return ref.id;
  }

  static Future<void> voteRoadHazard({
    required String id,
    required String type,
    required bool present,
  }) async {
    if (!_hazardTypes.contains(type)) {
      throw ArgumentError('invalid-road-hazard-type');
    }
    await _ensurePublicUser();
    final ref =
        FirebaseFirestore.instance.collection('road_hazards').doc(id);
    if (present) {
      final expires =
          DateTime.now().add(Duration(hours: _hazardLifetimeHours(type)));
      await ref.update(<String, dynamic>{
        'confirmations': FieldValue.increment(1),
        'lastConfirmedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expires),
      });
    } else {
      await ref.update(<String, dynamic>{
        'resolvedReports': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
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
    final data = admin.data();
    if (admin.exists) {
      final status = normalizeAdminStatus(data);
      if (data?['active'] != true || status != 'active') {
        await FirebaseAuth.instance.signOut();
        if (status == 'temporarily_stopped') {
          throw StateError('admin-temporarily-stopped');
        }
        throw StateError('admin-disabled');
      }

      await FirebaseFirestore.instance.collection('admins').doc(uid).set({
        'lastSeenAt': FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await registerAdminNotifications();
      await _writeAdminAudit('admin_signed_in');
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
    final data = admin.data();
    return admin.exists &&
        data?['active'] == true &&
        normalizeAdminStatus(data) == 'active';
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

  static Stream<QuerySnapshot<Map<String, dynamic>>> placeRequestsForAdmin(
    Map<String, dynamic> adminProfile,
  ) {
    final role = normalizeAdminRole(
      adminProfile['roleNormalized'] ?? adminProfile['role'],
    );
    final collection = FirebaseFirestore.instance.collection('place_requests');
    if (role == 'province_agent') {
      final governorate =
          (adminProfile['governorate'] ?? '').toString().trim();
      if (governorate.isEmpty) {
        return collection
            .where('governorate', isEqualTo: '__no_governorate__')
            .limit(1)
            .snapshots();
      }
      return collection
          .where('governorate', isEqualTo: governorate)
          .limit(100)
          .snapshots();
    }
    return collection
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> supportRequestsForAdmin(
    Map<String, dynamic> adminProfile,
  ) {
    return FirebaseFirestore.instance
        .collection('support_requests')
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
    await _writeAdminAudit(
      'request_viewed',
      details: <String, dynamic>{
        'sourceCollection': collection,
        'sourceId': id,
      },
    );
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
    await _writeAdminAudit(
      'place_approved',
      details: <String, dynamic>{
        'sourceCollection': 'place_requests',
        'sourceId': id,
      },
    );
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

    if ((status == 'rejected' || status == 'needs_changes') &&
        (note == null || note.trim().isEmpty)) {
      throw ArgumentError('reason-required');
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
    await _writeAdminAudit(
      collection == 'place_requests'
          ? 'place_status_changed'
          : 'request_status_changed',
      details: <String, dynamic>{
        'sourceCollection': collection,
        'sourceId': id,
        'newStatus': status,
        if (note != null && note.trim().isNotEmpty) 'reason': note.trim(),
      },
    );
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

  static Future<List<Map<String, dynamic>>> mySupportRequests({
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
    await _writeAdminAudit(
      'support_status_changed',
      details: <String, dynamic>{
        'sourceCollection': 'support_requests',
        'sourceId': id,
        'newStatus': status,
      },
    );
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
    await _writeAdminAudit(
      'support_replied',
      details: <String, dynamic>{
        'sourceCollection': 'support_requests',
        'sourceId': id,
      },
    );
  }

  static Future<Map<String, dynamic>> adminUserSnapshot({
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
      // A single tap can occasionally trigger the same async open twice on a
      // slow device. Use a short deterministic bucket so concurrent duplicate
      // calls collapse into one audit record, while later genuine views still
      // create a new entry.
      final auditBucket = DateTime.now().millisecondsSinceEpoch ~/ 5000;
      final auditId =
          'read_${actor['uid']}_${ownerUid}_$auditBucket';
      await firestore.collection('admin_audit').doc(auditId).set({
        'action': 'read_user_account',
        'ownerUid': ownerUid,
        'accountKey': accountKey,
        'targetUserName': (profile['name'] ?? '').toString().trim(),
        'targetUserPhone':
            (profile['phone'] ?? sourcePhone).toString().trim(),
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

  static Stream<QuerySnapshot<Map<String, dynamic>>> adminMembers() {
    return FirebaseFirestore.instance
        .collection('admins')
        .limit(200)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> adminInvitations() {
    return FirebaseFirestore.instance
        .collection('admin_invites')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> adminAudit() {
    return FirebaseFirestore.instance
        .collection('admin_audit')
        .orderBy('createdAt', descending: true)
        .limit(300)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> adminUsers() {
    return FirebaseFirestore.instance
        .collection('users')
        .limit(200)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>>
      accountDeletionRequests() {
    return FirebaseFirestore.instance
        .collection('account_deletion_requests')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots();
  }

  static Future<String> submitAccountDeletionRequest({
    required String name,
    required String phone,
    String reason = '',
  }) async {
    final user = await _ensurePublicUser();
    final firestore = FirebaseFirestore.instance;
    final cleanName = name.trim();
    final cleanPhone = phone.trim();
    final accountKey = accountKeyForPhone(cleanPhone);
    final request = firestore.collection('account_deletion_requests').doc();

    await request.set(<String, dynamic>{
      'requesterUid': user.uid,
      'accountKey': accountKey,
      'name': cleanName,
      'phone': cleanPhone,
      'reason': reason.trim(),
      'status': 'new',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return request.id;
  }

  static Future<void> updateAccountDeletionRequestStatus({
    required String requestId,
    required String status,
    String note = '',
  }) async {
    final actor = await currentAdminProfile();
    if (normalizeAdminRole(actor['role']) != 'general_manager') {
      throw StateError('general-manager-required');
    }
    const allowed = <String>{
      'new',
      'reviewing',
      'deleted',
      'cancelled',
      'rejected',
    };
    if (!allowed.contains(status)) {
      throw ArgumentError('invalid-account-deletion-status');
    }

    final ref = FirebaseFirestore.instance
        .collection('account_deletion_requests')
        .doc(requestId);
    final snapshot = await ref.get();
    if (!snapshot.exists) {
      throw StateError('account-deletion-request-not-found');
    }
    final current = snapshot.data() ?? <String, dynamic>{};

    final update = <String, dynamic>{
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
      'reviewedByUid': actor['uid'].toString(),
      'reviewedByName': actor['displayName'].toString(),
      'reviewedByRole': normalizeAdminRole(actor['role']),
      'reviewNote': note.trim(),
    };
    if (status == 'deleted') {
      update['completedAt'] = FieldValue.serverTimestamp();
    }
    if (status == 'cancelled' || status == 'rejected') {
      update['closedAt'] = FieldValue.serverTimestamp();
    }

    await ref.update(update);
    await _writeAdminAudit(
      'account_deletion_status_changed',
      details: <String, dynamic>{
        'requestId': requestId,
        'targetUserUid': current['requesterUid'],
        'targetUserName': current['name'],
        'targetUserPhone': current['phone'],
        'oldStatus': current['status'],
        'newStatus': status,
        'note': note.trim(),
      },
    );
  }

  static String _newAdminInviteCode() {
    final random = Random.secure();
    return List<String>.generate(8, (_) => random.nextInt(10).toString()).join();
  }

  static Map<String, bool> _cleanAdminPermissions(
    Map<String, bool> permissions,
  ) {
    return <String, bool>{
      for (final entry in permissions.entries) entry.key: entry.value == true,
    };
  }

  static Future<Map<String, dynamic>> createAdminInvitation({
    required String displayName,
    required String email,
    required String role,
    required String department,
    required String governorate,
    required Map<String, bool> permissions,
    String phone = '',
  }) async {
    final actor = await currentAdminProfile();
    if (normalizeAdminRole(actor['role']) != 'general_manager') {
      throw StateError('general-manager-required');
    }

    final cleanName = displayName.trim();
    final cleanEmail = email.trim().toLowerCase();
    final cleanDepartment = department.trim();
    final cleanRole = normalizeAdminRole(role);
    final cleanGovernorate =
        cleanRole == 'province_agent' ? governorate.trim() : '';

    if (cleanName.isEmpty) throw ArgumentError('display-name-required');
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      throw ArgumentError('valid-email-required');
    }
    if (cleanDepartment.isEmpty) throw ArgumentError('department-required');
    if (!<String>{
      'general_manager',
      'deputy_manager',
      'employee',
      'province_agent',
    }.contains(cleanRole)) {
      throw ArgumentError('invalid-admin-role');
    }
    if (cleanRole == 'province_agent' && cleanGovernorate.isEmpty) {
      throw ArgumentError('governorate-required');
    }

    final firestore = FirebaseFirestore.instance;

    final existingAdmin = await firestore
        .collection('admins')
        .where('email', isEqualTo: cleanEmail)
        .limit(1)
        .get();
    if (existingAdmin.docs.isNotEmpty) {
      throw StateError('email-already-exists');
    }

    final existingInvite = await firestore
        .collection('admin_invites')
        .where('email', isEqualTo: cleanEmail)
        .limit(10)
        .get();
    if (existingInvite.docs.any((doc) {
      final status = (doc.data()['status'] ?? '').toString();
      return status == 'pending' || status == 'claimed';
    })) {
      throw StateError('invite-already-exists');
    }

    final inviteRef = firestore.collection('admin_invites').doc();
    final counterRef =
        firestore.collection('system_counters').doc('admin_members');
    final code = _newAdminInviteCode();
    final expiresAt = Timestamp.fromDate(
      DateTime.now().add(const Duration(days: 7)),
    );
    final cleanPermissions = _cleanAdminPermissions(permissions);

    late String adminId;
    await firestore.runTransaction((transaction) async {
      final counter = await transaction.get(counterRef);
      final current = (counter.data()?['value'] as num?)?.toInt() ?? 0;
      final next = current + 1;
      adminId = 'DEDA-ADM-${next.toString().padLeft(6, '0')}';

      transaction.set(
        counterRef,
        <String, dynamic>{
          'value': next,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      transaction.set(inviteRef, <String, dynamic>{
        'adminId': adminId,
        'displayName': cleanName,
        'email': cleanEmail,
        'phone': phone.trim(),
        'department': cleanDepartment,
        'role': cleanRole,
        'governorate': cleanGovernorate,
        'permissions': cleanPermissions,
        'status': 'pending',
        'activationCode': code,
        'createdByUid': actor['uid'].toString(),
        'createdByName': actor['displayName'].toString(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'expiresAt': expiresAt,
      });
    });

    await _writeAdminAudit(
      'admin_invite_created',
      details: <String, dynamic>{
        'inviteId': inviteRef.id,
        'targetAdminId': adminId,
        'targetAdminName': cleanName,
        'targetAdminRole': cleanRole,
        'targetEmail': cleanEmail,
        'targetGovernorate':
            cleanRole == 'province_agent' ? cleanGovernorate : null,
      },
    );

    return <String, dynamic>{
      'inviteId': inviteRef.id,
      'adminId': adminId,
      'email': cleanEmail,
      'activationCode': code,
      'expiresAt': expiresAt,
    };
  }

  static Future<void> cancelAdminInvitation(String inviteId) async {
    final actor = await currentAdminProfile();
    if (normalizeAdminRole(actor['role']) != 'general_manager') {
      throw StateError('general-manager-required');
    }
    final ref =
        FirebaseFirestore.instance.collection('admin_invites').doc(inviteId);
    final snapshot = await ref.get();
    if (!snapshot.exists) return;
    final data = snapshot.data() ?? <String, dynamic>{};
    await _writeAdminAudit(
      'admin_invite_cancelled',
      details: <String, dynamic>{
        'inviteId': inviteId,
        'targetAdminId': data['adminId'],
        'targetAdminName': data['displayName'],
        'targetEmail': data['email'],
      },
    );
    await ref.delete();
  }

  static Future<Map<String, dynamic>> activateAdminInvitation({
    required String inviteId,
    required String activationCode,
    required String email,
    required String password,
  }) async {
    if (!isReady) throw StateError('firebase-not-ready');
    final cleanInviteId = inviteId.trim();
    final cleanCode = activationCode.trim();
    final cleanEmail = email.trim().toLowerCase();
    if (cleanInviteId.isEmpty) throw ArgumentError('invite-id-required');
    if (!RegExp(r'^\d{8}$').hasMatch(cleanCode)) {
      throw ArgumentError('invalid-invite-code');
    }
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      throw ArgumentError('valid-email-required');
    }
    if (password.length < 8) throw ArgumentError('weak-password');

    final auth = FirebaseAuth.instance;
    UserCredential credential;
    try {
      credential = await auth.createUserWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );
    } catch (error) {
      rethrow;
    }

    final user = credential.user;
    if (user == null) {
      await auth.signOut();
      throw StateError('admin-account-create-failed');
    }

    final firestore = FirebaseFirestore.instance;
    final inviteRef =
        firestore.collection('admin_invites').doc(cleanInviteId);
    final adminRef = firestore.collection('admins').doc(user.uid);
    var claimed = false;
    var adminCreated = false;

    try {
      await inviteRef.update(<String, dynamic>{
        'status': 'claimed',
        'claimedUid': user.uid,
        'claimCode': cleanCode,
        'claimedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      claimed = true;

      final inviteSnapshot = await inviteRef.get();
      if (!inviteSnapshot.exists) throw StateError('invite-not-found');
      final invite = inviteSnapshot.data() ?? <String, dynamic>{};
      if ((invite['status'] ?? '').toString() != 'claimed' ||
          (invite['claimedUid'] ?? '').toString() != user.uid) {
        throw StateError('invite-not-claimed');
      }
      if ((invite['email'] ?? '').toString().trim().toLowerCase() != cleanEmail) {
        throw StateError('invite-email-mismatch');
      }

      final expiresAt = invite['expiresAt'];
      if (expiresAt is Timestamp && expiresAt.toDate().isBefore(DateTime.now())) {
        throw StateError('invite-expired');
      }

      final role = normalizeAdminRole(invite['role']);
      final permissions = invite['permissions'] is Map
          ? Map<String, dynamic>.from(invite['permissions'] as Map)
          : <String, dynamic>{};

      await adminRef.set(<String, dynamic>{
        'adminId': (invite['adminId'] ?? '').toString(),
        'displayName': (invite['displayName'] ?? '').toString(),
        'email': cleanEmail,
        'phone': (invite['phone'] ?? '').toString(),
        'department': (invite['department'] ?? '').toString(),
        'role': role,
        'governorate':
            role == 'province_agent' ? (invite['governorate'] ?? '').toString() : '',
        'status': 'active',
        'active': true,
        'permissions': permissions,
        'mustChangePassword': false,
        'inviteId': cleanInviteId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdByUid': (invite['createdByUid'] ?? '').toString(),
        'createdByName': (invite['createdByName'] ?? '').toString(),
        'permissionsUpdatedAt': FieldValue.serverTimestamp(),
        'permissionsUpdatedByUid': (invite['createdByUid'] ?? '').toString(),
        'permissionsUpdatedByName': (invite['createdByName'] ?? '').toString(),
        'lastSeenAt': FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
        'firstLoginCompletedAt': FieldValue.serverTimestamp(),
      });
      adminCreated = true;

      try {
        await inviteRef.update(<String, dynamic>{
          'status': 'completed',
          'acceptedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'activationCode': FieldValue.delete(),
          'claimCode': FieldValue.delete(),
        });
      } catch (_) {
        // The admin record is already secure and usable. Invite cleanup can
        // be completed later by the general manager if the network drops here.
      }

      try {
        await registerAdminNotifications();
      } catch (_) {}
      await _writeAdminAudit(
        'admin_invite_accepted',
        details: <String, dynamic>{
          'inviteId': cleanInviteId,
          'targetAdminId': invite['adminId'],
          'targetAdminName': invite['displayName'],
          'targetAdminRole': role,
        },
      );
      return currentAdminProfile();
    } catch (error) {
      if (!adminCreated) {
        if (claimed) {
          try {
            await inviteRef.update(<String, dynamic>{
              'status': 'pending',
              'claimedUid': FieldValue.delete(),
              'claimCode': FieldValue.delete(),
              'claimedAt': FieldValue.delete(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          } catch (_) {}
        }
        try {
          await user.delete();
        } catch (_) {}
        try {
          await auth.signOut();
        } catch (_) {}
      }
      rethrow;
    }
  }

  static Future<void> updateAdminMember({
    required String uid,
    required String displayName,
    required String role,
    required String department,
    required String governorate,
    required String status,
    required Map<String, bool> permissions,
    required String reason,
    String phone = '',
  }) async {
    final actor = await currentAdminProfile();
    if (normalizeAdminRole(actor['role']) != 'general_manager') {
      throw StateError('general-manager-required');
    }
    if (reason.trim().isEmpty) throw ArgumentError('reason-required');

    final ref = FirebaseFirestore.instance.collection('admins').doc(uid);
    final snapshot = await ref.get();
    if (!snapshot.exists) throw StateError('admin-member-not-found');
    final current = snapshot.data() ?? <String, dynamic>{};

    final newRole = normalizeAdminRole(role);
    final newStatus = status.trim().toLowerCase();
    if (!<String>{
      'general_manager',
      'deputy_manager',
      'employee',
      'province_agent',
    }.contains(newRole)) {
      throw ArgumentError('invalid-admin-role');
    }
    if (!<String>{
      'active',
      'temporarily_stopped',
      'disabled',
    }.contains(newStatus)) {
      throw ArgumentError('invalid-admin-status');
    }
    if (displayName.trim().isEmpty) {
      throw ArgumentError('display-name-required');
    }
    if (department.trim().isEmpty) {
      throw ArgumentError('department-required');
    }
    if (newRole == 'province_agent' && governorate.trim().isEmpty) {
      throw ArgumentError('governorate-required');
    }

    if (uid == actor['uid'].toString()) {
      final oldRole = normalizeAdminRole(current['role']);
      final oldStatus = normalizeAdminStatus(current);
      if (newRole != oldRole || newStatus != oldStatus) {
        throw StateError('cannot-change-current-admin-access');
      }
    }

    final cleanPermissions = _cleanAdminPermissions(permissions);
    await ref.update(<String, dynamic>{
      'displayName': displayName.trim(),
      'phone': phone.trim(),
      'department': department.trim(),
      'role': newRole,
      'governorate':
          newRole == 'province_agent' ? governorate.trim() : '',
      'status': newStatus,
      'active': newStatus == 'active',
      'permissions': cleanPermissions,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': actor['uid'].toString(),
      'updatedByName': actor['displayName'].toString(),
      'permissionsUpdatedAt': FieldValue.serverTimestamp(),
      'permissionsUpdatedByUid': actor['uid'].toString(),
      'permissionsUpdatedByName': actor['displayName'].toString(),
      'statusReason': reason.trim(),
      'statusUpdatedAt': FieldValue.serverTimestamp(),
      'statusUpdatedByUid': actor['uid'].toString(),
      'statusUpdatedByName': actor['displayName'].toString(),
    });

    await _writeAdminAudit(
      'admin_member_updated',
      details: <String, dynamic>{
        'targetAdminUid': uid,
        'targetAdminId': current['adminId'],
        'targetAdminName': displayName.trim(),
        'oldRole': normalizeAdminRole(current['role']),
        'newRole': newRole,
        'oldStatus': normalizeAdminStatus(current),
        'newStatus': newStatus,
        'reason': reason.trim(),
      },
    );
  }

  static Future<void> revokeAdminMemberSessions({
    required String uid,
    required String reason,
  }) async {
    final actor = await currentAdminProfile();
    if (normalizeAdminRole(actor['role']) != 'general_manager') {
      throw StateError('general-manager-required');
    }
    if (uid == actor['uid'].toString()) {
      throw StateError('cannot-stop-current-session');
    }
    if (reason.trim().isEmpty) throw ArgumentError('reason-required');

    final ref = FirebaseFirestore.instance.collection('admins').doc(uid);
    final snapshot = await ref.get();
    if (!snapshot.exists) throw StateError('admin-member-not-found');
    final data = snapshot.data() ?? <String, dynamic>{};

    await ref.update(<String, dynamic>{
      'status': 'temporarily_stopped',
      'active': false,
      'updatedAt': FieldValue.serverTimestamp(),
      'statusReason': reason.trim(),
      'statusUpdatedAt': FieldValue.serverTimestamp(),
      'statusUpdatedByUid': actor['uid'].toString(),
      'statusUpdatedByName': actor['displayName'].toString(),
    });
    await _writeAdminAudit(
      'admin_access_suspended',
      details: <String, dynamic>{
        'targetAdminUid': uid,
        'targetAdminId': data['adminId'],
        'targetAdminName': data['displayName'] ?? data['name'],
        'reason': reason.trim(),
      },
    );
  }

  static Future<void> sendAdminPasswordReset({
    required String email,
  }) async {
    final actor = await currentAdminProfile();
    if (normalizeAdminRole(actor['role']) != 'general_manager') {
      throw StateError('general-manager-required');
    }
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty) throw ArgumentError('valid-email-required');
    await FirebaseAuth.instance.sendPasswordResetEmail(email: cleanEmail);
    await _writeAdminAudit(
      'admin_password_reset_sent',
      details: <String, dynamic>{'targetEmail': cleanEmail},
    );
  }

  static Future<void> deleteAdminMember({
    required String uid,
    required String reason,
  }) async {
    final actor = await currentAdminProfile();
    if (normalizeAdminRole(actor['role']) != 'general_manager') {
      throw StateError('general-manager-required');
    }
    if (uid == actor['uid'].toString()) {
      throw StateError('cannot-delete-current-admin');
    }
    if (reason.trim().isEmpty) throw ArgumentError('reason-required');

    final ref = FirebaseFirestore.instance.collection('admins').doc(uid);
    final snapshot = await ref.get();
    if (!snapshot.exists) return;
    final data = snapshot.data() ?? <String, dynamic>{};
    await _writeAdminAudit(
      'admin_member_access_removed',
      details: <String, dynamic>{
        'targetAdminUid': uid,
        'targetAdminId': data['adminId'],
        'targetAdminName': data['displayName'] ?? data['name'],
        'targetAdminRole': normalizeAdminRole(data['role']),
        'reason': reason.trim(),
      },
    );
    await ref.delete();
  }

  static Future<void> changeCurrentAdminPassword(String newPassword) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('admin-not-signed-in');
    }
    await user.updatePassword(newPassword);
    await FirebaseFirestore.instance.collection('admins').doc(user.uid).update({
      'mustChangePassword': false,
      'firstLoginCompletedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deleteRoadHazardAsAdmin({
    required String id,
    required String reason,
  }) async {
    final actor = await _adminIdentity();
    final ref = FirebaseFirestore.instance.collection('road_hazards').doc(id);
    final snapshot = await ref.get();
    if (!snapshot.exists) return;
    await ref.delete();
    await _writeAdminAudit(
      'road_hazard_deleted',
      details: <String, dynamic>{
        'targetId': id,
        'reason': reason.trim(),
        'hazardType': snapshot.data()?['type'],
        'adminUid': actor['uid'],
      },
    );
  }

  static Future<void> signOutAdmin() async {
    try {
      await _writeAdminAudit('admin_signed_out');
    } catch (_) {}
    await FirebaseAuth.instance.signOut();
  }
}
