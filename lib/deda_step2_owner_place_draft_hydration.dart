import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'deda_step2_linked_published_place_recovery.dart';
import 'deda_step2_owner_place_local_archive.dart';

/// Opt-in private QA only. The source is an untrusted old-phone archive;
/// this hydrates an absent *draft UI* key, never an approved place ID,
/// ownership, availability, pending request, prize or wallet.
const bool dedaStep2OwnerPlaceDraftHydrationEnabled = bool.fromEnvironment(
  'DEDA_STEP2_OWNER_PLACE_DRAFT_HYDRATION', defaultValue: false);

class DedaStep2PlaceDraftHold implements Exception {
  const DedaStep2PlaceDraftHold(this.reason);
  final String reason;
  @override
  String toString() => 'DedaStep2PlaceDraftHold($reason)';
}

class DedaStep2ArchiveCapturePage {
  const DedaStep2ArchiveCapturePage(this.ids, {
    this.fromCache = false,
    this.pendingWrites = false,
  });
  final List<String> ids;
  final bool fromCache;
  final bool pendingWrites;
}

abstract class DedaStep2PlaceDraftHydrationIo {
  Future<DedaStep2ArchiveCapturePage> getCaptureIds(
      String accountKey, int limit);
  Future<String?> getExistingDraft(String accountKey);
  Future<bool> putDraftIfAbsent(String accountKey, String raw);
}

/// Only query at most two captures: zero is missing, two are ambiguous.
/// Firestore security rules already restrict list to original UID and
/// a maximum of 20 records. We do not silently choose a newer source.
class DedaStep2FirebasePlaceDraftIo implements DedaStep2PlaceDraftHydrationIo {
  const DedaStep2FirebasePlaceDraftIo();

  static String draftKey(String accountKey) =>
      'deda_owner_place_draft_v1_$accountKey';

  @override
  Future<DedaStep2ArchiveCapturePage> getCaptureIds(
      String accountKey, int limit) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('deda_step2_owner_place_evidence')
        .doc(accountKey).collection('captures')
        .limit(limit).get(const GetOptions(source: Source.server));
    return DedaStep2ArchiveCapturePage(
      [for (final doc in snapshot.docs) doc.id],
      fromCache: snapshot.metadata.isFromCache,
      pendingWrites: snapshot.metadata.hasPendingWrites,
    );
  }

  @override
  Future<String?> getExistingDraft(String accountKey) async =>
      (await SharedPreferences.getInstance())
          .getString(draftKey(accountKey));

  @override
  Future<bool> putDraftIfAbsent(String accountKey, String raw) async {
    final prefs = await SharedPreferences.getInstance();
    final key = draftKey(accountKey);
    // Do not silently clobber a draft entered on the replacement phone.
    if (prefs.containsKey(key)) return false;
    return prefs.setString(key, raw);
  }
}

class DedaStep2PlaceDraftHydrationReceipt {
  const DedaStep2PlaceDraftHydrationReceipt({
    required this.captureId,
    required this.approvedPlaceId,
    required this.draftRestored,
  });
  final String captureId, approvedPlaceId;
  final bool draftRestored;
  bool get canEditPublishedPlace => false;
  bool get allAccountDataRestored => false;
  bool get canRestorePendingEdits => false;
}

/// Makes an old-phone *draft* available for display on a second handset,
/// strictly after independently proving the same ORIGINAL Firebase UID
/// owns the same currently published/approved map place.
/// Published owner controls must continue validating the live map document.
class DedaStep2OwnerPlaceDraftHydration {
  const DedaStep2OwnerPlaceDraftHydration({
    required this.archived,
    required this.places,
    required this.io,
    required this.currentUid,
    this.enabled = dedaStep2OwnerPlaceDraftHydrationEnabled,
  });

  factory DedaStep2OwnerPlaceDraftHydration.firebase() =>
      DedaStep2OwnerPlaceDraftHydration(
        archived: DedaStep2OwnerPlaceLocalArchive.firebase(),
        places: const DedaStep2FirebaseLinkedPlaceIo(),
        io: const DedaStep2FirebasePlaceDraftIo(),
        currentUid: () => FirebaseAuth.instance.currentUser?.uid,
      );

  final DedaStep2OwnerPlaceLocalArchive archived;
  final DedaStep2LinkedPlaceIo places;
  final DedaStep2PlaceDraftHydrationIo io;
  final String? Function() currentUid;
  final bool enabled;

  void _check(String account, String uid, bool Function() isCurrent) {
    if (!enabled || !archived.enabled ||
        !RegExp(r'^[0-9]{8,16}$').hasMatch(account) ||
        uid.isEmpty || currentUid() != uid || !isCurrent()) {
      throw const DedaStep2PlaceDraftHold(
          'original-owner-session-or-pilot-required');
    }
  }

