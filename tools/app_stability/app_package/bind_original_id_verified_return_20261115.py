"""Isolated DEDA original-ID return integration on an already assembled app.

Keep the verified 100410/100414 active-ID service, public projection, UID,
gifts, wallets, login and all other widgets unchanged. Only replace the
independent server-proven original-ID picker and add its read-only proof entry.
NEVER run on the repository source or Firebase production.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
NAME = "lib/deda_stage71_free_owned_use_profile.dart"
PANEL_START = "class _DedaStage71OwnedIdsPanelState"
PANEL_END = "/// On the user's personal hero"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def block(text: str, begin: str, finish: str) -> str:
    if text.count(begin) != 1 or text.count(finish) != 1:
        raise ValueError("Original picker markers are not unique")
    return text[text.index(begin):text.index(finish)]


def bind(project: Path) -> None:
    project = project.resolve()
    if project == ROOT or ROOT in project.parents:
        raise ValueError("Refuse to alter the protected repository")
    meta_path = project / "internal-build-inputs.json"
    meta = json.loads(meta_path.read_text())
    if meta.get("package") != "com.diraq.ludo.d_iraq_ludo":
        raise ValueError("Unexpected Android package")
    app = project / NAME
    if not app.is_file() or meta["sourceHashes"].get(NAME) != sha(app):
        raise ValueError("Assembled source mismatch; do not patch")
    before = app.read_text()
    wanted = (ROOT / NAME).read_text()
    old_panel = block(before, PANEL_START, PANEL_END)
    new_panel = block(wanted, PANEL_START, PANEL_END)
    # The full-app assembly comes from the earlier immutable baseline, so
    # its original panel may predate the newer library's premium-list helpers.
    # Preserve the actual service and its strict UID guards; replace the panel
    # only if the exact prior owner-picker structure is present.
    if ("Future<void> _load() async" not in old_panel or
            "Future<void> _use(String id) async" not in old_panel or
            "DedaStage71OwnedIdentifierService" not in old_panel or
            "widget.originalId" not in old_panel):
        raise ValueError("Original owner selection panel changed; safe stop")
    if ("verifyOriginalOwner(original)" not in new_panel
            or "if (originalVerified)" not in new_panel
            or "_premiumLoadFailed" not in new_panel):
        raise ValueError("Independent original owner gate missing from source")
    # Full 100410 app Use has TWO parameters and itself validates + reads back;
    # the staging-source-only panel has a newer optional callback. Do not
    # rewrite or weaken the real Use service to satisfy a UI callback.
    use_with_callback = """      await DedaStage71OwnedIdentifierService.use(
        original, id,
        onServerConfirmed: () {
          // Never optimistic: the canonical ID has been written and read
          // back on the same verified UID before this callback runs.
          if (!mounted || generation != _generation ||
              widget.originalId != original || _currentUid() != uid) return;
          setState(() => _active = id);
        },
      );"""
    if new_panel.count(use_with_callback) != 1:
        raise ValueError("Source panel server-confirmed callback unexpectedly changed")
    new_panel = new_panel.replace(
        use_with_callback,
        """      final ownerUid = await
          DedaStage71OwnedIdentifierService.verifyOriginalOwner(original);
      if (ownerUid != uid || !mounted || generation != _generation ||
          widget.originalId != original || _currentUid() != uid) return;
      await DedaStage71OwnedIdentifierService.use(original, id);""", 1)
    # A historical assembled version lacking the VERIFIED/RECEIVED premium
    # helper must not display raw unaccepted gift records as owned IDs.
    if "static Future<List<DedaStage71OwnedIdentifier>> acceptedOwnedForMyStore(" not in before:
        premium_fetch = """        final rows = await
            DedaStage71OwnedIdentifierService.acceptedOwnedForMyStore(original);"""
        if new_panel.count(premium_fetch) != 1:
            raise ValueError("Premium helper adapter anchor changed")
        new_panel = new_panel.replace(
            premium_fetch,
            "        throw StateError('premium-receipt-proof-not-in-this-baseline');", 1)
    if "verifyOriginalOwner(String originalId)" in before:
        raise ValueError("Original return already patched; refuse duplicate")
    if "static Future<String> _requireOriginal(" not in before:
        raise ValueError("Assembled original owner route verifier is absent")
    # Protected full-app snapshot predates modern owner proof. Add the exact
    # server proof solely for original reactivation, preserving existing Use.
    # The genuine premium Use implementation is kept byte-for-byte,
    # including public projection, verified readback and same-UID checks.
    use_before = block(before, "  static Future<void> use(", "/// User's Edit Profile:")
    add = """  /// Original-only, server-authoritative proof, independent of gift loading.
  /// A split, anonymous or foreign Firebase UID never receives this action.
  static Future<String> verifyOriginalOwner(String originalId) async {
    final uid = await _requireOriginal(originalId);
    if (Firebase.apps.isEmpty || FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('original-owner-session-rotated');
    }
    final db = FirebaseFirestore.instance;
    final records = await Future.wait([
      db.collection('users').doc(uid)
          .get(const GetOptions(source: Source.server)),
      db.collection('deda_sessions').doc(uid)
          .get(const GetOptions(source: Source.server)),
      db.collection('deda_share_ids').doc(originalId)
          .get(const GetOptions(source: Source.server)),
    ]);
    if (FirebaseAuth.instance.currentUser?.uid != uid ||
        !DedaQa32ManagerOriginalOwnerProof.authentic(
          expectedOriginal: originalId,
          authUid: uid,
          account: records[0].data() ?? <String, dynamic>{},
          session: records[1].data() ?? <String, dynamic>{},
          route: records[2].data() ?? <String, dynamic>{},
        )) {
      throw StateError('original-owner-server-proof-not-matched');
    }
    return uid;
  }

