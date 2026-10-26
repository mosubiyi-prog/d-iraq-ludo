"""Opt-in, presentation-only fix for old-ID flash in original 100380 source.

Never changes account ownership, ID grants, routing, Firebase writes, or wallet.
Runs on the verified restore workspace, never on the immutable archive.
"""
from pathlib import Path


def _replace_exact(source: str, before: str, after: str, label: str) -> str:
    if source.count(before) != 1:
        raise ValueError('ID flash binding source mismatch: ' + label)
    return source.replace(before, after, 1)


def bind(output):
    root = Path(output)
    path = root / 'lib/deda_six_active_identity.dart'
    source = path.read_text()
    source = _replace_exact(
        source,
        """      final id = proof?.displayId ?? originalId;
      return Directionality(textDirection: TextDirection.ltr,
        child: selectable ? SelectableText(id, style: style, textAlign: textAlign)
          : Text(id, style: style, textAlign: textAlign));""",
        """      // Do not briefly display the canonical ID before a server-verified
      // active ID arrives: this looks like the account changed its ID.
      // Keep the canonical ID for backend routing, not as a loading fallback.
      final id = proof?.displayId ??
          (DedaStage71OwnedIdentifierService.enabled ? null : originalId);
      if (id == null) {
        return Text('جارٍ التحقق من المعرّف…',
          key: const ValueKey('deda-active-id-awaiting-verification'),
          textAlign: textAlign,
          style: style,
        );
      }
      return Directionality(textDirection: TextDirection.ltr,
        child: selectable ? SelectableText(id, style: style, textAlign: textAlign)
          : Text(id, style: style, textAlign: textAlign));""",
        'active owner ID',
    )
    source = _replace_exact(
        source,
        """        if (uid == null || uid != FirebaseAuth.instance.currentUser?.uid) return fallback;""",
        """        if (uid == null || uid != FirebaseAuth.instance.currentUser?.uid) {
          return const SizedBox.shrink(); // No unverified sender ID flash.
        }""",
        'received sender initial state',
    )
    source = _replace_exact(
        source,
        """            if (snapshot.hasError || snapshot.data?.metadata.isFromCache != false ||
                uid != FirebaseAuth.instance.currentUser?.uid)
              return fallback;""",
        """            if (snapshot.hasError ||
                uid != FirebaseAuth.instance.currentUser?.uid) {
              return const SizedBox.shrink();
            }
            // Wait for current server state; only then may the unchanged
            // original be shown when no premium ID is actually active.
            if (!snapshot.hasData ||
                snapshot.data?.metadata.isFromCache != false) {
              return const Text('جارٍ التحقق من المعرّف…');
            }""",
        'received sender verified projection',
    )
    path.write_text(source)

    scope_path = root / 'lib/deda_qa32_active_account_scope.dart'
    scope = scope_path.read_text()
    scope = _replace_exact(
        scope,
        """    if (_proof != null) setState(() => _proof = null);
    if (dedaStabilityIdentityPilot && _paused) return;""",
        """    // Keep a verified same-owner ID visible during a normal refresh.
    // Never carry proof over an auth/original-ID change.
    if (_proof != null &&
        (uid == null || !_proof!.verifiedFor(uid, original))) {
      setState(() => _proof = null);
    }
    if (dedaStabilityIdentityPilot && _paused) return;""",
        'same-owner refresh',
    )
    scope = _replace_exact(
        scope,
        """  void _refresh() {
    _reads.invalidate();
    _load();
  }""",
        """  void _refresh() {
    // Active-ID selection changed on this same device. Do not keep showing
    // the PREVIOUS premium ID while checking the newly chosen one.
    _invalidateProof();
    _load();
  }""",
        'active selection update',
    )
    # Join the same verified owner's simultaneous display reads across
    # multiple widgets. The key includes the active-selection generation and
    # promises are discarded immediately after completion: no persistent cache.
    scope = _replace_exact(
        scope,
        "import 'package:firebase_core/firebase_core.dart';",
        "import 'package:firebase_core/firebase_core.dart';\n"
        "import 'package:cloud_firestore/cloud_firestore.dart';\n"
        "import 'deda_stage71_free_manager_200_service.dart';",
        'direct registry read imports',
    )
    scope = _replace_exact(
        scope,
        """  @override
  Future<DedaQa32ActiveAccountIdentity> readVerified(
      String uid, String original) async {
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
  }""",
        """  // Share only in-flight server verification, never a cross-login cache.
  // Selection generation separates reads that overlap an active-ID change.
  static final Map<(String, String, int), Future<DedaQa32ActiveAccountIdentity>>
      _inFlight = {};

  @override
  Future<DedaQa32ActiveAccountIdentity> readVerified(
      String uid, String original) {
    final key = (uid, original, DedaStage71ActiveIdRefresh.notifier.value);
    final existing = _inFlight[key];
    if (existing != null) return existing;
    final pending = _readFresh(uid, original);
    _inFlight[key] = pending;
    // Observe both outcomes; do not retain a completed result or an error.
    pending.then((_) {
      if (identical(_inFlight[key], pending)) _inFlight.remove(key);
    }, onError: (Object _, StackTrace __) {
      if (identical(_inFlight[key], pending)) _inFlight.remove(key);
    });
    return pending;
  }

  Future<DedaQa32ActiveAccountIdentity> _readFresh(
      String uid, String original) async {
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('identity-owner-changed');
    }
    // active() already checks original-account ownership, active grant,
    // and gift receipt against SERVER; do not enumerate all 200 owned IDs.
    final active = await DedaStage71OwnedIdentifierService.active(original);
    String? color;
    if (active != original) {
      final record = await FirebaseFirestore.instance
          .collection(DedaStage71Admin200.registry).doc(active)
          .get(const GetOptions(source: Source.server));
      if (FirebaseAuth.instance.currentUser?.uid != uid) {
        throw StateError('identity-owner-changed');
      }
      final grant = DedaStage71OwnedIdentifier.read(
          record.id, record.data() ?? <String, dynamic>{}, original);
      color = grant.baseColor;
    }
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('identity-owner-changed');
    }
    return DedaQa32ActiveAccountIdentity(
      uid: uid, originalId: original, displayId: active, fixedColor: color,
    );
  }""",
        'one fresh verified lookup instead of a repeated full owned-list read',
    )
    source = _replace_exact(
        source,
        "    } catch(_) {return same()?original:null;}",
        "    } catch(_) {\\n      // Never copy an unverified old ID on failure.\\n      return null;\\n    }",
        'copy resolution does not fall back to stale original ID',
    )
    scope_path.write_text(scope)