  static void _draftHasSameScope(
      String raw, String accountKey, String originalUid, String placeId) {
    if (utf8.encode(raw).length > 65536) {
      throw const DedaStep2PlaceDraftHold('old-draft-too-large');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      throw const DedaStep2PlaceDraftHold('old-draft-invalid-json');
    }
    if (decoded is! Map || decoded.isEmpty ||
        decoded.keys.any((key) => key is! String) ||
        (decoded.containsKey('accountKey') &&
            decoded['accountKey'] != accountKey) ||
        (decoded.containsKey('ownerUid') &&
            decoded['ownerUid'] != originalUid) ||
        (decoded.containsKey('placeId') &&
            decoded['placeId'] != placeId)) {
      throw const DedaStep2PlaceDraftHold('old-draft-foreign-scope');
    }
    // This is a UI draft, never reinterpreted as a signed approval.
    for (final blocked in [
      'walletBalance', 'diamonds', 'paidFrames', 'premiumId',
      'permissions', 'adminRole', 'approved', 'published',
    ]) {
      if (decoded.containsKey(blocked)) {
        throw const DedaStep2PlaceDraftHold('old-draft-privileged-fields');
      }
    }
  }

  Future<DedaStep2PlaceDraftHydrationReceipt> restoreMissingDraft({
    required String accountKey,
    required String originalUid,
    required bool Function() isCurrent,
  }) async {
    void check() => _check(accountKey, originalUid, isCurrent);
    check();
    // The same-UID proof happens BEFORE even querying capture IDs.
    await archived.proveOriginalOwner(
      accountKey: accountKey, originalUid: originalUid,
      isCurrent: isCurrent,
    );
    check();
    final existing = await io.getExistingDraft(accountKey);
    check();
    if (existing != null) {
      throw const DedaStep2PlaceDraftHold(
          'replacement-phone-draft-already-exists');
    }

    final captures = await io.getCaptureIds(accountKey, 2);
    check();
    if (captures.fromCache || captures.pendingWrites ||
        captures.ids.length != 1 ||
        !RegExp(r'^[A-Za-z0-9_-]{20,80}$').hasMatch(captures.ids.single)) {
      throw const DedaStep2PlaceDraftHold(
          'old-phone-capture-missing-or-ambiguous');
    }
    final captureId = captures.ids.single;
    final source = await archived.inspectOnReplacementPhone(
      accountKey: accountKey, originalUid: originalUid,
      captureId: captureId, isCurrent: isCurrent,
    );
    check();

    final published = await places.publishedForAccount(accountKey);
    check();
    if (published.fromCache || published.pendingWrites ||
        published.documents.length != 1) {
      throw const DedaStep2PlaceDraftHold(
          'approved-original-place-not-unique');
    }
    final row = published.documents.single;
    final p = row.fields;
    if (row.fromCache || row.pendingWrites ||
        row.id.isEmpty || row.id.contains('/') ||
        p['accountKey'] != accountKey ||
        p['ownerUid'] != originalUid ||
        p['published'] != true ||
        p['approvalNumber'] is! String ||
        (p['approvalNumber'] as String).trim().isEmpty ||
        source.records['placeId'] != row.id) {
      throw const DedaStep2PlaceDraftHold(
          'old-phone-place-not-same-approved-owner');
    }

    final draft = source.records['draftRaw'];
    if (draft == null || draft.isEmpty) {
      // Absence is explicitly reported, never filled with invented content.
      return DedaStep2PlaceDraftHydrationReceipt(
          captureId: captureId, approvedPlaceId: row.id,
          draftRestored: false);
    }
    _draftHasSameScope(draft, accountKey, originalUid, row.id);
    check();

    // A second session/account must not win an asynchronous race and cause
    // the old phone's draft to overwrite another account's local content.
    if (await io.getExistingDraft(accountKey) != null) {
      throw const DedaStep2PlaceDraftHold('local-draft-changed-during-restore');
    }
    check();
    if (!await io.putDraftIfAbsent(accountKey, draft)) {
      throw const DedaStep2PlaceDraftHold('draft-save-failed-or-conflicted');
    }
    check();
    if (await io.getExistingDraft(accountKey) != draft) {
      throw const DedaStep2PlaceDraftHold('draft-readback-mismatch');
    }
    check();
    return DedaStep2PlaceDraftHydrationReceipt(
      captureId: captureId, approvedPlaceId: row.id,
      draftRestored: true,
    );
  }
}
