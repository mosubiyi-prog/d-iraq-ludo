import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
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
  String? _ownedVerifiedUid;
  String? _error;
  StreamSubscription<User?>? _authSubscription;

  // DEDA_100377_POINT01_FRAME_OWNERSHIP_AUTH_ROTATION_INVALIDATION
  // Cache is presentation-only; a different authenticated UID can never
  // inherit a frame's server-confirmed Use button or pending checkout result.
  void _onAuthChanged(User? user) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _owned = false;
      _ownedVerifiedUid = null;
      _error = null;
    });
    if (user?.uid != null && DedaLabFrameSecureCheckout.live) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refresh();
      });
    }
  }


  // DEDA_100377_POINT01_FRAME_PURCHASE_ACTION_ACCOUNT_UID_GUARD
  // Even if the visible card stays mounted, a signed-in account can change
  // while an async receipt or purchase is pending. Never show or activate
  // another user's paid frame after that change.
  String? _currentUid() {
    try {
      if (Firebase.apps.isEmpty) return null;
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  bool _sameItem(String owner, String frame, String? uid) =>
      mounted &&
      widget.originalId == owner &&
      widget.frameId == frame &&
      uid != null &&
      _currentUid() == uid;

  void _clearIfAccountChanged(String owner, String frame, String? uid) {
    if (!mounted || widget.originalId != owner || widget.frameId != frame ||
        _currentUid() == uid) {
      return;
    }
    setState(() {
      _busy = false;
      _owned = false;
      _ownedVerifiedUid = null;
      _error = 'تغيّر الحساب؛ أعد التحقق من ملكية الإطار.';
    });
  }

  void _useVerifiedFrame() {
    if (!_busy && _owned && _ownedVerifiedUid != null &&
        _ownedVerifiedUid == _currentUid()) {
      widget.onVerifiedOwned();
      return;
    }
    if (mounted) {
      setState(() {
        _owned = false;
        _ownedVerifiedUid = null;
        _busy = false;
        _error = 'يلزم التحقق من ملكية الإطار لهذا الحساب.';
      });
    }
  }

  @override
  void initState() {
    super.initState();
    try {
      if (Firebase.apps.isNotEmpty) {
        _authSubscription = FirebaseAuth.instance.authStateChanges()
            .listen(_onAuthChanged);
      }
    } catch (_) {
      // Firebase not initialized: never show a cached premium ownership.
    }
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
      _ownedVerifiedUid = null;
      _error = null;
      if (DedaLabFrameSecureCheckout.live) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
      }
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted || _busy || !DedaLabFrameSecureCheckout.live) return;
    final owner = widget.originalId;
    final frame = widget.frameId;
    final uid = _currentUid();
    if (uid == null) return; // No owner proof, no paid ownership UI.
    setState(() { _busy = true; _error = null; });
    try {
      final owned = await DedaLabFrameSecureCheckout.isOwned(
        originalId: owner, frameId: frame);
      if (_sameItem(owner, frame, uid)) {
        setState(() {
          _owned = owned;
          _ownedVerifiedUid = owned ? uid : null;
        });
      }
    } catch (_) {
      if (_sameItem(owner, frame, uid)) {
        setState(() => _error = 'تعذّر التحقق من ملكية الإطار.');
      }
    } finally {
      if (_sameItem(owner, frame, uid)) {
        setState(() => _busy = false);
      } else {
        _clearIfAccountChanged(owner, frame, uid);
      }
    }
  }

  Future<void> _buy() async {
    if (_busy || !DedaLabFrameSecureCheckout.live ||
        (_owned && _ownedVerifiedUid == _currentUid())) {
      return;
    }
    final owner = widget.originalId;
    final frame = widget.frameId;
    final uid = _currentUid();
    if (uid == null) return;
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
    if (!_sameItem(owner, frame, uid)) {
      _clearIfAccountChanged(owner, frame, uid);
      return;
    }
    if (yes != true || _busy || _owned) return;
    setState(() { _busy = true; _error = null; });
    try {
      await DedaLabFrameSecureCheckout.buyOnce(
        originalId: owner, frameId: frame);
      if (_sameItem(owner, frame, uid)) {
        setState(() {
          _owned = true;
          _ownedVerifiedUid = uid;
        });
      }
    } catch (error) {
      // Network timeouts can happen AFTER a real commit. Read receipt first,
      // never issue a second automatic payment.
      try {
        final owned = await DedaLabFrameSecureCheckout.isOwned(
          originalId: owner, frameId: frame);
        if (_sameItem(owner, frame, uid) && owned) {
          setState(() {
            _owned = true;
            _ownedVerifiedUid = uid;
          });
        } else if (_sameItem(owner, frame, uid)) {
          final insufficient = error.toString()
              .contains('insufficient-verified-gift-diamonds');
          setState(() => _error = insufficient
              ? 'رصيد الماسات الموثق للشراء غير كافٍ.'
              : 'لم يتأكد الشراء؛ لم نفعّل الإطار.');
        }
      } catch (_) {
        if (_sameItem(owner, frame, uid)) {
          setState(() =>
              _error = 'الحالة غير مؤكدة؛ أعد التحقق قبل أي محاولة شراء.');
        }
      }
    } finally {
      if (_sameItem(owner, frame, uid)) {
        setState(() => _busy = false);
      } else {
        _clearIfAccountChanged(owner, frame, uid);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Even before the async auth listener is delivered, old-owner receipt
    // state must never render an actionable Use button for the next account.
    final ownedByCurrentUid = _owned && _ownedVerifiedUid != null &&
        _ownedVerifiedUid == _currentUid();
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
        child: ownedByCurrentUid
            ? OutlinedButton(
                onPressed: _busy ? null : _useVerifiedFrame,
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
