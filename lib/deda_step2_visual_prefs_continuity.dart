import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'deda_100431_linked_owner_session_policy.dart';

/// SOURCE-ONLY / OFF BY DEFAULT. One-time migration of two FREE, non-financial
/// account-scoped appearance preferences. This does NOT restore premium frames,
/// IDs, points, coins, diamonds, league prizes or gift entitlement.
const bool dedaStep2VisualPrefsMigrationEnabled = bool.fromEnvironment(
  'DEDA_STEP2_VISUAL_PREFS_MIGRATION', defaultValue: false);

class DedaStep2VisualPrefsHold implements Exception {
  const DedaStep2VisualPrefsHold(this.reason);
  final String reason;
}

class DedaStep2VisualSnapshot {
  const DedaStep2VisualSnapshot({
    required this.accountKey,
    required this.originalId,
    required this.uid,
    required this.avatarStyle,
    required this.backgroundStyle,
  });

  final String accountKey, originalId, uid;
  final int avatarStyle, backgroundStyle;

  void validate() {
    if (!RegExp(r'^[0-9]{10,16}$').hasMatch(accountKey) ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(originalId) ||
        uid.trim().isEmpty || avatarStyle < 0 || avatarStyle > 5 ||
        backgroundStyle < 0 || backgroundStyle > 5) {
      throw const DedaStep2VisualPrefsHold('invalid-visual-preferences');
    }
  }

  Map<String, dynamic> toCloud() {
    validate();
    return {
      'format': 1,
      'kind': 'free-profile-appearance-only',
      'accountKey': accountKey,
      'originalId': originalId,
      'uid': uid,
      'avatarStyle': avatarStyle,
      'backgroundStyle': backgroundStyle,
    };
  }

  static DedaStep2VisualSnapshot fromCloud(
      Map<String, dynamic> data, {
      required String accountKey,
      required String originalId,
      required String uid,
    }) {
    const fields = {
      'format','kind','accountKey','originalId','uid',
      'avatarStyle','backgroundStyle','createdAt',
    };
    if (data.keys.toSet().difference(fields).isNotEmpty ||
        !fields.every(data.containsKey) ||
        data['format'] != 1 ||
        data['kind'] != 'free-profile-appearance-only' ||
        data['accountKey'] != accountKey ||
        data['originalId'] != originalId ||
        data['uid'] != uid ||
        data['avatarStyle'] is! int ||
        data['backgroundStyle'] is! int ||
        data['createdAt'] is! Timestamp) {
      throw const DedaStep2VisualPrefsHold('visual-source-corrupt');
    }
    final value = DedaStep2VisualSnapshot(
      accountKey: accountKey, originalId: originalId, uid: uid,
      avatarStyle: data['avatarStyle'] as int,
      backgroundStyle: data['backgroundStyle'] as int,
    );
    value.validate();
    return value;
  }
}

abstract class DedaStep2VisualPrefsLocal {
  Future<int?> getInt(String key);
  Future<bool> putInt(String key, int value);
}

class DedaStep2VisualPrefsSharedLocal implements DedaStep2VisualPrefsLocal {
  const DedaStep2VisualPrefsSharedLocal();
  @override
  Future<int?> getInt(String key) async =>
      (await SharedPreferences.getInstance()).getInt(key);
  @override
  Future<bool> putInt(String key, int value) async =>
      (await SharedPreferences.getInstance()).setInt(key, value);
}

abstract class DedaStep2VisualPrefsCloud {
  Future<Map<String, dynamic>?> read(String accountKey);
  Future<void> createOnce(String accountKey, Map<String, dynamic> fields);
}

class DedaStep2VisualPrefsFirestore implements DedaStep2VisualPrefsCloud {
  const DedaStep2VisualPrefsFirestore();
  DocumentReference<Map<String, dynamic>> _doc(String accountKey) =>
      FirebaseFirestore.instance.collection('deda_profile_ui_migration')
          .doc(accountKey);

  @override
  Future<Map<String, dynamic>?> read(String accountKey) async {
    final snapshot = await _doc(accountKey)
        .get(const GetOptions(source: Source.server));
    if (snapshot.metadata.isFromCache ||
        snapshot.metadata.hasPendingWrites) {
      throw const DedaStep2VisualPrefsHold('not-authoritative-server-read');
    }
    return snapshot.data();
  }

