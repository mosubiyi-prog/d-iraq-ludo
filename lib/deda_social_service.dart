import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'deda_backend.dart';

class DedaSocialProfile {
  final String publicId;
  final String ownerUid;
  final String displayName;
  final int avatarStyle;
  final int frameStyle;
  final int backgroundStyle;
  final int level;
  final List<String> badges;

  const DedaSocialProfile({
    required this.publicId,
    required this.ownerUid,
    required this.displayName,
    required this.avatarStyle,
    required this.frameStyle,
    required this.backgroundStyle,
    required this.level,
    required this.badges,
  });

  factory DedaSocialProfile.fromMap(Map<String, dynamic> data) {
    final rawBadges = data['badges'];
    return DedaSocialProfile(
      publicId: (data['publicId'] ?? '').toString(),
      ownerUid: (data['ownerUid'] ?? '').toString(),
      displayName: (data['displayName'] ?? 'DEDA').toString(),
      avatarStyle: ((data['avatarStyle'] as num?)?.toInt() ?? 0).clamp(0, 5),
      frameStyle: ((data['frameStyle'] as num?)?.toInt() ?? 0).clamp(0, 5),
      backgroundStyle:
          ((data['backgroundStyle'] as num?)?.toInt() ?? 0).clamp(0, 5),
      level: ((data['level'] as num?)?.toInt() ?? 1).clamp(1, 999),
      badges: rawBadges is List
          ? rawBadges.map((value) => value.toString()).take(12).toList()
          : const <String>[],
    );
  }
}

class DedaFriendshipRecord {
  final String id;
  final List<String> members;
  final String requesterUid;
  final String recipientUid;
  final String requesterPublicId;
  final String recipientPublicId;
  final String requesterName;
  final String recipientName;
  final String status;

  const DedaFriendshipRecord({
    required this.id,
    required this.members,
    required this.requesterUid,
    required this.recipientUid,
    required this.requesterPublicId,
    required this.recipientPublicId,
    required this.requesterName,
    required this.recipientName,
    required this.status,
  });

  factory DedaFriendshipRecord.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return DedaFriendshipRecord.fromMap(doc.id, doc.data());
  }

  factory DedaFriendshipRecord.fromMap(
    String id,
    Map<String, dynamic> data,
  ) {
    final rawMembers = data['members'];
    return DedaFriendshipRecord(
      id: id,
      members: rawMembers is List
          ? rawMembers.map((value) => value.toString()).toList()
          : const <String>[],
      requesterUid: (data['requesterUid'] ?? '').toString(),
      recipientUid: (data['recipientUid'] ?? '').toString(),
      requesterPublicId: (data['requesterPublicId'] ?? '').toString(),
      recipientPublicId: (data['recipientPublicId'] ?? '').toString(),
      requesterName: (data['requesterName'] ?? 'DEDA').toString(),
      recipientName: (data['recipientName'] ?? 'DEDA').toString(),
      status: (data['status'] ?? '').toString(),
    );
  }

  String otherUid(String myUid) =>
      requesterUid == myUid ? recipientUid : requesterUid;

  String otherPublicId(String myUid) => requesterUid == myUid
      ? recipientPublicId
      : requesterPublicId;

  String otherName(String myUid) =>
      requesterUid == myUid ? recipientName : requesterName;
}

class DedaSocialSession {
  final String uid;
  final String publicId;
  final DedaSocialProfile profile;

  const DedaSocialSession({
    required this.uid,
    required this.publicId,
    required this.profile,
  });
}

class DedaSocialService {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static String normalizePublicId(String raw) {
    var value = raw.trim().toUpperCase().replaceAll(' ', '');
    if (value.isNotEmpty && !value.startsWith('@')) value = '@$value';
    return value;
  }

  static bool looksLikePersonalId(String value) =>
      RegExp(r'^@DEDA-[A-Z0-9]{5,12}$').hasMatch(normalizePublicId(value));

  static String _pairKey(String firstUid, String secondUid) {
    final values = <String>[firstUid, secondUid]..sort();
    return '${values[0]}__${values[1]}';
  }

