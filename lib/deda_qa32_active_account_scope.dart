import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'deda_stage71_free_owned_use_profile.dart';
import 'deda_stability_read_scope.dart';

/// Verified *owner-only* account display. Never changes the immutable
/// sharePersonalId used for location routing and friend lookup.
class DedaQa32ActiveAccountIdentity {
  final String uid;
  final String originalId;
  final String displayId;
  final String? fixedColor;

  const DedaQa32ActiveAccountIdentity({
    required this.uid,
    required this.originalId,
    required this.displayId,
    required this.fixedColor,
  });

  bool get isPremium => displayId != originalId && fixedColor != null;

  bool verifiedFor(String currentUid, String currentOriginal) =>
      uid == currentUid &&
      originalId == currentOriginal &&
      RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(originalId) &&
      (displayId == originalId && fixedColor == null ||
          displayId != originalId &&
              RegExp(r'^@DEDA-[A-Z0-9]{4,12}$').hasMatch(displayId) &&
              {'gold', 'diamond', 'royal', 'pink'}.contains(fixedColor));
}

typedef DedaQa32ActiveAccountBuilder = Widget Function(
    BuildContext context, DedaQa32ActiveAccountIdentity? proof);

/// UI wrapper for use on Account Info and the sender's own location share
/// page. A successful server read is mandatory before showing an alias.
/// No cross-account alias may leak through the old local widget state.
class DedaQa32ActiveAccountScope extends StatefulWidget {
  final String originalId;
  final DedaQa32ActiveAccountBuilder builder;

  const DedaQa32ActiveAccountScope({
    super.key,
    required this.originalId,
    required this.builder,
  });

  @override
  State<DedaQa32ActiveAccountScope> createState() =>
      _DedaQa32ActiveAccountScopeState();
}

class _DedaQa32ActiveAccountScopeState
    extends State<DedaQa32ActiveAccountScope> with WidgetsBindingObserver {
  DedaQa32ActiveAccountIdentity? _proof;
  StreamSubscription<User?>? _auth;
  int _epoch = 0;
  final _reads = DedaStabilityReadScope<DedaQa32ActiveAccountIdentity>();
  bool _authAttachQueued = false;
  // DEDA_100377_POINT13_LATE_FIREBASE_INIT_ACCOUNT_SCOPE_REARM
  // A page can mount before Firebase.initializeApp completes. The canonical
  // fallback stays until an actual session and Stage71 grant are verified.
  // Re-arm on app resume/parent rebuild without leaking prior UID proof.

  // Widget tests and initial cold-start frames may render Account Info before
  // Firebase.initializeApp(). A missing app MUST NOT crash the whole page.
  bool get _firebaseReady {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  String? _currentUid() {
    if (!_firebaseReady) return null;
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  void _attachAuthWhenReady() {
    if (!mounted || _auth != null || !_firebaseReady) return;
    try {
      _auth = FirebaseAuth.instance.authStateChanges().listen((_) {
        _reads.invalidate();
        _load();
      });
      // After late initialization the fresh session will trigger _load.
      _load();
    } catch (_) {
      // Firebase isn't ready: keep the canonical original fallback.
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Always listen, even if Firebase initialization is pending.
    DedaStage71ActiveIdRefresh.notifier.addListener(_refresh);
    // Attach after first frame as mounted is false during initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _attachAuthWhenReady();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Firebase may have become ready while this screen was already mounted.
    if (_auth == null && _firebaseReady && !_authAttachQueued) {
      _authAttachQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _authAttachQueued = false;
        if (mounted) _attachAuthWhenReady();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _attachAuthWhenReady();
      _refresh(); // server-verified refresh, never a local alias guess
    }
  }

  @override
  void didUpdateWidget(covariant DedaQa32ActiveAccountScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reattach if this owner header survived Firebase initialization.
    if (_auth == null && _firebaseReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _attachAuthWhenReady();
      });
    }
    if (oldWidget.originalId != widget.originalId) {
      _reads.invalidate();
      setState(() => _proof = null);
      _load();
    }
  }

  void _refresh() {
    _reads.invalidate();
    _load();
  }

  Future<void> _load() async {
    final epoch = ++_epoch;
    final uid = _currentUid();
    final original = widget.originalId;
    if (!mounted) return;
    if (_proof != null) setState(() => _proof = null);
    if (uid == null || !DedaStage71OwnedIdentifierService.enabled ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(original)) {
      return;
    }
    try {
      Future<DedaQa32ActiveAccountIdentity> readVerified() async {
        // The service separately checks users/{uid}, deda_sessions/{uid},
        // original ownership and, for gifted aliases, immutable receipt.
        final active = await DedaStage71OwnedIdentifierService.active(original);
        String? color;
        if (active != original) {
          final owned = await DedaStage71OwnedIdentifierService.owned(original);
          final matching = owned.where((row) => row.identifier == active).toList();
          if (matching.length != 1) throw StateError('alias-not-owned');
          color = matching.single.baseColor;
        }
        return DedaQa32ActiveAccountIdentity(
          uid: uid, originalId: original, displayId: active, fixedColor: color,
        );
      }
      final next = dedaStabilityIdentityPilot
          ? await _reads.run(
              key: (uid, original),
              isCurrent: () => mounted && _currentUid() == uid &&
                  widget.originalId == original,
              read: readVerified,
              retryWhen: (error) => error is FirebaseException &&
                  {'unavailable', 'deadline-exceeded'}.contains(error.code),
            )
          : await readVerified();
      if (!mounted || epoch != _epoch ||
          _currentUid() != uid ||
          widget.originalId != original || !next.verifiedFor(uid, original)) {
        return;
      }
      setState(() => _proof = next);
    } catch (_) {
      // Unknown, failed or unauthorized reads must never invent an active ID.
      if (mounted && epoch == _epoch &&
          _currentUid() == uid) {
        setState(() => _proof = null);
      }
    }
  }

  @override
  void dispose() {
    ++_epoch;
    _reads.dispose();
    DedaStage71ActiveIdRefresh.notifier.removeListener(_refresh);
    WidgetsBinding.instance.removeObserver(this);
    _auth?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = _currentUid();
    final proof = currentUid != null &&
            _proof?.verifiedFor(currentUid, widget.originalId) == true
        ? _proof
        : null;
    return widget.builder(context, proof);
  }
}
