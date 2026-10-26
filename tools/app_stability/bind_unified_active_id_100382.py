"""100382: bind one verified display ID across profile, label and Use action.

Applies after 100381's no-flash patch to a verified temporary restore.
Fails closed when any original source anchor changes. Does not modify
Firestore rules, session routing, grants, wallets or deployed application.
"""
from pathlib import Path
import shutil


def once(text, before, after, label):
    if text.count(before) != 1:
        raise ValueError('unified-active-id source mismatch: '+label)
    return text.replace(before, after, 1)


def bind(output):
    root = Path(output)
    repo = Path(__file__).resolve().parents[2]
    shutil.copy2(repo/'lib/deda_verified_active_id_store.dart',
                 root/'lib/deda_verified_active_id_store.dart')
    shutil.copy2(repo/'test/deda_verified_active_id_store_test.dart',
                 root/'test/deda_verified_active_id_store_test.dart')

    path = root/'lib/deda_qa32_active_account_scope.dart'
    scope = path.read_text()
    scope = once(scope,
        "import 'deda_stability_read_scope.dart';",
        "import 'deda_stability_read_scope.dart';\n"
        "import 'deda_verified_active_id_store.dart';",
        'owner scope store import')
    scope = once(scope,
        "  bool _authAttachQueued = false;",
        """  bool _authAttachQueued = false;

  // All owner display surfaces share ONE confirmed account-scoped value.
  // Their rendering does not each wait for new Firebase round trips.
  void _onSharedDisplayChanged() {
    if (mounted) setState(() {});
  }""",
        'owner shared listener')
    scope = once(scope,
        "    DedaStage71ActiveIdRefresh.notifier.addListener(_refresh);",
        """    DedaStage71ActiveIdRefresh.notifier.addListener(_refresh);
    DedaVerifiedActiveIdStore.revision.addListener(_onSharedDisplayChanged);""",
        'owner shared listener registration')
    scope = once(scope,
        """    if (dedaStabilityIdentityPilot && _paused) return;
    if (uid == null || !widget._source.enabled ||""",
        """    if (uid != null && widget._source.enabled) {
      // Warm UI-only last confirmed value without blocking the server read.
      unawaited(DedaVerifiedActiveIdStore.restore(uid, original));
    }
    if (dedaStabilityIdentityPilot && _paused) return;
    if (uid == null || !widget._source.enabled ||""",
        'warm verified account-scoped display')
    scope = once(scope,
        "      setState(() => _proof = next);",
        """      DedaVerifiedActiveIdStore.confirmed(
        uid: uid, originalId: original, displayId: next.displayId,
        fixedColor: next.fixedColor,
      );
      setState(() => _proof = next);""",
        'broadcast only server-verified owner read')
    scope = once(scope,
        """    DedaStage71ActiveIdRefresh.notifier.removeListener(_refresh);""",
        """    DedaStage71ActiveIdRefresh.notifier.removeListener(_refresh);
    DedaVerifiedActiveIdStore.revision.removeListener(_onSharedDisplayChanged);""",
        'remove shared listener')
    scope = once(scope,
        """    final proof = currentUid != null &&
            _proof?.verifiedFor(currentUid, widget.originalId) == true
        ? _proof
        : null;
    return widget.builder(context, proof);""",
        """    // UI cache is scoped to the SDK current UID and canonical route;
    // never feed it to backend authorization. The server read reconciles it.
    final cached = currentUid == null ? null :
        DedaVerifiedActiveIdStore.read(currentUid, widget.originalId);
    final cachedProof = cached == null ? null : DedaQa32ActiveAccountIdentity(
      uid: cached.uid, originalId: cached.originalId,
      displayId: cached.displayId, fixedColor: cached.fixedColor,
    );
    final proof = cachedProof?.verifiedFor(
            currentUid ?? '', widget.originalId) == true
        ? cachedProof
        : currentUid != null &&
            _proof?.verifiedFor(currentUid, widget.originalId) == true
            ? _proof
            : null;
    return widget.builder(context, proof);""",
        'all owner labels use shared account presentation')
    path.write_text(scope)

    path = root/'lib/deda_stage71_free_owned_use_profile.dart'
    social = path.read_text()
    social = once(social,
        "import 'deda_stage71_free_manager_200_service.dart';",
        "import 'deda_stage71_free_manager_200_service.dart';\n"
        "import 'deda_verified_active_id_store.dart';\n"
        "import 'deda_qa32_active_account_scope.dart';",
        'stage71 import shared proof and scope')
    # Scope all changes to the actual service Use method. Other Stage71
    # helpers legitimately compare the same identifiers.
    start = social.index('static Future<void> use(String originalId, String identifier) async {')
    stop = social.index("\n}\n\n/// User's Edit Profile:", start)
    use_body = social[start:stop]
    use_body = once(use_body,
        "    if (identifier != originalId) {",
        "    String? selectedColor;\n    if (identifier != originalId) {",
        'capture server-verified Use selection color')
    use_body = once(use_body,
        "DedaStage71OwnedIdentifier.read(owner.id, owner.data() ?? {}, originalId);",
        "final selectedGrant = DedaStage71OwnedIdentifier.read(\n"
        "          owner.id, owner.data() ?? {}, originalId);\n"
        "      selectedColor = selectedGrant.baseColor;",
        'capture original grant color')
    use_body = once(use_body,
        "    DedaStage71ActiveIdRefresh.changed();",
        """    // Existing server readback and public projection succeeded.
    DedaVerifiedActiveIdStore.confirmed(
      uid: uid, originalId: originalId, displayId: identifier,
      fixedColor: selectedColor,
    );
    DedaStage71ActiveIdRefresh.changed();""",
        'broadcast owner ID only after confirmed Use')
    social = social[:start] + use_body + social[stop:]
    social = once(social,
        "if (currentRows != null)",
        "if (currentRows != null \n                && currentActive == widget.originalId)",
        'old ID is never offered for display while premium active')
    before = "class DedaStage71ActiveProfileFoil extends StatefulWidget {"
    if social.count(before) != 1:
        raise ValueError('profile-foil anchor changed')
    head, tail = social.split(before, 1)
    if not tail.rstrip().endswith('}'):
        raise ValueError('profile foil is not final class')
    social = head + """class DedaStage71ActiveProfileFoil extends StatelessWidget {
  final String originalId;
  final Widget fallback;
  const DedaStage71ActiveProfileFoil({
    super.key, required this.originalId, required this.fallback,
  });

  @override
  Widget build(BuildContext context) => DedaQa32ActiveAccountScope(
    originalId: originalId,
    builder: (context, proof) {
      // The original hero may only be shown after server verification that
      // the original is active. Every other surface uses the same source.
      if (proof == null) {
        return const SizedBox(
          height: 50,
          child: Center(child: Text('جارٍ التحقق من المعرّف…')),
        );
      }
      if (!proof.isPremium) return fallback;
      final fixedColor = proof.fixedColor!;
      final color = DedaPremiumIdCardColor.values.firstWhere(
        (item) => item.name == fixedColor,
      );
      return GestureDetector(
        key: const Key('deda_stage71_active_granted_id_hero'),
        onTap: () => Clipboard.setData(ClipboardData(text: proof.displayId)),
        child: DedaPremiumIdCard(
          identifier: proof.displayId, color: color, height: 50,
        ),
      );
    },
  );
}
"""
    path.write_text(social)
    return {'sharedAccountDisplay': True, 'originalRoutingUntouched': True,
            'ownerHeroUnified': True, 'publicProjectionUnchanged': True}