  static Future<DedaSocialSession> ensurePersonalSession({
    required String name,
    required String phone,
    required String accountType,
    required bool hasApprovedPlace,
    required int avatarStyle,
    required int frameStyle,
    required int backgroundStyle,
    required int level,
    List<String> badges = const <String>[],
  }) async {
    final identity = await DedaBackend.ensureLocationShareIdentity(
      name: name,
      phone: phone,
      hasApprovedPlace: hasApprovedPlace,
      accountType: accountType,
    );
    final publicId = normalizePublicId(identity['personalId'] ?? '');
    if (publicId.isEmpty) throw StateError('social-personal-id-missing');

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('social-session-missing');

    final profileRef = _db.collection('deda_social_profiles').doc(publicId);
    final existing = await profileRef.get();
    await profileRef.set(<String, dynamic>{
      'publicId': publicId,
      'ownerUid': user.uid,
      'displayName': name.trim().isEmpty ? 'DEDA' : name.trim(),
      'avatarStyle': avatarStyle.clamp(0, 5),
      'frameStyle': frameStyle.clamp(0, 5),
      'backgroundStyle': backgroundStyle.clamp(0, 5),
      'level': level.clamp(1, 999),
      'badges': badges.take(12).toList(),
      if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return DedaSocialSession(
      uid: user.uid,
      publicId: publicId,
      profile: DedaSocialProfile(
        publicId: publicId,
        ownerUid: user.uid,
        displayName: name.trim().isEmpty ? 'DEDA' : name.trim(),
        avatarStyle: avatarStyle.clamp(0, 5),
        frameStyle: frameStyle.clamp(0, 5),
        backgroundStyle: backgroundStyle.clamp(0, 5),
        level: level.clamp(1, 999),
        badges: badges.take(12).toList(),
      ),
    );
  }

  static Future<DedaSocialProfile?> findByPublicId(String raw) async {
    final publicId = normalizePublicId(raw);
    if (!looksLikePersonalId(publicId)) return null;

    final directory = await _db.collection('deda_share_ids').doc(publicId).get();
    final directoryData = directory.data();
    if (!directory.exists ||
        directoryData == null ||
        directoryData['active'] != true ||
        directoryData['kind'] != 'personal') {
      return null;
    }

    final profile =
        await _db.collection('deda_social_profiles').doc(publicId).get();
    final data = profile.data();
    if (data != null) return DedaSocialProfile.fromMap(data);

    return DedaSocialProfile(
      publicId: publicId,
      ownerUid: (directoryData['ownerUid'] ?? '').toString(),
      displayName: (directoryData['displayName'] ?? 'DEDA').toString(),
      avatarStyle: 0,
      frameStyle: 0,
      backgroundStyle: 0,
      level: 1,
      badges: const <String>[],
    );
  }

  static Stream<List<DedaFriendshipRecord>> watchRelations(String uid) {
    if (uid.isEmpty) return Stream.value(const <DedaFriendshipRecord>[]);
    return _db
        .collection('deda_friendships')
        .where('members', arrayContains: uid)
        .snapshots()
        .map((snapshot) {
      final items = snapshot.docs
          .map(DedaFriendshipRecord.fromDoc)
          .where((item) => item.members.contains(uid))
          .toList();
      items.sort((a, b) => a.otherName(uid).compareTo(b.otherName(uid)));
      return items;
    });
  }

  static Future<String> sendFriendRequest({
    required DedaSocialSession sender,
    required DedaSocialProfile target,
  }) async {
    if (target.ownerUid.isEmpty) throw StateError('social-target-missing');
    if (target.ownerUid == sender.uid || target.publicId == sender.publicId) {
      throw StateError('social-self-request');
    }

    final pairKey = _pairKey(sender.uid, target.ownerUid);
    final ref = _db.collection('deda_friendships').doc(pairKey);
    final existing = await ref.get();
    final existingData = existing.data();
    if (existingData != null) {
      final status = (existingData['status'] ?? '').toString();
      if (status == 'accepted') throw StateError('social-already-friends');
      if (status == 'pending') throw StateError('social-request-pending');
      if (status == 'rejected') {
        await ref.delete();
      }
    }

    await ref.set(<String, dynamic>{
      'pairKey': pairKey,
      'members': <String>[sender.uid, target.ownerUid],
      'requesterUid': sender.uid,
      'recipientUid': target.ownerUid,
      'requesterPublicId': sender.publicId,
      'recipientPublicId': target.publicId,
      'requesterName': sender.profile.displayName,
      'recipientName': target.displayName,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return pairKey;
  }

  static Future<void> respondToRequest({
    required String relationId,
    required bool accept,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('social-session-missing');
    final ref = _db.collection('deda_friendships').doc(relationId);
    final snapshot = await ref.get();
    final data = snapshot.data();
    if (data == null || data['recipientUid'] != user.uid) {
      throw StateError('social-request-not-owned');
    }
    if (data['status'] != 'pending') {
      throw StateError('social-request-not-pending');
    }
    await ref.update(<String, dynamic>{
      'status': accept ? 'accepted' : 'rejected',
      'respondedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> removeRelation(String relationId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('social-session-missing');
    final ref = _db.collection('deda_friendships').doc(relationId);
    final snapshot = await ref.get();
    final data = snapshot.data();
    final members = data?['members'];
    if (members is! List || !members.contains(user.uid)) {
      throw StateError('social-relation-not-owned');
    }
    await ref.delete();
  }

  static Future<DedaSocialProfile?> profileForFriend(
    DedaFriendshipRecord relation,
    String myUid,
  ) async {
    if (relation.status != 'accepted' || !relation.members.contains(myUid)) {
      return null;
    }
    return findByPublicId(relation.otherPublicId(myUid));
  }
}
