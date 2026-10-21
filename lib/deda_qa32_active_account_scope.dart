import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'deda_stage71_free_owned_use_profile.dart';

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
    extends State<DedaQa32ActiveAccountScope> {
  DedaQa32ActiveAccountIdentity? _proof;
  StreamSubscription<User?>? _auth;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _auth = FirebaseAuth.instance.authStateChanges().listen((_) {
      _load();
    });
    DedaStage71ActiveIdRefresh.notifier.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(covariant DedaQa32ActiveAccountScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.originalId != widget.originalId) {
      setState(() => _proof = null);
      _load();
    }
  }

  Future<void> _load() async {
    final epoch = ++_epoch;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final original = widget.originalId;
    if (!mounted) return;
    if (_proof != null) setState(() => _proof = null);
    if (uid == null || !DedaStage71OwnedIdentifierService.enabled ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(original)) {
      return;
    }
    try {
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
      final next = DedaQa32ActiveAccountIdentity(
        uid: uid, originalId: original, displayId: active, fixedColor: color,
      );
      if (!mounted || epoch != _epoch ||
          FirebaseAuth.instance.currentUser?.uid != uid ||
          widget.originalId != original || !next.verifiedFor(uid, original)) {
        return;
      }
      setState(() => _proof = next);
    } catch (_) {
      // Unknown, failed or unauthorized reads must never invent an active ID.
      if (mounted && epoch == _epoch &&
          FirebaseAuth.instance.currentUser?.uid == uid) {
        setState(() => _proof = null);
      }
    }
  }

  @override
  void dispose() {
    ++_epoch;
    DedaStage71ActiveIdRefresh.notifier.removeListener(_load);
    _auth?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final proof = currentUid != null &&
            _proof?.verifiedFor(currentUid, widget.originalId) == true
        ? _proof
        : null;
    return widget.builder(context, proof);
  }
}
