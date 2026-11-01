import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'deda_100431_linked_owner_session_policy.dart';
import 'deda_social_service.dart';

/// Step 2: source-only continuity of existing Firestore friendship relations.
/// Nothing here sends friend requests, rewrites old IDs, changes relationship
/// status or claims the entire legacy 100340 friends history was recovered.
/// Safe in normal builds: feature disabled until verified private QA.
const bool dedaStep2FriendshipReadbackEnabled = bool.fromEnvironment(
  'DEDA_STEP2_FRIENDSHIP_READBACK', defaultValue: false);

class DedaStep2FriendshipHold implements Exception {
  const DedaStep2FriendshipHold(this.reason);
  final String reason;
  @override
  String toString() => 'DedaStep2FriendshipHold($reason)';
}

class DedaStep2FriendshipRow {
  const DedaStep2FriendshipRow(this.id, this.data,
      {this.fromCache = false, this.pendingWrites = false});
  final String id;
  final Map<String, dynamic> data;
  final bool fromCache, pendingWrites;
}

class DedaStep2FriendshipPage {
  const DedaStep2FriendshipPage(this.rows,
      {this.fromCache = false, this.pendingWrites = false});
  final List<DedaStep2FriendshipRow> rows;
  final bool fromCache, pendingWrites;
}

abstract class DedaStep2FriendshipIo {
  Future<DedaStep2FriendshipPage> readServerForUid(
      String originalUid, int maxDocuments);
}

/// Read from the same Firestore collection used by Friends UI. A bounded
/// query fetches one sentinel row beyond the supported 200 relations; if
/// the result reaches 201 it FAILS CLOSED, never drops any friend silently.
class DedaStep2FirestoreFriendshipIo implements DedaStep2FriendshipIo {
  const DedaStep2FirestoreFriendshipIo();
  @override
  Future<DedaStep2FriendshipPage> readServerForUid(
      String originalUid, int maxDocuments) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('deda_friendships')
        .where('members', arrayContains: originalUid)
        .limit(maxDocuments)
        .get(const GetOptions(source: Source.server));
    return DedaStep2FriendshipPage(
      [
        for (final doc in snapshot.docs)
          DedaStep2FriendshipRow(doc.id, doc.data(),
              fromCache: doc.metadata.isFromCache,
              pendingWrites: doc.metadata.hasPendingWrites),
      ],
      fromCache: snapshot.metadata.isFromCache,
      pendingWrites: snapshot.metadata.hasPendingWrites,
    );
  }
}

class DedaStep2FriendshipEvidence {
  const DedaStep2FriendshipEvidence({
    required this.originalUid,
    required this.accountKey,
    required this.originalId,
    required this.relations,
  });
  final String originalUid, accountKey, originalId;
  final List<DedaFriendshipRecord> relations;

  int get acceptedCount =>
      relations.where((record) => record.status == 'accepted').length;
  int get pendingCount =>
      relations.where((record) => record.status == 'pending').length;
  int get rejectedCount =>
      relations.where((record) => record.status == 'rejected').length;

  /// Server readback is not a historical completeness proof and cannot
  /// independently restore deleted legacy friends on another Firebase UID.
  bool get historicalLegacyRelationsProven => false;
  bool get allAccountDataRestored => false;
  bool get canCreateMissingFriendships => false;
  bool get canReassignFriendsToDifferentUid => false;
}

class DedaStep2FriendshipReadback {
  const DedaStep2FriendshipReadback({
    required this.io,
    required this.currentUid,
    required this.verifyOriginalOwner,
    this.enabled = dedaStep2FriendshipReadbackEnabled,
  });

  factory DedaStep2FriendshipReadback.firebase() =>
      DedaStep2FriendshipReadback(
        io: const DedaStep2FirestoreFriendshipIo(),
        currentUid: () => FirebaseAuth.instance.currentUser?.uid,
        verifyOriginalOwner: (uid, account) async {
          final current = FirebaseAuth.instance.currentUser;
          return current?.uid == uid &&
              await DedaLinkedOwnerSessionPolicy.verified(current, account);
        },
      );

  final DedaStep2FriendshipIo io;
  final String? Function() currentUid;
  final Future<bool> Function(String uid, String accountKey)
      verifyOriginalOwner;
  final bool enabled;
  static const maxRelations = 200;

  void _check(String uid, bool Function() isCurrent) {
    if (!enabled || uid.trim().isEmpty ||
        currentUid() != uid || !isCurrent()) {
      throw const DedaStep2FriendshipHold('friend-owner-session-changed');
    }
  }

  Future<DedaStep2FriendshipEvidence> inspect({
    required String accountKey,
    required String originalUid,
    required String originalId,
    required bool Function() isCurrent,
  }) async {
    if (!RegExp(r'^[0-9]{8,16}$').hasMatch(accountKey) ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(originalId)) {
      throw const DedaStep2FriendshipHold('friend-original-scope-invalid');
    }
    _check(originalUid, isCurrent);
    if (!await verifyOriginalOwner(originalUid, accountKey)) {
      throw const DedaStep2FriendshipHold('friend-original-owner-not-proven');
    }
    _check(originalUid, isCurrent);
    final page = await io.readServerForUid(originalUid, maxRelations + 1);
    _check(originalUid, isCurrent);
    if (page.fromCache || page.pendingWrites ||
        page.rows.length > maxRelations) {
      throw const DedaStep2FriendshipHold(
          'friend-read-not-authoritative-or-truncated');
    }

    final ids = <String>{}, otherUids = <String>{};
    final validated = <DedaFriendshipRecord>[];
    for (final row in page.rows) {
      _check(originalUid, isCurrent);
      if (row.fromCache || row.pendingWrites ||
          row.id.trim().isEmpty || row.id.contains('/') ||
          !ids.add(row.id)) {
        throw const DedaStep2FriendshipHold(
            'friend-duplicate-or-cached-source');
      }
      final fields = row.data;
      final record = DedaFriendshipRecord.fromMap(row.id, fields);
      final first = record.requesterUid;
      final second = record.recipientUid;
      final originalRequester = first == originalUid;
      final originalRecipient = second == originalUid;
      final other = originalRequester ? second : first;
      final sortedPair = <String>[first, second]..sort();
      final expectedPair = '${sortedPair[0]}__${sortedPair[1]}';
      final ownId = originalRequester
          ? record.requesterPublicId : record.recipientPublicId;
      final otherId = originalRequester
          ? record.recipientPublicId : record.requesterPublicId;
      if (first.trim().isEmpty || second.trim().isEmpty ||
          first == second ||
          originalRequester == originalRecipient ||
          record.members.length != 2 ||
          record.members.toSet().length != 2 ||
          !record.members.contains(first) ||
          !record.members.contains(second) ||
          row.id != expectedPair ||
          fields['pairKey'] != row.id ||
          ownId != originalId ||
          !RegExp(r'^@DEDA-[A-Z0-9]{5,12}$').hasMatch(otherId) ||
          !['accepted', 'pending', 'rejected'].contains(record.status) ||
          other.trim().isEmpty || !otherUids.add(other)) {
        throw const DedaStep2FriendshipHold(
            'friend-pair-or-original-id-conflict');
      }
      validated.add(record);
    }
    _check(originalUid, isCurrent);
    validated.sort((a, b) => a.id.compareTo(b.id));
    return DedaStep2FriendshipEvidence(
      accountKey: accountKey, originalUid: originalUid,
      originalId: originalId,
      relations: List<DedaFriendshipRecord>.unmodifiable(validated),
    );
  }
}
