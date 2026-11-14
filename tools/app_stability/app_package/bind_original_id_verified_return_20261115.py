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
    if ("DedaStage71OwnedIdentifierService.acceptedOwnedForMyStore(original)"
            not in old_panel or "if (currentRows != null)" not in old_panel
            or "Future<void> _load() async" not in old_panel):
        raise ValueError("Not the approved original owner selection widget")
    if ("verifyOriginalOwner(original)" not in new_panel
            or "if (originalVerified)" not in new_panel
            or "_premiumLoadFailed" not in new_panel):
        raise ValueError("Independent original owner gate missing from source")
    if "verifyOriginalOwner(String originalId)" in before:
        raise ValueError("Original return already patched; refuse duplicate")
    if ("DedaQa32ManagerOriginalOwnerProof.authentic(" not in before
            or "static Future<String> _requireOriginal(" not in before):
        raise ValueError("Exact UID/route/session original proof is missing")
    # The genuine premium Use implementation is kept byte-for-byte,
    # including public projection, verified readback and same-UID checks.
    use_before = block(before, "  static Future<void> use(", "/// User's Edit Profile:")
    add = (
        "  /// Independently verify the same server owner for original return.\n"
        "  /// This does NOT authorize a foreign or anonymous Firebase UID.\n"
        "  static Future<String> verifyOriginalOwner(String originalId) =>\n"
        "      _requireOriginal(originalId);\n\n"
    )
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
