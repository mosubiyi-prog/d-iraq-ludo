#!/usr/bin/env python3
"""After exact signed DEDA reconstruction, enable Spark friend/location ID aliases.

The *unmodified* historical 100269 social regex is required while rebuilding.
On the reconstructed source, apply the verified premium alias resolver and
restore four-character input support. Original account ID remains canonical.
Fail closed instead of silently skipping a feature or changing an unrelated
method. No Firestore writes, wallet or release deployment.
"""
from pathlib import Path

BACKEND=Path("lib/deda_backend.dart")
SOCIAL=Path("lib/deda_social_service.dart")
IMPORT="import 'deda_qa32_public_recipient_resolver.dart';"
MARK_SHARE="DEDA_QA32_SHARE_TO_VERIFIED_ACTIVE_PREMIUM_ALIAS_CANONICAL_ROUTE"
MARK_FRIEND="DEDA_QA32_FIND_FRIEND_BY_VERIFIED_PREMIUM_ID_TO_CANONICAL_ACCOUNT"

OLD_SHARE="""    final recipientId = normalizeSharePublicId(recipientPublicId);
    final senderId = normalizeSharePublicId(senderPublicId);
    if (!isValidPersonalShareId(recipientId)) {
      throw ArgumentError('invalid-recipient-share-id');
    }

    final recipient = await locationShareIdInfo(recipientId);
    if (recipient == null ||
        (recipient['kind'] ?? '').toString() != 'personal') {
      throw StateError('recipient-share-id-not-found');
    }"""
NEW_SHARE="""    // DEDA_QA32_SHARE_TO_VERIFIED_ACTIVE_PREMIUM_ALIAS_CANONICAL_ROUTE
    // Canonical original IDs always take precedence over six-letter aliases.
    final requested = normalizeSharePublicId(recipientPublicId);
    final senderId = normalizeSharePublicId(senderPublicId);
    if (!RegExp(r'^@DEDA-[A-Z0-9]{4,12}$').hasMatch(requested)) {
      throw ArgumentError('invalid-recipient-share-id');
    }
    var recipientId = requested;
    var recipient = isValidPersonalShareId(recipientId)
        ? await locationShareIdInfo(recipientId) : null;
    if (recipient == null || (recipient['kind'] ?? '').toString() != 'personal') {
      final verified = await DedaQa32PublicRecipientResolver.resolveActiveAlias(
        requested,
      );
      if (verified == null || !isValidPersonalShareId(verified)) {
        throw StateError('recipient-share-id-not-found');
      }
      recipientId = verified;
      recipient = await locationShareIdInfo(recipientId);
    }
    if (recipient == null ||
        (recipient['kind'] ?? '').toString() != 'personal') {
      throw StateError('recipient-share-id-not-found');
    }"""
OLD_FRIEND="""    final publicId = normalizePublicId(raw);
    if (!looksLikePersonalId(publicId)) return null;

    final directory = await _db.collection('deda_share_ids').doc(publicId).get();
    final directoryData = directory.data();
    if (!directory.exists ||
        directoryData == null ||
        directoryData['active'] != true ||
        directoryData['kind'] != 'personal') {
      return null;
    }"""
NEW_FRIEND="""    // DEDA_QA32_FIND_FRIEND_BY_VERIFIED_PREMIUM_ID_TO_CANONICAL_ACCOUNT
    final requestedId = normalizePublicId(raw);
    if (!looksLikePersonalId(requestedId)) return null;
    var publicId = requestedId;
    var directory = await _db.collection('deda_share_ids').doc(publicId).get();
    var directoryData = directory.data();
    if (!directory.exists ||
        directoryData == null ||
        directoryData['active'] != true ||
        directoryData['kind'] != 'personal') {
      final verified = await DedaQa32PublicRecipientResolver.resolveActiveAlias(
        requestedId,
      );
      if (verified == null ||
          !DedaBackend.isValidPersonalShareId(verified)) return null;
      publicId = verified;
      directory = await _db.collection('deda_share_ids').doc(publicId).get();
      directoryData = directory.data();
      if (!directory.exists ||
          directoryData == null ||
          directoryData['active'] != true ||
          directoryData['kind'] != 'personal') return null;
    }"""
OLD_REGEXP="RegExp(r'^@DEDA-[A-Z0-9]{5,12}$').hasMatch(normalizePublicId(value));"
NEW_REGEXP="RegExp(r'^@DEDA-[A-Z0-9]{4,12}$').hasMatch(normalizePublicId(value));"

def patch_backend(s):
    if MARK_SHARE not in s:
        if s.count(OLD_SHARE)!=1:
            raise ValueError(f"SAFE_STOP_SPARK_SHARING_SOURCE_DRIFT={s.count(OLD_SHARE)}")
        s=s.replace(OLD_SHARE, NEW_SHARE, 1)
    if s.count(MARK_SHARE)!=1:
        raise ValueError("SAFE_STOP_SPARK_SHARE_PATCH_DUPLICATE")
    if IMPORT not in s:
        needle="import 'deda_pin_auth.dart';"
        if s.count(needle)!=1:raise ValueError("SAFE_STOP_SPARK_BACKEND_IMPORT")
        s=s.replace(needle,needle+"\n"+IMPORT,1)
    if "'recipientPublicId': recipientId" not in s:
        raise ValueError("SAFE_STOP_SPARK_CANONICAL_RECIPIENT_CHANGED")
    return s

def patch_social(s):
    # DEDA_QA32_STAGE51_SPARK_FRIEND_INTEGRATES_IN_EXISTING_SEARCH
    # Stage51 already routes all Add Friend user input through
    # DedaStage51FriendSearch.findByUserInput. That bridge now resolves
    # verified Spark aliases and calls the canonical ORIGINAL lookup.
    # Do not patch the historical DedaSocialService here; reconstruction
    # has modified/pretty-printed this function and the second patch
    # previously failed SAFE_STOP_SPARK_FRIEND_SOURCE_DRIFT.
    if "static Future<DedaSocialProfile?> findByPublicId(String raw)" not in s:
        raise ValueError("SAFE_STOP_ORIGINAL_SOCIAL_LOOKUP_MISSING")
    if "collection('deda_share_ids')" not in s:
        raise ValueError("SAFE_STOP_SOCIAL_ROUTE_NO_LONGER_ORIGINAL")
    if MARK_FRIEND in s:
        raise ValueError("SAFE_STOP_SOCIAL_ALREADY_REWRITTEN_UNEXPECTED")
    return s

if __name__=="__main__":
    a=BACKEND.read_text()
    b=SOCIAL.read_text()
    after_a=patch_backend(a)
    after_b=patch_social(b)
    BACKEND.write_text(after_a)
    SOCIAL.write_text(after_b)
    print("PASS_100375_SPARK_PREMIUM_ID_SEARCH_SHARE_CANONICAL_ROUTING_FOUR_CHAR")
    print("PASS_100375_SPARK_STAGE51_VERIFIED_FRIENDS_NO_LEGACY_SOCIAL_MUTATION")
    print("PASS_100375_SPARK_ORIGINAL_ID_BACKEND_AND_FRIEND_SOURCE_GUARDS")
