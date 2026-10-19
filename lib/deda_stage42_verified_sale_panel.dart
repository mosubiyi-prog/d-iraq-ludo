import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Only real server-approved Group002 stock. No guessed sales or fake diamonds.
class DedaStage42VerifiedSalePanel extends StatefulWidget {
  final String originalId;
  final ValueChanged<String> onPreview;
  final Future<void> Function() refreshOwned;
  const DedaStage42VerifiedSalePanel({
    super.key, required this.originalId,
    required this.onPreview, required this.refreshOwned,
  });
  @override
  State<DedaStage42VerifiedSalePanel> createState() =>
      _DedaStage42VerifiedSalePanelState();
}

class _DedaStage42VerifiedSalePanelState
    extends State<DedaStage42VerifiedSalePanel> {
  static const _live = bool.fromEnvironment(
      'DEDA_STAGE42_VERIFIED_SALE_LIVE', defaultValue: false);
  static const _premiumLive = bool.fromEnvironment(
      'DEDA_PREMIUM_IDS_SERVER_LIVE', defaultValue: false);
  static final _pattern = RegExp(r'^@DEDA-[A-Z0-9]{6}$');
  final _requestIds = <String, String>{};
  List<String>? _available;
  String? _busyId;
  String? _message;
  bool _loading = false;
  bool get _ready => _live && _premiumLive;
  @override
  void initState() {
    super.initState();
    if (_ready) WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }
  Future<Map<String, dynamic>> _call(
      String name, Map<String, dynamic> payload, String uid) async {
    if (!_ready || uid.isEmpty ||
        FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('authenticated-premium-call-required');
    }
    final result = await FirebaseFunctions.instance.httpsCallable(name,
        options: HttpsCallableOptions(timeout: const Duration(seconds: 40)))
        .call<Map<String, dynamic>>(payload);
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('authentication-rotated');
    }
    return Map<String, dynamic>.from(result.data);
  }
  Future<void> _load() async {
    if (!_ready || _loading || _busyId != null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    setState(() { _loading = true; _message = null; });
    try {
      final verified = await _call(
        'dedaPremiumListAvailableIdentifiers', {}, uid);
      final rows = verified['identifiers'];
      if (verified['serverConfirmed'] != true ||
          verified['priceDiamonds'] != 10000 ||
          rows is! List || rows.length > 100) {
        throw StateError('unverified-catalog');
      }
      final ids = <String>[];
      for (final row in rows) {
        if (row is! Map || row['identifier'] is! String ||
            row['priceDiamonds'] != 10000 ||
            !_pattern.hasMatch(row['identifier'] as String)) {
          throw StateError('unverified-catalog-item');
        }
        ids.add(row['identifier'] as String);
      }
      if (ids.toSet().length != ids.length) {
        throw StateError('duplicate-catalog-item');
      }
      if (mounted && FirebaseAuth.instance.currentUser?.uid == uid) {
        setState(() => _available = ids);
      }
    } catch (_) {
      if (mounted) setState(() {
        _available = null;
        _message = 'تعذّر التحقق من المعرفات المتاحة بالخادم.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
  Future<void> _buy(String wanted) async {
    if (!_ready || !_pattern.hasMatch(wanted) || _busyId != null ||
        !(_available?.contains(wanted) ?? false)) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    final agree = await showDialog<bool>(context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('تأكيد شراء المعرّف'),
        content: Text('شراء $wanted مقابل 10,000 ماسة حقيقية؟ '
            'سعر تصميم البطاقة منفصل 5,000 ماسة.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
              child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
              child: const Text('تأكيد')),
        ],
      ),
    );
    if (agree != true || !mounted ||
        FirebaseAuth.instance.currentUser?.uid != uid) return;
    setState(() { _busyId = wanted; _message = null; });
    // Same ID + same key on retries: never accidentally double debit.
    final requestId = _requestIds.putIfAbsent(wanted, () => 'idbuy_' +
        DateTime.now().toUtc().microsecondsSinceEpoch.toString());
    try {
      final receipt = await _call('dedaPremiumBuyIdentifier',
        {'identifier': wanted, 'requestId': requestId}, uid);
      if (receipt['serverConfirmed'] != true ||
          receipt['identifier'] != wanted ||
          receipt['diamondsCharged'] != 10000 ||
          receipt['alreadyOwned'] != false ||
          receipt['transactionId'] is! String ||
          (receipt['transactionId'] as String).isEmpty) {
        throw StateError('unverified-10k-receipt');
      }
      final owned = await _call('dedaPremiumReadIdentifiers', {}, uid);
      if (owned['serverConfirmed'] != true ||
          owned['accountUid'] != uid ||
          owned['originalId'] != widget.originalId ||
          owned['ownedIds'] is! List ||
          !(owned['ownedIds'] as List).contains(wanted)) {
        throw StateError('ownership-readback-pending');
      }
      _requestIds.remove(wanted);
      await widget.refreshOwned();
      if (mounted && FirebaseAuth.instance.currentUser?.uid == uid) {
        setState(() {
          _available = (_available ?? []).where((e) => e != wanted).toList();
          _message = 'تم تأكيد ملكية $wanted. تقدر تستخدمه من ملفك.';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _message =
        'تعذّر تأكيد نتيجة الشراء. أعد المحاولة على نفس المعرف '
        'حتى نستخدم نفس رقم العملية ولا نكرر الخصم.');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }
  @override
  Widget build(BuildContext context) {
    if (!_ready) return const Center(child: Text(
      'البيع الحقيقي يحتاج خادماً موثقاً، ولا توجد مبيعات وهمية هنا.'));
    return RefreshIndicator(onRefresh: _load, child: ListView(
      key: const Key('deda_stage42_verified_group002_list'),
      children: [
        const Padding(padding: EdgeInsets.all(10), child: Text(
          'المعرفات المعتمدة للبيع — 10,000 ماسة',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold),
        )),
        if (_loading) const LinearProgressIndicator(),
        if (_message != null) Padding(
          padding: const EdgeInsets.all(8), child: Text(_message!)),
        if (_available != null && _available!.isEmpty)
          const ListTile(title: Text('لا توجد معرفات معتمدة للبيع الآن.')),
        for (final id in _available ?? <String>[])
          Card(child: ListTile(
            title: Text(id, textDirection: TextDirection.ltr),
            subtitle: const Text('10,000 ماسة • سعر المعرف فقط'),
            onTap: () => widget.onPreview(id),
            trailing: FilledButton(
              key: ValueKey<String>('deda_stage42_buy_' + id),
              onPressed: _busyId == null ? () => _buy(id) : null,
              child: const Text('شراء'),
            ),
          )),
      ],
    ));
  }
}
