import 'dart:async';

import 'package:flutter/material.dart';

/// The original DEDA user/anonymous Firebase auth can finish warming up after
/// tapping the league card. Never freeze an EMPTY UID then call it a logout.
/// Once a VALID identity is bound, account changes still revoke old results.
class DedaWeeklyAccountViewGate extends StatefulWidget {
  const DedaWeeklyAccountViewGate({
    super.key,
    required this.readCanonicalAccount,
    required this.readSessionUid,
    required this.authEvents,
    required this.builder,
    this.refreshSignal,
    this.startsAt,
    this.clock,
  });

  final String Function() readCanonicalAccount;
  final String? Function() readSessionUid;
  final Stream<Object?> authEvents;
  final Listenable? refreshSignal;
  final DateTime? startsAt;
  final DateTime Function()? clock;
  final Widget Function(BuildContext, String, bool Function()) builder;

  @override
  State<DedaWeeklyAccountViewGate> createState() =>
      _DedaWeeklyAccountViewGateState();
}

class _DedaWeeklyAccountViewGateState
    extends State<DedaWeeklyAccountViewGate> {
  static final RegExp _account = RegExp(r'^[0-9]{10,16}$');
  static final RegExp _uid = RegExp(r'^[A-Za-z0-9_-]{8,128}$');

  String? _boundAccount;
  String? _boundUid;
  bool _authReady = false;
  bool _revoked = false;
  int _pendingSeconds = 0;
  StreamSubscription<Object?>? _subscription;
  Timer? _poll;

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

  DateTime _now() => (widget.clock?.call() ?? DateTime.now()).toUtc();

  bool get _bound => _boundAccount != null && _boundUid != null;

  bool _sameViewer() =>
      _bound &&
      !_revoked &&
      _readAccount() == _boundAccount &&
      _readUid() == _boundUid;

  void _refreshSession() {
    if (!mounted || _revoked) return;
    final account = _readAccount();
    final uid = _readUid();

    if (!_bound) {
      // Wait for the FIRST Firebase auth-state emission. Reading currentUser
      // synchronously during navigation is not proof auth startup is complete.
      if (_authReady && _account.hasMatch(account) && _uid.hasMatch(uid)) {
        setState(() {
          _boundAccount = account;
          _boundUid = uid;
        });
      } else if (_authReady) {
        _pendingSeconds++;
        if (_pendingSeconds % 2 == 0) setState(() {});
      }
      return;
    }

    if (account != _boundAccount || uid != _boundUid) {
      setState(() => _revoked = true);
      _poll?.cancel();
      _poll = null;
      return;
    }
    final start = widget.startsAt;
    if (start != null && _now().isBefore(start.toUtc())) {
      // Live countdown, without attempting any Firestore reads before 06:00.
      setState(() {});
    } else {
      _poll?.cancel();
      _poll = null;
      // Build next frame at the actual start time and show shared standings.
      if (start != null) setState(() {});
    }
  }

  void _onAuthEvent(Object? _) {
    if (!_authReady) _authReady = true;
    _refreshSession();
  }

  void _attachAuth() {
    _subscription = widget.authEvents.listen(
      _onAuthEvent,
      onError: (Object _) => _onAuthEvent(null),
    );
  }

  @override
  void initState() {
    super.initState();
    _attachAuth();
    widget.refreshSignal?.addListener(_refreshSession);
    // Include a small retry window for account preferences that hydrate after
    // the Firebase stream. Never lose session or modify DEDA credentials.
    _poll = Timer.periodic(
      const Duration(seconds: 1), (_) => _refreshSession());
  }

  @override
  void didUpdateWidget(covariant DedaWeeklyAccountViewGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authEvents != widget.authEvents) {
      _subscription?.cancel();
      _authReady = false;
      _attachAuth();
    }
    if (oldWidget.refreshSignal != widget.refreshSignal) {
      oldWidget.refreshSignal?.removeListener(_refreshSession);
      widget.refreshSignal?.addListener(_refreshSession);
    }
    _refreshSession();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _subscription?.cancel();
    widget.refreshSignal?.removeListener(_refreshSession);
    super.dispose();
  }

  Widget _message(String label, {bool showSpinner = false}) =>
      Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showSpinner) ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                  ],
                  Text(label, textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18)),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () {
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      } else {
                        _refreshSession();
                      }
                    },
                    child: Text(Navigator.of(context).canPop()
                        ? 'رجوع للرئيسية' : 'إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_revoked) {
      return _message(
        'تم تبديل الحساب أثناء عرض الدوري. ارجع للرئيسية وافتح الدوري من جديد.',
      );
    }
    if (!_bound) {
      return _message(
        _authReady && _pendingSeconds >= 20
          ? 'تعذر تهيئة جلسة الدوري. لا حاجة لتسجيل الخروج أو حذف التطبيق.'
          : 'جاري تهيئة حساب الدوري...',
        showSpinner: _pendingSeconds < 20,
      );
    }
    if (!_sameViewer()) {
      return _message(
        'تغيّر الحساب أثناء فتح الدوري. ارجع للرئيسية وافتحه مجدداً.',
      );
    }
    final start = widget.startsAt;
    if (start != null) {
      final remaining = start.toUtc().difference(_now());
      if (remaining > Duration.zero) {
        final total = remaining.inSeconds + 1;
        final hours = (total ~/ 3600).toString().padLeft(2, '0');
        final minutes = ((total ~/ 60) % 60).toString().padLeft(2, '0');
        final seconds = (total % 60).toString().padLeft(2, '0');
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.emoji_events_outlined, size: 68),
                  const SizedBox(height: 16),
                  const Text('الدوري الأسبوعي',
                      style: TextStyle(
                        fontSize: 26, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  const Text('سيبدأ الدوري بعد',
                      style: TextStyle(fontSize: 20)),
                  const SizedBox(height: 10),
                  Text('$hours:$minutes:$seconds',
                    key: const Key('deda_weekly_prestart_countdown'),
                    style: const TextStyle(
                      fontSize: 36, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 14),
                  const Text('السبت 31 أكتوبر — الساعة 6 صباحاً بتوقيت العراق',
                      textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        );
      }
    }
    return widget.builder(context, _boundAccount!, _sameViewer);
  }
}