  @override
  Future<void> createOnce(
      String accountKey, Map<String, dynamic> fields) async {
    final ref = _doc(accountKey);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final existing = await tx.get(ref);
      if (existing.exists) {
        final data = existing.data() ?? {};
        for (final entry in fields.entries) {
          if (data[entry.key] != entry.value) {
            throw const DedaStep2VisualPrefsHold(
                'existing-visual-snapshot-conflict');
          }
        }
        return;
      }
      tx.set(ref, {...fields, 'createdAt': FieldValue.serverTimestamp()});
    });
  }
}

/// Verifies directory, session, original user projection and immutable route,
/// from server. Same proof works for original anonymous UID or linked UID.
class DedaStep2VisualOriginalOwnerProof {
  const DedaStep2VisualOriginalOwnerProof();
  Future<bool> verify(DedaStep2VisualSnapshot scope) async {
    scope.validate();
    final current = FirebaseAuth.instance.currentUser;
    if (current == null || current.uid != scope.uid ||
        (!current.isAnonymous &&
            !DedaLinkedOwnerSessionPolicy.emailMatches(
                current.email, scope.accountKey))) {
      return false;
    }
    try {
      final db = FirebaseFirestore.instance;
      final docs = await Future.wait([
        db.collection('deda_account_directory').doc(scope.accountKey)
            .get(const GetOptions(source: Source.server)),
        db.collection('deda_sessions').doc(scope.uid)
            .get(const GetOptions(source: Source.server)),
        db.collection('users').doc(scope.uid)
            .get(const GetOptions(source: Source.server)),
        db.collection('deda_share_ids').doc(scope.originalId)
            .get(const GetOptions(source: Source.server)),
      ]);
      if (FirebaseAuth.instance.currentUser?.uid != scope.uid ||
          docs.any((d) => d.metadata.isFromCache ||
              d.metadata.hasPendingWrites)) {
        return false;
      }
      return DedaLinkedOwnerSessionPolicy.ownerDocumentsMatch(
        uid: scope.uid,
        accountKey: scope.accountKey,
        directory: docs[0].data(),
        session: docs[1].data(),
        projection: docs[2].data(),
        route: docs[3].data(),
      ) && docs[2].data()?['sharePersonalId'] == scope.originalId;
    } catch (_) {
      return false;
    }
  }
}

class DedaStep2VisualPrefsContinuity {
  const DedaStep2VisualPrefsContinuity({
    required this.local,
    required this.cloud,
    required this.currentUid,
    required this.verifyOriginalOwner,
    this.enabled = dedaStep2VisualPrefsMigrationEnabled,
  });

  factory DedaStep2VisualPrefsContinuity.firebase() =>
      DedaStep2VisualPrefsContinuity(
        local: const DedaStep2VisualPrefsSharedLocal(),
        cloud: const DedaStep2VisualPrefsFirestore(),
        currentUid: () => FirebaseAuth.instance.currentUser?.uid,
        verifyOriginalOwner:
            const DedaStep2VisualOriginalOwnerProof().verify,
      );

  final DedaStep2VisualPrefsLocal local;
  final DedaStep2VisualPrefsCloud cloud;
  final String? Function() currentUid;
  final Future<bool> Function(DedaStep2VisualSnapshot)
      verifyOriginalOwner;
  final bool enabled;

  String _avatar(String account) => 'deda_profile_avatar_v1_$account';
  String _background(String account) =>
      'deda_profile_background_v1_$account';

  void _check(DedaStep2VisualSnapshot scope, bool Function() isCurrent) {
    scope.validate();
    if (!enabled || !isCurrent() || currentUid() != scope.uid) {
      throw const DedaStep2VisualPrefsHold('visual-owner-session-changed');
    }
  }

  Future<void> _owner(
      DedaStep2VisualSnapshot scope, bool Function() isCurrent) async {
    _check(scope, isCurrent);
    if (!await verifyOriginalOwner(scope)) {
      throw const DedaStep2VisualPrefsHold('visual-owner-not-proven');
    }
    _check(scope, isCurrent);
  }