"""
    if "import 'deda_qa32_manager_original_owner_proof.dart';" not in before:
        legacy_import = "import 'deda_qa32_spark_public_identifier_directory.dart';"
        if before.count(legacy_import) != 1:
            raise ValueError("Cannot attach exact original owner proof import")
        before = before.replace(legacy_import, """import 'deda_qa32_spark_public_identifier_directory.dart';
import 'deda_qa32_manager_original_owner_proof.dart';""", 1)
    proof_name = "lib/deda_qa32_manager_original_owner_proof.dart"
    reviewed_proof = ROOT / proof_name
    project_proof = project / proof_name
    if project_proof.is_file():
        if project_proof.read_bytes() != reviewed_proof.read_bytes():
            raise ValueError("Existing original owner proof differs: STOP")
    else:
        project_proof.write_bytes(reviewed_proof.read_bytes())
    meta["sourceHashes"][proof_name] = sha(project_proof)
    marker = "  static Future<List<DedaStage71OwnedIdentifier>> owned(String originalId) async {"
    if before.count(marker) != 1:
        raise ValueError("Owner service insertion anchor changed")
    after = before.replace(marker, add + marker, 1)
    after = after.replace(old_panel, new_panel, 1)
    if block(after, "  static Future<void> use(", "/// User's Edit Profile:") != use_before:
        raise ValueError("Refuse any change to active ID server Use")
    if after.count("verifyOriginalOwner(String originalId)") != 1:
        raise ValueError("Duplicate original verifier")
    app.write_text(after)
    meta["sourceHashes"][NAME] = sha(app)
    meta["originalIdReturnOwnerVerified20261115"] = {
        "independentOriginalProof": True,
        "premiumInventoryCannotBlockOriginal": True,
        "exactUidSessionRouteRequired": True,
        "originalSelectionServerReadbackUnchanged": True,
        "activeAliasPublicSyncUnchanged": True,
        "noFirebaseOrPlayMutation": True,
        "phoneAcceptancePending": True,
    }
    meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n")
    print("PASS: assembled original ID return independently owner-verified; Use preserved")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("project", type=Path)
    bind(p.parse_args().project)
