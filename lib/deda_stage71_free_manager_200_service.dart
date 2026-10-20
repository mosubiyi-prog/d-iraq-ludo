import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'deda_backend.dart';

/// Manager-only Spark backend for TWO original catalogs of 100 each.
/// NO diamonds, sales, costs, Cloud Functions or decrypted Group001 in APK.
/// The real 200 rows MUST first be seeded by a trusted private administrator.
/// Uses Firestore rules for role, canonical original-ID ownership and
/// immutable exactly-once group-specific grants.
class DedaStage71AdminId {
  final String identifier;
  final String group; // 001 preserved originals; 002 former sale proposals
  final int sequence;
  final String baseColor;
  final String status;
  final String? recipientOriginalId;
  final DateTime? grantedAt;

  const DedaStage71AdminId({
    required this.identifier,
    required this.group,
    required this.sequence,
    required this.baseColor,
    required this.status,
    this.recipientOriginalId,
    this.grantedAt,
  });

  bool get available => status == 'available';

  static DedaStage71AdminId fromRecord(String docId, Map<String, dynamic> d) {
    final id = (d['identifier'] ?? '').toString();
    final group = (d['group'] ?? '').toString();
    final sequence = d['sequence'];
    final baseColor = (d['baseColor'] ?? '').toString();
    final status = (d['status'] ?? '').toString();
    final rawRecipient = d['recipientOriginalId'];
    final recipient = rawRecipient is String ? rawRecipient : null;
    final stamp = d['grantedAt'];
    if (id != docId ||
        !RegExp(r'^@DEDA-[A-Z0-9]{4,12}$').hasMatch(id) ||
        !{'001', '002'}.contains(group) ||
        sequence is! int || sequence < 1 || sequence > 100 ||
        !{'gold', 'diamond', 'royal', 'pink'}.contains(baseColor) ||
        !{'available', 'gifted', 'self_used'}.contains(status) ||
        (status == 'available' && (recipient != null || stamp != null)) ||
        (status != 'available' &&
            (recipient == null ||
             !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(recipient) ||
             stamp is! Timestamp))) {
      throw StateError('unverified-admin-catalog-entry');
    }
    return DedaStage71AdminId(
      identifier: id, group: group, sequence: sequence,
      baseColor: baseColor, status: status,
      recipientOriginalId: recipient,
      grantedAt: stamp is Timestamp ? stamp.toDate() : null,
    );
  }
}

class DedaStage71Admin200 {
  DedaStage71Admin200._();
  static const enabled = bool.fromEnvironment(
    'DEDA_STAGE71_ADMIN200_RULES_AND_PRIVATE_CATALOG_DEPLOYED',
    defaultValue: false,
  );
  static const collection = 'deda_stage71_admin_catalog';
  static const registry = 'deda_stage71_granted_registry';

