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
    scope_path.write_text(scope)
