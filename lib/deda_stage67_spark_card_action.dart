import 'package:flutter/material.dart';

import 'deda_stage67_spark_secure_card_checkout.dart';

/// Stage67 — one safe real client purchase action. The *actual* owner-verified
/// Firestore Rules must be deployed before enabling this at build time.
/// Keep this widget OUT of final customer builds while that gate is false.
class DedaStage67SparkCardAction extends StatefulWidget {
  final String originalId;
  final String style;
  const DedaStage67SparkCardAction({
    super.key,
    required this.originalId,
    required this.style,
  });

  @override
  State<DedaStage67SparkCardAction> createState() =>
      _DedaStage67SparkCardActionState();
}

class _DedaStage67SparkCardActionState
    extends State<DedaStage67SparkCardAction> {
  bool _loading = false;
  bool _owned = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (DedaStage67SparkCardCheckout.live) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    }
  }

  Future<void> _refresh() async {
    if (!mounted || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final owned = await DedaStage67SparkCardCheckout.isOwned(
        originalId: widget.originalId,
        style: widget.style,
      );
      if (mounted) setState(() => _owned = owned);
    } catch (_) {
      if (mounted) setState(() {
        _error = 'تعذّر تأكيد الملكية بالخادم';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _buy() async {
    if (_loading || _owned || !DedaStage67SparkCardCheckout.live) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('تأكيد شراء البطاقة'),
        content: const Text(
          'سيُخصم 5,000 ماسة من رصيد الهدايا الموثق فقط. '
          'رصيد الإعلانات المحلي غير قابل للصرف بهذه العملية.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await DedaStage67SparkCardCheckout.buyCard(
        originalId: widget.originalId,
        style: widget.style,
      );
      if (mounted) setState(() => _owned = true);
    } catch (_) {
      // A lost network response may follow a completed commit; NEVER create
      // a second debit until protected ownership is checked again.
      try {
        final verified = await DedaStage67SparkCardCheckout.isOwned(
          originalId: widget.originalId,
          style: widget.style,
        );
        if (mounted) setState(() => _owned = verified);
      } catch (_) {
        if (mounted) setState(() {
          _error = 'الشراء لم يتأكد بعد. تحقق من الملكية قبل الإعادة.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!DedaStage67SparkCardCheckout.live) {
      return const Text('الشراء الآمن غير مفعّل',
        key: Key('deda_stage67_secure_checkout_off'));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton(
          key: Key('deda_stage67_shop_${widget.style}'),
          onPressed: _loading || _owned || _error != null ? null : _buy,
          child: Text(_loading ? 'جار التحقق…' :
            _owned ? 'مملوكة ✓' : 'شراء 5,000'),
        ),
        if (_error != null) TextButton(
          onPressed: _loading ? null : _refresh,
          child: const Text('إعادة التحقق'),
        ),
      ],
    );
  }
}
