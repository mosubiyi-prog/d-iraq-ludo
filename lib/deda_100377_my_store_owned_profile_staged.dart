import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

/// DEDA Point12: READ-ONLY unified proof surface for owned account cosmetics.
/// No wallet/spending/grant/inventory mutations. Not imported by main.dart.
/// Never infer owned premium items from a local selected avatar/frame/ID.
enum DedaMyStoreKind {
  identifier('المعرّفات', 'Identifiers'),
  avatar('الصور الرمزية', 'Avatars'),
  frame('الإطارات', 'Frames'),
  background('الخلفيات', 'Backgrounds'),
  badge('الشارات', 'Badges');

  const DedaMyStoreKind(this.arabic, this.english);
  final String arabic;
  final String english;
}

enum DedaMyStoreOrigin { free, purchased, granted }

class DedaMyStoreEntry {
  final DedaMyStoreKind kind;
  final String itemId;
  final String displayName;
  final DedaMyStoreOrigin origin;
  final bool active;

  const DedaMyStoreEntry({
    required this.kind,
    required this.itemId,
    required this.displayName,
    required this.origin,
    required this.active,
  });
}

/// Only a server-authenticated, original-ID-matched inventory source may
/// construct a displayed proof.  `verifiedFor` is a secondary UI boundary;
/// a raw caller-set `serverConfirmed` is NOT itself an authorization receipt.
/// Live use also requires an audited owner-verified inventory reader.
class DedaMyStoreSnapshot {
  final String ownerUid;
  final String originalId;
  final bool serverConfirmed;
  final List<DedaMyStoreEntry> entries;

  const DedaMyStoreSnapshot({
    required this.ownerUid,
    required this.originalId,
    required this.serverConfirmed,
    required this.entries,
  });

  static final RegExp _original = RegExp(r'^@DEDA-[A-Z0-9]{6}$');
  static final RegExp _safeItemId = RegExp(r'^[A-Za-z0-9_@-]{1,64}$');

  bool verifiedFor(String uid, String original) {
    if (!serverConfirmed || uid.isEmpty || ownerUid != uid ||
        original != originalId || !_original.hasMatch(original)) {
      return false;
    }
    final known = <String>{};
    final activePerCategory = <DedaMyStoreKind>{};
    for (final item in entries) {
      if (!_safeItemId.hasMatch(item.itemId) ||
          item.displayName.trim().isEmpty ||
          item.displayName.length > 100 ||
          !known.add(item.kind.name + ':' + item.itemId)) return false;
      if (item.active && !activePerCategory.add(item.kind)) return false;
      // Original is routable even when the visible active alias is different.
      if (item.kind == DedaMyStoreKind.identifier &&
          item.origin == DedaMyStoreOrigin.free &&
          item.itemId != original) return false;
    }
    return entries.length <= 300;
  }
}

class DedaMyStorePage extends StatelessWidget {
  // This page is staged and disconnected from main.dart. A trusted production
  // item-source adapter and signed owner QA are mandatory before enabling.
  static const bool releaseEnabled = bool.fromEnvironment(
    'DEDA_100377_MY_STORE_VERIFIED_LIVE', defaultValue: false,
  );

  const DedaMyStorePage({
    super.key,
    required this.originalId,
    this.verifiedSnapshot,
    this.isArabic = true,
  });

  final String originalId;
  final DedaMyStoreSnapshot? verifiedSnapshot;
  final bool isArabic;

  String _text(String ar, String en) => isArabic ? ar : en;

  String? _trustedUid() {
    try {
      if (Firebase.apps.isEmpty) return null;
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _trustedUid();
    final inventory = releaseEnabled && uid != null &&
            verifiedSnapshot?.verifiedFor(uid, originalId) == true
        ? verifiedSnapshot
        : null;

    return Scaffold(
      appBar: AppBar(title: Text(_text('متجري', 'My Store'))),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: <Widget>[
          Text(
            _text('مقتنياتي الشخصية — المملوك والمستخدم حاليًا',
                'My account items — owned and currently equipped'),
            key: const Key('deda_p12_read_only_heading'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            _text('متجر الشراء منفصل عن متجري. لا يوجد خصم أو شراء هنا.',
                'Purchasing stays in the separate shop. No debit here.'),
          ),
          if (inventory == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _text(
                  'بانتظار إثبات ملكية العناصر من حسابك. لا نعرض مقتنيات غير متحققة.',
                  'Waiting for account-verified items. Unverified items are not shown.',
                ),
                key: const Key('deda_p12_ownership_unverified'),
              ),
            ),
          for (final kind in DedaMyStoreKind.values)
            _MyStoreCategory(
              kind: kind,
              isArabic: isArabic,
              entries: inventory == null
                  ? const <DedaMyStoreEntry>[]
                  : inventory.entries.where((e) => e.kind == kind).toList(),
              verified: inventory != null,
            ),
        ],
      ),
    );
  }
}

class _MyStoreCategory extends StatelessWidget {
  const _MyStoreCategory({
    required this.kind,
    required this.entries,
    required this.verified,
    required this.isArabic,
  });

  final DedaMyStoreKind kind;
  final List<DedaMyStoreEntry> entries;
  final bool verified;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final label = isArabic ? kind.arabic : kind.english;
    return Card(
      key: ValueKey<String>('deda_p12_section_' + kind.name),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(label, style: const TextStyle(
              fontWeight: FontWeight.w800, fontSize: 16,
            )),
            if (verified && entries.isEmpty)
              Text(isArabic
                  ? 'لا توجد عناصر مثبتة في هذا القسم'
                  : 'No verified items in this section'),
            if (!verified)
              Text(isArabic ? 'قيد التحقق من ملكية الحساب'
                  : 'Awaiting account ownership verification'),
            for (final item in entries)
              ListTile(
                dense: true,
                key: ValueKey<String>(
                  'deda_p12_owned_' + kind.name + '_' + item.itemId),
                title: Text(item.displayName),
                subtitle: Text(
                  item.origin == DedaMyStoreOrigin.free
                    ? (isArabic ? 'مجاني' : 'Free')
                    : item.origin == DedaMyStoreOrigin.granted
                      ? (isArabic ? 'ممنوح' : 'Granted')
                      : (isArabic ? 'تم شراؤه' : 'Purchased'),
                ),
                trailing: Text(item.active
                    ? (isArabic ? 'مستخدم' : 'Active')
                    : (isArabic ? 'مملوك' : 'Owned')),
              ),
          ],
        ),
      ),
    );
  }
}