  /// Original phone, before any linked-account transition. Missing is NOT zero.
  /// No purchased frame or account credential is uploaded.
  Future<DedaStep2VisualSnapshot> saveOriginalPhone({
    required String accountKey,
    required String originalId,
    required String originalUid,
    required bool Function() isCurrent,
  }) async {
    final scope = DedaStep2VisualSnapshot(
      accountKey: accountKey, originalId: originalId, uid: originalUid,
      avatarStyle: 0, backgroundStyle: 0,
    );
    await _owner(scope, isCurrent);
    final avatar = await local.getInt(_avatar(accountKey));
    _check(scope, isCurrent);
    final background = await local.getInt(_background(accountKey));
    _check(scope, isCurrent);
    if (avatar == null || background == null) {
      throw const DedaStep2VisualPrefsHold('old-phone-visual-data-missing');
    }
    final source = DedaStep2VisualSnapshot(
      accountKey: accountKey, originalId: originalId, uid: originalUid,
      avatarStyle: avatar, backgroundStyle: background,
    );
    source.validate();
    await _owner(source, isCurrent);
    await cloud.createOnce(accountKey, source.toCloud());
    await _owner(source, isCurrent);
    final readback = await cloud.read(accountKey);
    _check(source, isCurrent);
    if (readback == null ||
        DedaStep2VisualSnapshot.fromCloud(readback,
          accountKey: accountKey, originalId: originalId, uid: originalUid)
            .avatarStyle != avatar ||
        DedaStep2VisualSnapshot.fromCloud(readback,
          accountKey: accountKey, originalId: originalId, uid: originalUid)
            .backgroundStyle != background) {
      throw const DedaStep2VisualPrefsHold('visual-write-not-acknowledged');
    }
    return source;
  }

  /// Replacement phone. Only fills absent free visual preferences; never
  /// overwrite the account's existing local choices, financial keys or frames.
  Future<bool> restoreReplacementPhone({
    required String accountKey,
    required String originalId,
    required String originalUid,
    required bool Function() isCurrent,
  }) async {
    final scope = DedaStep2VisualSnapshot(
      accountKey: accountKey, originalId: originalId, uid: originalUid,
      avatarStyle: 0, backgroundStyle: 0,
    );
    await _owner(scope, isCurrent);
    final raw = await cloud.read(accountKey);
    _check(scope, isCurrent);
    if (raw == null) {
      throw const DedaStep2VisualPrefsHold('visual-backup-not-found');
    }
    final saved = DedaStep2VisualSnapshot.fromCloud(raw,
      accountKey: accountKey, originalId: originalId, uid: originalUid);
    await _owner(scope, isCurrent);
    final avatarKey = _avatar(accountKey);
    final backgroundKey = _background(accountKey);
    final currentAvatar = await local.getInt(avatarKey);
    _check(scope, isCurrent);
    final currentBackground = await local.getInt(backgroundKey);
    _check(scope, isCurrent);
    if ((currentAvatar != null && currentAvatar != saved.avatarStyle) ||
        (currentBackground != null &&
            currentBackground != saved.backgroundStyle)) {
      throw const DedaStep2VisualPrefsHold(
          'replacement-existing-visual-choices-preserved');
    }
    var changed = false;
    if (currentAvatar == null) {
      _check(scope, isCurrent);
      if (!await local.putInt(avatarKey, saved.avatarStyle)) {
        throw const DedaStep2VisualPrefsHold('avatar-persist-failed');
      }
      _check(scope, isCurrent);
      if (await local.getInt(avatarKey) != saved.avatarStyle) {
        throw const DedaStep2VisualPrefsHold('avatar-readback-failed');
      }
      changed = true;
    }
    if (currentBackground == null) {
      _check(scope, isCurrent);
      if (!await local.putInt(backgroundKey, saved.backgroundStyle)) {
        throw const DedaStep2VisualPrefsHold('background-persist-failed');
      }
      _check(scope, isCurrent);
      if (await local.getInt(backgroundKey) != saved.backgroundStyle) {
        throw const DedaStep2VisualPrefsHold('background-readback-failed');
      }
      changed = true;
    }
    return changed;
  }
}
