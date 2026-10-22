import 'package:flutter/material.dart';

/// DEDA 100377 / Point12 — read-only personal inventory, never an acquisition shop.
/// Only callers with an actual verified server receipt may use [serverVerified].
/// SharedPreferences selections are [deviceSaved], never proven purchases.
enum DedaMyStoreSection {
  identifiers,
  avatars,
  frames,
  backgrounds,
  badges,
  purchasedAndGranted,
}

enum DedaMyStoreProof { basicFree, deviceSaved, serverVerified }

class DedaMyStoreItem {
  const DedaMyStoreItem({
    required this.id,
    required this.label,
    required this.section,
    required this.proof,
    this.active = false,
    this.receiptKind,
  });

  final String id;
  final String label;
  final DedaMyStoreSection section;
  final DedaMyStoreProof proof;
  final bool active;

  /// Only 'purchase' or 'gift' with serverVerified may enter the final section.
  final String? receiptKind;
}

class DedaMyStorePage extends StatelessWidget {
  const DedaMyStorePage({
    super.key,
    required this.originalId,
    required this.items,
    this.isArabic = true,
    this.onOpenIdentifierShop,
  });

  final String originalId;
  final List<DedaMyStoreItem> items;
  final bool isArabic;
  /// Preserves the ORIGINAL acquisition store route from the profile grid,
  /// but keeps only one owner-facing profile tile named My Store.
  final VoidCallback? onOpenIdentifierShop;

  String _t(String ar, String en) => isArabic ? ar : en;

  String _heading(DedaMyStoreSection section) {
    switch (section) {
      case DedaMyStoreSection.identifiers:
        return _t('معرّفاتي', 'My identifiers');
      case DedaMyStoreSection.avatars:
        return _t('الصور الرمزية', 'Avatars');
      case DedaMyStoreSection.frames:
        return _t('الإطارات', 'Frames');
      case DedaMyStoreSection.backgrounds:
        return _t('الخلفيات', 'Backgrounds');
      case DedaMyStoreSection.badges:
        return _t('الشارات', 'Badges');
      case DedaMyStoreSection.purchasedAndGranted:
        return _t('المشتريات والهدايا المثبتة', 'Verified purchases and gifts');
    }
  }

  String _proofLabel(DedaMyStoreItem item) {
    switch (item.proof) {
      case DedaMyStoreProof.basicFree:
        return _t('أساسي / مجاني', 'Basic / free');
      case DedaMyStoreProof.deviceSaved:
        return _t('محفوظ على هذا الجهاز', 'Saved on this device');
      case DedaMyStoreProof.serverVerified:
        if (item.receiptKind == 'purchase') {
          return _t('شراء مثبت بالخادم', 'Server-verified purchase');
        }
        if (item.receiptKind == 'gift') {
          return _t('هدية مثبتة بالخادم', 'Server-verified gift');
        }
        return _t('ملكية مثبتة بالخادم', 'Server-verified ownership');
    }
  }

  bool _isVerifiedTransaction(DedaMyStoreItem item) =>
      item.proof == DedaMyStoreProof.serverVerified &&
      (item.receiptKind == 'purchase' || item.receiptKind == 'gift');

  List<DedaMyStoreItem> _itemsFor(DedaMyStoreSection section) {
    final selected = section == DedaMyStoreSection.purchasedAndGranted
        ? items.where(_isVerifiedTransaction)
        : items.where((item) => item.section == section);
    final unique = <String, DedaMyStoreItem>{};
    for (final item in selected) {
      // The active visual choice can have only one entry for a given item.
      unique['${item.section.name}:${item.id}'] = item;
    }
    return unique.values.toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('متجري', 'My Store')),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        key: const Key('deda_p12_my_store_read_only'),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
          Text(
            originalId,
            key: const Key('deda_p12_canonical_original_id'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 7),
          Text(
            _t(
              'مقتنيات حسابك فقط؛ الشراء يتم من المتاجر الأصلية. ما حُفظ على الجهاز ليس إثبات شراء أو هدية، ولا توجد أي عملية خصم هنا.',
              'Personal inventory only. Purchases happen in existing shops. Device-saved choices do not prove ownership. No charges here.',
            ),
            key: const Key('deda_p12_no_fake_ownership_or_checkout'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          if (onOpenIdentifierShop != null) ...<Widget>[
            Card(
              child: ListTile(
                key: const Key('deda_p12_original_identifier_shop_entry'),
                leading: const Icon(Icons.storefront_rounded),
                title: Text(_t('متجر المعرّفات', 'Identifier store')),
                subtitle: Text(_t(
                  'الانتقال إلى المتجر الأصلي للشراء؛ لا يوجد خصم في متجري.',
                  'Open the existing identifier acquisition shop. No charge here.',
                )),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: onOpenIdentifierShop,
              ),
            ),
            const SizedBox(height: 12),
          ],
          for (final section in DedaMyStoreSection.values) ...<Widget>[
            Card(
              key: ValueKey<String>('deda_p12_section_${section.name}'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      _heading(section),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    if (_itemsFor(section).isEmpty)
                      Text(
                        _t(
                          'لا توجد مقتنيات مثبتة للعرض هنا حاليًا.',
                          'No confirmed items to show here yet.',
                        ),
                        key: ValueKey<String>(
                          'deda_p12_empty_${section.name}',
                        ),
                      ),
                    for (final item in _itemsFor(section))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        key: ValueKey<String>('deda_p12_item_${item.section.name}_${item.id}'),
                        title: Text(item.label),
                        subtitle: Text(_proofLabel(item)),
                        trailing: item.active
                            ? Text(_t('مستخدمة', 'Active'))
                            : null,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
          ],
        ),
      ),
    );
  }
}
