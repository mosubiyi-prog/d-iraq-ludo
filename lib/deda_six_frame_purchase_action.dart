import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'deda_owner18_frame_checkout.dart';

/// The original DEDA store visual flow: preview is free; paid Buy becomes Use
/// only after a verified receipt. Never trigger a client-only wallet debit.
class DedaSixFramePurchaseAction extends StatefulWidget {
  final String originalId;
  final String frameId;
  final Future<bool> Function() onVerifiedOwned;
  final bool isActive;
  final ValueChanged<bool>? onOwnershipVerified;
  final double width;
  const DedaSixFramePurchaseAction({
    super.key,
    required this.originalId,
    required this.frameId,
    required this.onVerifiedOwned,
    this.width = 108,
    this.isActive = false,
    this.onOwnershipVerified,
  });

  @override
  State<DedaSixFramePurchaseAction> createState() =>
      _DedaSixFramePurchaseActionState();
}

class _DedaSixFramePurchaseActionState
    extends State<DedaSixFramePurchaseAction> {
  int _verificationEpoch = 0;
  bool _busy = false;
  String? _lastAuthUid;
  bool _owned = false;
  String? _ownedVerifiedUid;
  String? _error;
  StreamSubscription<User?>? _authSubscription;

  // DEDA_100377_POINT01_FRAME_OWNERSHIP_AUTH_ROTATION_INVALIDATION
  // Cache is presentation-only; a different authenticated UID can never
  // inherit a frame's server-confirmed Use button or pending checkout result.
  void _onAuthChanged(User? user) {
    if (!mounted) return;
    // Firebase auth streams may repeat the same UID. Do not reset an
    // in-flight purchase or its verified ownership for duplicate events.
    if (_lastAuthUid == user?.uid) return;
    _lastAuthUid = user?.uid;
    _verificationEpoch++;
    setState(() {
      _busy = false;
      _owned = false;
      _ownedVerifiedUid = null;
      _error = null;
    });
    if (user?.uid != null) {
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
    if (!mounted ||
        widget.originalId != owner ||
        widget.frameId != frame ||
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

  Future<void> _useVerifiedFrame() async {
    if (_busy || widget.isActive) return;
    final owner = widget.originalId, frame = widget.frameId;
    final uid = _currentUid();
    if (!_owned || uid == null || _ownedVerifiedUid != uid) return;
    setState(() { _busy = true; _error = null; });
    try {
      final confirmed = await widget.onVerifiedOwned();
      if (_sameItem(owner, frame, uid) && !confirmed) {
        setState(() => _error = 'لم يتأكد تفعيل الإطار؛ أعد المحاولة.');
      }
    } catch (_) {
      if (_sameItem(owner, frame, uid)) {
        setState(() => _error = 'تعذّر حفظ الإطار بالحساب.');
      }
    } finally {
      if (_sameItem(owner, frame, uid)) setState(() => _busy = false);
      else _clearIfAccountChanged(owner, frame, uid);
    }
  }

  @override
  void initState() {
    super.initState();
    try {
      if (Firebase.apps.isNotEmpty) {
        _authSubscription =
            FirebaseAuth.instance.authStateChanges().listen(_onAuthChanged);
      }
    } catch (_) {
      // Firebase not initialized: never show a cached premium ownership.
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void didUpdateWidget(covariant DedaSixFramePurchaseAction old) {
    super.didUpdateWidget(old);
    if (old.originalId != widget.originalId || old.frameId != widget.frameId) {
      // Never apply old-account ownership or a pending debit result to
      // another account or another card.
      _verificationEpoch++;
      _busy = false;
      _owned = false;
      _ownedVerifiedUid = null;
      _error = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted || _busy) return;
    final owner = widget.originalId;
    final frame = widget.frameId;
    final uid = _currentUid();
    final epoch = _verificationEpoch;
    if (uid == null) return; // No owner proof, no paid ownership UI.
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final owned = await DedaOwner18FrameCheckout.isOwned(
          originalId: owner, frameId: frame);
      if ((epoch == _verificationEpoch && _sameItem(owner, frame, uid))) {
        setState(() {
          _owned = owned;
          _ownedVerifiedUid = owned ? uid : null;
        });
        widget.onOwnershipVerified?.call(owned);
      }
    } catch (_) {
      if ((epoch == _verificationEpoch && _sameItem(owner, frame, uid))) {
        setState(() => _error = 'تعذّر التحقق من ملكية الإطار.');
      }
    } finally {
      if ((epoch == _verificationEpoch && _sameItem(owner, frame, uid))) {
        setState(() => _busy = false);
      } else if (mounted && epoch != _verificationEpoch) {
        // A newer auth/card verification owns the busy state. An older
        // asynchronous completion must never clear or overwrite it.
      } else {
        _clearIfAccountChanged(owner, frame, uid);
      }
    }
  }

  Future<void> _buy() async {
    if (_busy ||
        !DedaOwner18FrameCheckout.live ||
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
            'سعر الإطار 1,000 ماسة من رصيدك، ويُحفظ ضمن مقتنيات حسابك. '
            'المعاينة مجانية. هل تريد تأكيد الشراء؟'),
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
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // DEDA_100377_POINT01_NO_FALSE_DISPLAY_BALANCE_CHECKOUT
      // The visible total includes sources that are not yet server-verified
      // for spending. Never claim that total is eligible or charge it locally.
      await DedaOwner18FrameCheckout.buyOnce(originalId: owner, frameId: frame);
      if (_sameItem(owner, frame, uid)) {
        setState(() {
          _owned = true;
          _ownedVerifiedUid = uid;
        });
        widget.onOwnershipVerified?.call(true);
      }
    } catch (error) {
      // Network timeouts can happen AFTER a real commit. Read receipt first,
      // never issue a second automatic payment.
      try {
        final owned = await DedaOwner18FrameCheckout.isOwned(
            originalId: owner, frameId: frame);
        if (_sameItem(owner, frame, uid) && owned) {
          setState(() {
            _owned = true;
            _ownedVerifiedUid = uid;
          });
          widget.onOwnershipVerified?.call(true);
        } else if (_sameItem(owner, frame, uid)) {
          final insufficient =
              error.toString().contains('insufficient-native-diamonds');
          setState(() => _error = insufficient
              ? 'رصيد الماسات المتاح للشراء غير كافٍ.'
              : 'لم يتأكد الشراء؛ لم نفعّل الإطار.');
        }
      } catch (_) {
        if (_sameItem(owner, frame, uid)) {
          setState(() => _error =
              'الشراء يحتاج تأكيد الحفظ؛ اضغط إعادة التحقق قبل المحاولة مجددًا.');
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
    final ownedByCurrentUid = _owned &&
        _ownedVerifiedUid != null &&
        _ownedVerifiedUid == _currentUid();
    // Unlike a fake interactive Buy control, this is explicit until rollout.
    if (!DedaOwner18FrameCheckout.live) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        if (ownedByCurrentUid)
          OutlinedButton(
            onPressed: _busy || widget.isActive ? null : _useVerifiedFrame,
            child: DedaSixFrameButtonLabel(_busy ? 'جار التحقق…' : widget.isActive ? 'مستخدم' : 'استخدام'),
          )
        else ...[
          const Text('1000 💎', style: TextStyle(fontWeight: FontWeight.bold)),
          const Text('الشراء بعد التحقق', style: TextStyle(fontSize: 11)),
        ],
        if (_error != null)
          TextButton(
            onPressed: _busy ? null : _refresh,
            child: const Text('إعادة التحقق'),
          ),
      ]);
    }
    return SizedBox(
        width: widget.width,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: 42,
            width: double.infinity,
            child: ownedByCurrentUid
                ? OutlinedButton(
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                    onPressed: _busy || widget.isActive ? null : _useVerifiedFrame,
                    child: DedaSixFrameButtonLabel(_busy ? 'جار التحقق…' : widget.isActive ? 'مستخدم' : 'استخدام'),
                  )
                : FilledButton(
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                    onPressed: _busy ? null : _buy,
                    child: DedaSixFrameButtonLabel(_busy ? 'جار التحقق…' : 'شراء — 1000 💎'),
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
        ]));
  }
}

/// A single line scales into narrow three-column cells, including large fonts.
class DedaSixFrameButtonLabel extends StatelessWidget {
  const DedaSixFrameButtonLabel(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) => FittedBox(fit: BoxFit.scaleDown,
    child: Text(label, maxLines: 1, softWrap: false,
      style: const TextStyle(fontSize: 13)));
}
