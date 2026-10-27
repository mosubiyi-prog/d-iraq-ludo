import 'dart:async';

import 'package:flutter/material.dart';

import 'deda_weekly_leaderboard_page.dart';
import 'deda_weekly_snapshot_decode.dart';

/// Guarded UI shell for the fixed owner-approved weekly leaderboard.
///
/// Source is NULL by default: NO cloud request and NO counterfeit results.
/// Production must supply an authenticated, App-Check-attested server callable
/// AFTER trusted XP receipts, snapshot issuer and Firestore rules exist.
/// This widget is NOT an authorization endpoint and never credits diamonds.
class DedaWeeklyLeaderboardSafeScreen extends StatefulWidget {
  const DedaWeeklyLeaderboardSafeScreen({
    super.key,
    this.loadVerifiedStandings,
    this.currentAccountStillAuthorized,
    this.refreshSignal,
    this.refreshInterval,
  });

  final Future<Object?> Function()? loadVerifiedStandings;

  /// MUST verify the same canonical DEDA account and session epoch captured
  /// before the async request. A new phone, logout or account switch invalidates
  /// old responses. Absent source/guard = blank unverified screen.
  final bool Function()? currentAccountStillAuthorized;

  /// Existing task-level XP notifier may trigger a read after XP changes.
  final Listenable? refreshSignal;

  /// Optional future verified-backend polling for ranks changed by other users.
  /// Disabled unless both reader and account guard are supplied.
  final Duration? refreshInterval;

  @override
  State<DedaWeeklyLeaderboardSafeScreen> createState() =>
      _DedaWeeklyLeaderboardSafeScreenState();
}

class _DedaWeeklyLeaderboardSafeScreenState
    extends State<DedaWeeklyLeaderboardSafeScreen>
    with WidgetsBindingObserver {
  DedaWeeklyServerSnapshotPair? _snapshot;
  Timer? _refresh;
  int _requestEpoch = 0;
  bool _requestInFlight = false;

  bool get _hasVerifiedReader =>
      widget.loadVerifiedStandings != null &&
      widget.currentAccountStillAuthorized != null;

  bool get _stillCurrent =>
      _hasVerifiedReader && widget.currentAccountStillAuthorized!();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attach();
  }

  void _attach() {
    widget.refreshSignal?.addListener(_onRefreshSignal);
    final interval = widget.refreshInterval;
    if (_hasVerifiedReader &&
        interval != null &&
        interval >= const Duration(seconds: 15)) {
      _refresh = Timer.periodic(interval, (_) => _read());
    }
    if (_hasVerifiedReader) {
      unawaited(_read());
    }
  }

  void _onRefreshSignal() {
    if (_hasVerifiedReader) unawaited(_read());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _hasVerifiedReader) {
      unawaited(_read());
    }
  }

  @override
  void didUpdateWidget(covariant DedaWeeklyLeaderboardSafeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loadVerifiedStandings != widget.loadVerifiedStandings ||
        oldWidget.currentAccountStillAuthorized !=
            widget.currentAccountStillAuthorized ||
        oldWidget.refreshSignal != widget.refreshSignal ||
        oldWidget.refreshInterval != widget.refreshInterval) {
      _detach(oldWidget);
      setState(() => _snapshot = null);
      _attach();
    }
  }

  void _detach(DedaWeeklyLeaderboardSafeScreen previous) {
    _requestEpoch++;
    _requestInFlight = false;
    _refresh?.cancel();
    _refresh = null;
    previous.refreshSignal?.removeListener(_onRefreshSignal);
  }

  Future<void> _read() async {
    if (!_hasVerifiedReader || _requestInFlight || !_stillCurrent) {
      if (_snapshot != null && !_stillCurrent && mounted) {
        setState(() => _snapshot = null);
      }
      return;
    }
    final epoch = ++_requestEpoch;
    _requestInFlight = true;
    try {
      final json = await widget.loadVerifiedStandings!();
      final converted = DedaWeeklyServerSnapshotPair.parse(json);
      if (!mounted || epoch != _requestEpoch || !_stillCurrent) {
        if (mounted && !_stillCurrent) setState(() => _snapshot = null);
        return;
      }
      setState(() => _snapshot = converted);
    } catch (_) {
      // Never retain a now-untrusted snapshot after source or session error.
      if (mounted && epoch == _requestEpoch) {
        setState(() => _snapshot = null);
      }
    } finally {
      if (epoch == _requestEpoch) _requestInFlight = false;
    }
  }

  @override
  void dispose() {
    _detach(widget);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safeSnapshot = _stillCurrent ? _snapshot : null;
    return DedaWeeklyLeaderboardPage(
      current: safeSnapshot?.current ??
          const DedaLeaderboardViewData(
            verified: false,
            rows: [],
            profilesByUid: {},
          ),
      previous: safeSnapshot?.previous ??
          const DedaLeaderboardViewData(
            verified: false,
            rows: [],
            profilesByUid: {},
          ),
    );
  }
}