  static Future<String> _managerUid() async {
    if (!enabled || Firebase.apps.isEmpty) {
      throw StateError('private-admin-200-not-provisioned');
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('no-deda-authentication');
    final profile = await DedaBackend.currentAdminProfile(forceRefresh: true);
    if (FirebaseAuth.instance.currentUser?.uid != uid ||
        profile == null ||
        DedaBackend.normalizeAdminRole(profile['role']) != 'general_manager' ||
        DedaBackend.normalizeAdminStatus(profile) != 'active') {
      throw StateError('general-manager-role-required');
    }
    // Published Firestore rules independently enforce this role on EACH read.
    return uid;
  }

  /// On-device one-time ORIGINAL owner backup import. Group001 input exists
  /// only in the GM's clipboard / private Library, NEVER embedded in APK or
  /// public GitHub. Group002 input is the exact 100 formerly offered for sale.
  /// All 200 create writes are restricted by published GM+PIN Rules, and
  /// existing rows are NEVER overwritten or reset after a gift.
  static Future<void> importOwnerTwoGroups({
    required String ownerBackupJson,
    required List<String> formerlySaleGroup002,
    void Function(int completed, int total)? progress,
  }) async {
    final uid = await _managerUid();
    final raw = jsonDecode(ownerBackupJson);
    if (raw is! Map ||
        raw['format'] != 'DEDA_LAB_IDS' ||
        raw['version'] != 1 ||
        raw['identifiers'] is! List ||
        (raw['identifiers'] as List).length != 100 ||
        formerlySaleGroup002.length != 100) {
      throw StateError('original-100-backup-required');
    }
    final originalNames = <String>[];
    for (final item in raw['identifiers'] as List) {
      if (item is! Map || item['name'] is! String ||
          item['tier'] != 'gold') {
        throw StateError('private-100-backup-corrupted');
      }
      final suffix=(item['name'] as String)
          .replaceFirst(RegExp(r'^@DEDA-'), '').toUpperCase();
      if (!RegExp(r'^[A-Z0-9]{4,12}$').hasMatch(suffix)) {
        throw StateError('private-identifier-invalid');
      }
      originalNames.add('@DEDA-$suffix');
    }
    if (originalNames.first != '@DEDA-SALEM' ||
        originalNames.last != '@DEDA-2020') {
      throw StateError('not-original-100-sequence');
    }
    final second = <String>[];
    for (final candidate in formerlySaleGroup002) {
      if (!RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(candidate)) {
        throw StateError('second100-invalid-identifier');
      }
      second.add(candidate);
    }
    final union = [...originalNames, ...second];
    if (union.toSet().length != 200) {
      throw StateError('duplicate-between-original-100-and-second-100');
    }
    final db = FirebaseFirestore.instance;
    final collection = db.collection(DedaStage71Admin200.collection);
    final planned = <Map<String, Object>>[];
    for (final group in ['001','002']) {
      final items = group == '001' ? originalNames : second;
      for (var i=0;i<100;i++) {
        planned.add({
          'identifier':items[i],
          'group':group,
          'sequence':i+1,
          'baseColor':'gold',
          'status':'available',
        });
      }
    }
    // Small batches stay under Firestore Rules access-call limits, and can
    // resume without resetting a granted item on intermittent rural internet.
    var completed=0;
    for (var i=0;i<planned.length;i+=3) {
      if (FirebaseAuth.instance.currentUser?.uid != uid) {
        throw StateError('admin-session-changed-during-import');
      }
      final batch=db.batch();
      var hasWrites=false;
      for (final data in planned.skip(i).take(3)) {
        final id=data['identifier']! as String;
        final ref=collection.doc(id);
        final existing=await ref.get();
        if (existing.exists) {
          final old=existing.data()!;
          for (final key in ['identifier','group','sequence','baseColor']) {
            if(old[key] != data[key]) {
              throw StateError('existing-reserved-identifier-mismatch');
            }
          }
          if(!{'available','gifted','self_used'}.contains(old['status'])) {
            throw StateError('existing-reserved-id-invalid-status');
          }
        } else {
          hasWrites=true;
          batch.set(ref,data);
        }
      }
      if(hasWrites) await batch.commit();
      completed+= (i+3<=planned.length ? 3 : planned.length-i);
      progress?.call(completed,planned.length);
    }
    final verified=await read();
    if(verified.length!=200) throw StateError('import-readback-incomplete');
  }

  static Future<List<DedaStage71AdminId>> read() async {
    final uid = await _managerUid();
    final db = FirebaseFirestore.instance;
    final data = await db.collection(collection).limit(250).get();
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('admin-session-changed');
    }
    final rows = data.docs.map((doc) =>
        DedaStage71AdminId.fromRecord(doc.id, doc.data())).toList();
    final allIds = rows.map((x) => x.identifier).toSet();
    if (rows.length != 200 || allIds.length != 200 ||
        rows.where((x) => x.group == '001').length != 100 ||
        rows.where((x) => x.group == '002').length != 100) {
      throw StateError('original-200-admin-catalog-not-complete');
    }
    for (final group in ['001', '002']) {
      final nums = rows.where((x) => x.group == group)
          .map((x) => x.sequence).toSet();
      if (nums.length != 100 ||
          !List<int>.generate(100, (i) => i + 1)
              .every(nums.contains)) {
        throw StateError('admin-catalog-order-or-duplicate-mismatch');
      }
    }
    rows.sort((a, b) {
      final g = a.group.compareTo(b.group);
      return g != 0 ? g : a.sequence.compareTo(b.sequence);
    });
    return rows;
  }

  /// Atomic *free* use or grant. Catalog document can change status once,
  /// registry is created once; Firestore Rules must require both documents
  /// in the SAME transaction and independently check manager/recipient.
  static Future<void> assign({
    required DedaStage71AdminId row,
    required String recipientOriginalId,
    required bool selfUse,
  }) async {
    final uid = await _managerUid();
    if (!RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(recipientOriginalId) ||
        !row.available) {
      throw StateError('invalid-free-grant');
    }
    final db = FirebaseFirestore.instance;
    final entry = db.collection(collection).doc(row.identifier);
    final ownership = db.collection(registry).doc(row.identifier);
    final recipient = db.collection('deda_share_ids').doc(recipientOriginalId);
    await db.runTransaction<void>((tx) async {
      final inventory = await tx.get(entry);
      final oldGrant = await tx.get(ownership);
      final recipientSnap = await tx.get(recipient);
      if (FirebaseAuth.instance.currentUser?.uid != uid) {
        throw StateError('admin-session-rotated');
      }
      final item = inventory.data();
      final target = recipientSnap.data();
      if (item == null ||
          item['group'] != row.group ||
          item['sequence'] != row.sequence ||
          item['identifier'] != row.identifier ||
          item['baseColor'] != row.baseColor ||
          item['status'] != 'available' ||
          oldGrant.exists ||
          target == null ||
          target['kind'] != 'personal' ||
          target['active'] != true) {
        throw StateError('free-identifier-no-longer-available');
      }
      final kind = selfUse ? 'self_used' : 'gifted';
      tx.update(entry, {
        'status': kind,
        'recipientOriginalId': recipientOriginalId,
        'grantedAt': FieldValue.serverTimestamp(),
      });
      tx.set(ownership, {
        'identifier': row.identifier,
        'recipientOriginalId': recipientOriginalId,
        'group': row.group,
        'baseColor': row.baseColor,
        'kind': kind,
        'grantedByUid': uid,
        'grantedAt': FieldValue.serverTimestamp(),
      });
    });
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('admin-session-changed');
    }
    // Read AFTER commit. UI must never claim success from local optimistic state.
    final confirmed = await ownership.get();
    final data = confirmed.data();
    if (data == null ||
        data['identifier'] != row.identifier ||
        data['recipientOriginalId'] != recipientOriginalId ||
        data['kind'] != (selfUse ? 'self_used' : 'gifted') ||
        data['baseColor'] != row.baseColor) {
      throw StateError('grant-awaiting-server-confirmation');
    }
  }
}
