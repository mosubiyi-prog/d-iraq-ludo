import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'deda_100431_linked_owner_session_policy.dart';

/// DEDA STEP 2: a published-place belongs to the *same original account*
/// when the user opens it on a second handset. Disabled in normal APKs.
/// The readback NEVER creates/removes/reassigns a Firestore place, receipt,
/// approval number, likes, availability, role or owner UID.
const bool dedaStep2LinkedPublishedPlaceEnabled = bool.fromEnvironment(
  'DEDA_STEP2_LINKED_PUBLISHED_PLACE', defaultValue: false,
);

class DedaStep2PublishedPlaceHold implements Exception {
  const DedaStep2PublishedPlaceHold(this.reason);
  final String reason;
  @override
  String toString() => 'DedaStep2PublishedPlaceHold($reason)';
}

class DedaStep2PublishedPlaceRow {
  const DedaStep2PublishedPlaceRow(
    this.id, this.fields, {
    this.fromCache = false, this.pendingWrites = false,
  });
  final String id;
  final Map<String, dynamic> fields;
  final bool fromCache, pendingWrites;
}

class DedaStep2PublishedPlacesResult {
  const DedaStep2PublishedPlacesResult(
    this.documents, {this.fromCache = false, this.pendingWrites = false});
  final List<DedaStep2PublishedPlaceRow> documents;
  final bool fromCache, pendingWrites;
}

abstract class DedaStep2LinkedPlaceIo {
  Future<DedaStep2PublishedPlacesResult> publishedForAccount(String accountKey);
  Future<String?> localPlaceId(String accountKey);
  Future<bool> saveScopedPlaceId(String accountKey, String id);
}

/// Existing locally-scoped key is exactly what OwnerPlacePage reads.
/// Only a VERIFIED existing Firestore document ID can populate it.
class DedaStep2FirebaseLinkedPlaceIo implements DedaStep2LinkedPlaceIo {
  const DedaStep2FirebaseLinkedPlaceIo();
  static String placeKey(String accountKey) =>
      'deda_owner_place_id_v2_$accountKey';

  @override
  Future<DedaStep2PublishedPlacesResult> publishedForAccount(
      String accountKey) async {
    final result = await FirebaseFirestore.instance
        .collection('published_places')
        .where('accountKey', isEqualTo: accountKey)
        .where('published', isEqualTo: true)
        .limit(2)
        .get(const GetOptions(source: Source.server));
    return DedaStep2PublishedPlacesResult([
      for (final doc in result.docs)
        DedaStep2PublishedPlaceRow(
          doc.id, doc.data(),
          fromCache: doc.metadata.isFromCache,
          pendingWrites: doc.metadata.hasPendingWrites,
        )
    ], fromCache: result.metadata.isFromCache,
       pendingWrites: result.metadata.hasPendingWrites);
  }

  @override
  Future<String?> localPlaceId(String accountKey) async =>
      (await SharedPreferences.getInstance()).getString(placeKey(accountKey));

  @override
  Future<bool> saveScopedPlaceId(String accountKey, String id) async =>
      (await SharedPreferences.getInstance()).setString(placeKey(accountKey), id);
}

class DedaStep2LinkedPublishedPlaceRecovery {
  const DedaStep2LinkedPublishedPlaceRecovery({
    required this.io,
    required this.currentUid,
    required this.verifyOriginalOwner,
    this.enabled = dedaStep2LinkedPublishedPlaceEnabled,
  });

  factory DedaStep2LinkedPublishedPlaceRecovery.firebase() =>
      DedaStep2LinkedPublishedPlaceRecovery(
        io: const DedaStep2FirebaseLinkedPlaceIo(),
        currentUid: () => FirebaseAuth.instance.currentUser?.uid,
        verifyOriginalOwner: (uid, accountKey) async {
          final current = FirebaseAuth.instance.currentUser;
          return current != null && current.uid == uid &&
              await DedaLinkedOwnerSessionPolicy.verified(
                  current, accountKey);
        },
      );

  final DedaStep2LinkedPlaceIo io;
  final String? Function() currentUid;
  final Future<bool> Function(String uid, String accountKey)
      verifyOriginalOwner;
  final bool enabled;

  void _check(String accountKey, String uid, bool Function() isCurrent) {
    if (!enabled || !RegExp(r'^[0-9]{8,16}$').hasMatch(accountKey) ||
        uid.isEmpty || currentUid() != uid || !isCurrent()) {
      throw const DedaStep2PublishedPlaceHold('place-original-owner-required');
    }
  }

  /// Replacement phone ONLY. Account owner already proved independently.
  /// Returns existing ID, and copies that ID into the same account-scoped
  /// local key (not the place document) when absent. It cannot mint ownership
  /// for another UID or hide missing/ambiguous places as an empty draft.
  Future<String> recoverOriginalPublishedPlace({
    required String accountKey,
    required String originalUid,
    required bool Function() isCurrent,
  }) async {
    void check() => _check(accountKey, originalUid, isCurrent);
    check();
    if (!await verifyOriginalOwner(originalUid, accountKey)) {
      throw const DedaStep2PublishedPlaceHold('place-owner-not-verified');
    }
    check();

    final result = await io.publishedForAccount(accountKey);
    check();
    if (result.fromCache || result.pendingWrites ||
        result.documents.isEmpty || result.documents.length != 1) {
      throw const DedaStep2PublishedPlaceHold(
          'published-place-not-uniquely-verified');
    }
    final row = result.documents.single;
    final place = row.fields;
    final approval = place['approvalNumber'];
    if (row.fromCache || row.pendingWrites ||
        row.id.trim().isEmpty || row.id.contains('/') ||
        place['accountKey'] != accountKey ||
        place['ownerUid'] != originalUid ||
        place['published'] != true ||
        approval == null || approval.toString().trim().isEmpty) {
      // Do not change ownerUid when a previous device logged in under
      // another UID: it needs trusted adjudication, not implicit takeover.
      throw const DedaStep2PublishedPlaceHold(
          'published-place-owner-or-approval-mismatch');
    }
    check();
    final stored = (await io.localPlaceId(accountKey))?.trim() ?? '';
    check();
    if (stored.isNotEmpty && stored != row.id) {
      // Never replace the original handset's place with a different one.
      throw const DedaStep2PublishedPlaceHold(
          'existing-local-place-id-conflict');
    }
    if (stored.isEmpty) {
      check();
      if (!await io.saveScopedPlaceId(accountKey, row.id)) {
        throw const DedaStep2PublishedPlaceHold('place-id-save-failed');
      }
      check();
      if (await io.localPlaceId(accountKey) != row.id) {
        throw const DedaStep2PublishedPlaceHold(
            'place-id-local-readback-failed');
      }
    }
    check();
    return row.id;
  }
}
