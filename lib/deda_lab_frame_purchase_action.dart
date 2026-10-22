import 'package:flutter/material.dart';
import 'deda_lab_frame_secure_checkout.dart';

/// Paid frame UI: the 1000-diamond price is fixed. Preview is ALWAYS free.
/// The buy button remains disabled until owner-approved live rules are tested.
class DedaLabFramePurchaseAction extends StatefulWidget {
  final String originalId;
  final String frameId;
  final VoidCallback onVerifiedOwned;
  const DedaLabFramePurchaseAction({
    super.key,
    required this.originalId,
    required this.frameId,
    required this.onVerifiedOwned,
  });

  @override
  State<DedaLabFramePurchaseAction> createState() =>
      _DedaLabFramePurchaseActionState();
}

class _DedaLabFramePurchaseActionState
    extends State<DedaLabFramePurchaseAction> {
  bool _busy = false;
  bool _owned = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (DedaLabFrameSecureCheckout.live) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    }
  }

  @override
  void didUpdateWidget(covariant DedaLabFramePurchaseAction old) {
    super.didUpdateWidget(old);
    if (old.originalId != widget.originalId ||
        old.frameId != widget.frameId) {
      _owned = false;
      _error = null;
      if (DedaLabFrameSecureCheckout.live) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
      }
    }
  }

  Future<void> _refresh() async {
    if (!mounted || _busy || !DedaLabFrameSecureCheckout.live) return;
    setState(() { _busy = true; _error = null; });
    try {
      final owned = await DedaLabFrameSecureCheckout.isOwned(
        originalId: widget.originalId, frameId: widget.frameId);
      if (mounted) {
        setState(() => _owned = owned);
        if (owned) widget.onVerifiedOwned();
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذّر التحقق من ملكية الإطار');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _buy() async {
    if (_busy || _owned || !DedaLabFrameSecureCheckout.live) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('شراء الإطار'),
        content: const Text(
          'السعر 1,000 ماسة. سيتم الخصم من الرصيد الموثق القابل للصرف فقط. '
          'المعاينة مجانية ولا تخصم شيئاً.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
            child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
            child: const Text('تأكيد الشراء')),
        ],
      ),
    );
    if (!mounted || yes != true) return;
    setState(() { _busy = true; _error = null; });
    try {
      await DedaLabFrameSecureCheckout.buyOnce(
        originalId: widget.originalId, frameId: widget.frameId);
      if (mounted) {
        setState(() => _owned = true);
        widget.onVerifiedOwned();
      }
    } catch (_) {
      // The request may have committed before network failure. Read first.
      try {
        final owned = await DedaLabFrameSecureCheckout.isOwned(
          originalId: widget.originalId, frameId: widget.frameId);
        if (mounted && owned) {
          setState(() => _owned = true);
          widget.onVerifiedOwned();
        } else if (mounted) {
          setState(() => _error = 'لم يتأكد الشراء؛ لم نفعّل الإطار.');
        }
      } catch (_) {
        if (mounted) {
          setState(() => _error = 'الحالة غير مؤكدة، أعد التحقق قبل الشراء.');
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!DedaLabFrameSecureCheckout.live) {
      return const Column(mainAxisSize: MainAxisSize.min, children: [
        Text('1000 💎', style: TextStyle(fontWeight: FontWeight.bold)),
        Text('الشراء بعد التحقق', style: TextStyle(fontSize: 11)),
      ]);
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      TextButton(
        onPressed: _busy ? null : _owned ? widget.onVerifiedOwned : _buy,
        child: Text(_busy ? 'جار التحقق…' :
          _owned ? 'استخدام' : 'شراء — 1000 💎'),
      ),
      if (_error != null)
        TextButton(onPressed: _busy ? null : _refresh,
          child: const Text('إعادة التحقق')),
    ]);
  }
}
