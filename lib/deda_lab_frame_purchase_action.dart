import 'package:flutter/material.dart';
import 'deda_lab_frame_secure_checkout.dart';

/// The original DEDA store visual flow: preview is free; paid Buy becomes Use
/// only after a verified receipt. Never trigger a client-only wallet debit.
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

  bool _sameItem(String owner, String frame) =>
      mounted && widget.originalId == owner && widget.frameId == frame;

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
      // Never apply old-account ownership or a pending debit result to
      // another account or another card.
      _busy = false;
      _owned = false;
      _error = null;
      if (DedaLabFrameSecureCheckout.live) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
      }
    }
  }

  Future<void> _refresh() async {
    if (!mounted || _busy || !DedaLabFrameSecureCheckout.live) return;
    final owner = widget.originalId;
    final frame = widget.frameId;
    setState(() { _busy = true; _error = null; });
    try {
      final owned = await DedaLabFrameSecureCheckout.isOwned(
        originalId: owner, frameId: frame);
      if (_sameItem(owner, frame)) setState(() => _owned = owned);
    } catch (_) {
      if (_sameItem(owner, frame)) {
        setState(() => _error = 'تعذّر التحقق من ملكية الإطار.');
      }
    } finally {
      if (_sameItem(owner, frame)) setState(() => _busy = false);
    }
  }

  Future<void> _buy() async {
    if (_busy || _owned || !DedaLabFrameSecureCheckout.live) return;
    final owner = widget.originalId;
    final frame = widget.frameId;
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('شراء الإطار'),
        content: const Text(
          'سعر الإطار 1,000 ماسة. الخصم مرة واحدة فقط بعد التأكيد. '
          'المعاينة مجانية ولا تخصم شيئاً.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('تأكيد الشراء'),
          ),
        ],
      ),
    );
    if (!_sameItem(owner, frame) || yes != true || _busy || _owned) return;
    setState(() { _busy = true; _error = null; });
    try {
      await DedaLabFrameSecureCheckout.buyOnce(
        originalId: owner, frameId: frame);
      if (_sameItem(owner, frame)) setState(() => _owned = true);
    } catch (error) {
      // Network timeouts can happen AFTER a real commit. Read receipt first,
      // never issue a second automatic payment.
      try {
        final owned = await DedaLabFrameSecureCheckout.isOwned(
          originalId: owner, frameId: frame);
        if (_sameItem(owner, frame) && owned) {
          setState(() => _owned = true);
        } else if (_sameItem(owner, frame)) {
          final insufficient = error.toString()
              .contains('insufficient-verified-gift-diamonds');
          setState(() => _error = insufficient
              ? 'رصيد الماسات الموثق للشراء غير كافٍ.'
              : 'لم يتأكد الشراء؛ لم نفعّل الإطار.');
        }
      } catch (_) {
        if (_sameItem(owner, frame)) {
          setState(() =>
              _error = 'الحالة غير مؤكدة؛ أعد التحقق قبل أي محاولة شراء.');
        }
      }
    } finally {
      if (_sameItem(owner, frame)) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Unlike a fake interactive Buy control, this is explicit until rollout.
    if (!DedaLabFrameSecureCheckout.live) {
      return const Column(mainAxisSize: MainAxisSize.min, children: [
        Text('1000 💎', style: TextStyle(fontWeight: FontWeight.bold)),
        Text('الشراء بعد التحقق', style: TextStyle(fontSize: 11)),
      ]);
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        height: 38,
        width: double.infinity,
        child: _owned
            ? OutlinedButton(
                onPressed: _busy ? null : widget.onVerifiedOwned,
                child: Text(_busy ? 'جار التحقق…' : 'استخدام'),
              )
            : FilledButton(
                onPressed: _busy ? null : _buy,
                child: Text(_busy ? 'جار التحقق…' : 'شراء — 1000 💎'),
              ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 4),
        Text(
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF9C2929), fontSize: 11),
        ),
        TextButton(
          onPressed: _busy ? null : _refresh,
          child: const Text('إعادة التحقق'),
        ),
      ],
    ]);
  }
}
