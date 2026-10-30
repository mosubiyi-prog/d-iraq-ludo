import 'dart:async';

import 'package:flutter/material.dart';

/// PRIVATE DEDA ACCOUNT DISPLAY SCOPE ONLY. NOT identity proof for payouts.
///
/// Captures the original anonymous Firebase UID plus original DEDA canonical
/// account at navigation. If either changes, the account-specific league page
/// is permanently revoked. No task, XP, wallet, Firestore or league writes.
/// The eventual server leaderboard reader MUST separately authenticate and
/// verify App Check, immutable canonical account binding and signed XP events.
class DedaWeeklyAccountViewGate extends StatefulWidget {
  const DedaWeeklyAccountViewGate({
    super.key,
    required this.readCanonicalAccount,
    required this.readSessionUid,
    required this.authEvents,
    required this.builder,
    this.refreshSignal,
  });

  /// Current original DEDA account selected by the app.
  /// Client preference is merely a DISPLAY scope, NOT login authority.
  final String Function() readCanonicalAccount;

  /// Current Firebase Auth UID; return null for missing/unauthorized sessions.
  final String? Function() readSessionUid;

  /// FirebaseAuth.instance.authStateChanges() in the actual DEDA app.
  final Stream<Object?> authEvents;
  final Listenable? refreshSignal;

  /// Called only while the captured viewer account + UID remain unchanged.
  final Widget Function(
    BuildContext context,
    String capturedAccountKey,
    bool Function() stillSameViewer,
  ) builder;

  @override
  State<DedaWeeklyAccountViewGate> createState() =>
      _DedaWeeklyAccountViewGateState();
}

class _DedaWeeklyAccountViewGateState
    extends State<DedaWeeklyAccountViewGate> {
  static final RegExp _account = RegExp(r'^[0-9]{10,16}$');
  static final RegExp _uid = RegExp(r'^[A-Za-z0-9_-]{8,128}$');

  late final String _capturedAccount;
  late final String _capturedUid;
  StreamSubscription<Object?>? _subscription;
  bool _revoked = false;

  String _readAccount() {
    try {
      return widget.readCanonicalAccount().trim();
    } catch (_) {
      return '';
    }
  }

  String _readUid() {
    try {
      return widget.readSessionUid()?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  bool _sameViewer() =>
      !_revoked &&
      _account.hasMatch(_capturedAccount) &&
      _uid.hasMatch(_capturedUid) &&
      _readAccount() == _capturedAccount &&
      _readUid() == _capturedUid;

  void _checkSession() {
    if (_revoked || !mounted) return;
    if (!_sameViewer()) {
      // Revocation persists, including if switching back to the old account:
      // reopening through the official home route is then required.
      setState(() => _revoked = true);
    }
  }

  @override
  void initState() {
    super.initState();
    _capturedAccount = _readAccount();
    _capturedUid = _readUid();
    _subscription = widget.authEvents.listen(
      (_) => _checkSession(),
      onError: (Object _) => _checkSession(),
    );
    widget.refreshSignal?.addListener(_checkSession);
  }

  @override
  void didUpdateWidget(covariant DedaWeeklyAccountViewGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authEvents != widget.authEvents) {
      _subscription?.cancel();
      _subscription = widget.authEvents.listen(
        (_) => _checkSession(),
        onError: (Object _) => _checkSession(),
      );
    }
    if (oldWidget.refreshSignal != widget.refreshSignal) {
      oldWidget.refreshSignal?.removeListener(_checkSession);
      widget.refreshSignal?.addListener(_checkSession);
    }
    _checkSession();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    widget.refreshSignal?.removeListener(_checkSession);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_sameViewer()) {
      return const Scaffold(
        body: SafeArea(
          child: Center(
            child: Text(
              'تغيّر الحساب أو انتهت الجلسة. ارجع للواجهة وافتح الدوري من جديد.',
              key: Key('deda_weekly_account_scope_revoked'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return widget.builder(context, _capturedAccount, _sameViewer);
  }
}
