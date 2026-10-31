"""DEDA 100408 / point 1: remove blocking public-alias repair from verified UI ID read.

Run after the accepted 100407 SHA-verified isolated assembly. The original
Stage71 active() retains grant/owner/receipt AND public-alias repair behavior.
The display-only activeFastDisplay() retains ALL authorization/receipt checks
but does not await a separate public-projection repair, whose delay caused
the owner-facing profile and leaderboard to show the old pending state.
Existing 100407 request coalescer/cache/revision + UID fencing are preserved.
"""
from pathlib import Path
import hashlib,json,argparse
ROOT=Path(__file__).resolve().parents[3]
SCOPE="lib/deda_qa32_active_account_scope.dart"
OWNED="lib/deda_stage71_free_owned_use_profile.dart"
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def bind(project):
    project=Path(project).resolve()
    if project==ROOT or project in ROOT.parents or ROOT in project.parents:
        raise ValueError("accepted original source is protected")
    meta_path=project/"internal-build-inputs.json"
    m=json.loads(meta_path.read_text())
    if (m.get("versionCode")!=100407 or
        m.get("package")!="com.diraq.ludo.d_iraq_ludo" or
        m.get("financialRestoreEnabled") is not False or
        m.get("weekly100407OwnerCorrections",{}).get(
            "profileAlreadyUsesVerifiedOwnerStore") is not True):
        raise ValueError("verified 100407 assembled original required")
    for name,h in m["sourceHashes"].items():
        if not (project/name).is_file() or sha(project/name)!=h:
            raise ValueError("source SHA changed "+name)
    owned_file=project/OWNED
    source=owned_file.read_text()
    start=source.index("  static Future<String> active(String originalId) async {")
    end=source.index("  static Future<void> use(",start)
    old=source[start:end]
    if (old.count("_requireOriginal(originalId)")!=1 or
        old.count("DedaStage74IdGiftService.isReceived(")!=1 or
        old.count("DedaStage71OwnedIdentifier.read(")!=1):
        raise ValueError("do not weaken original owner/receipt proof")
    if old.count("DedaOwner18PublicAliasRepair.ensure(")!=1:
        raise ValueError("expected exactly one slow optional alias repair")
    # Clone exact verified owner read, retaining ALL its stage71 checks.
    fast=old.replace("static Future<String> active(",
                     "static Future<String> activeFastDisplay(",1)
    slow_start=fast.index("    // Restore a missing public projection")
    slow_end=fast.index("    return current;",slow_start)
    if "DedaOwner18PublicAliasRepair.ensure(" not in fast[slow_start:slow_end]:
        raise ValueError("cannot isolate optional repair from verified read")
    fast=fast[:slow_start]+fast[slow_end:]
    if ("_requireOriginal(originalId)" not in fast or
        "DedaStage74IdGiftService.isReceived(" not in fast or
        "account-switched-after-active-gift-receipt" not in fast or
        "DedaOwner18PublicAliasRepair.ensure(" in fast):
        raise ValueError("fast UI read failed original-grant and receipt preservation")
    owned_file.write_text(source[:start]+fast+"\n"+source[start:])
    # Already bundled by 100407: single UID-scoped in-flight coalescer,
    # ValueNotifier and server-verified cache. Repoint its readFresh only.
    scope_file=project/SCOPE
    scope=scope_file.read_text()
    needle="DedaStage71OwnedIdentifierService.active(original)"
    if scope.count(needle)!=1 or (
        "_inFlight[key]" not in scope or
        "DedaVerifiedActiveIdStore.confirmed(" not in scope or
        "DedaVerifiedActiveIdStore.restore(uid, original)" not in scope):
        raise ValueError("100407 shared current-UID cached owner reader changed")
    scope=scope.replace(needle,
        "DedaStage71OwnedIdentifierService.activeFastDisplay(original)",1)
    scope_file.write_text(scope)
    for name in (SCOPE,OWNED):m["sourceHashes"][name]=sha(project/name)
    m["versionCode"]=100408
    m["weekly100408Point1"]={
        "fastVerifiedUiReadPreservesOriginalGrantReceipt":True,
        "optionalPublicRepairNoLongerBlocksHeader":True,
        "originalActiveWithPublicRepairUnchanged":True,
        "alreadyServerConfirmedSameUidStoreReused":True,
        "inFlightSameOwnerReadsCoalesced":True,
        "freshPhoneRequiresServerProof":True,
        "latencyTargetSecondsPendingPhoneMeasurement":True,
        "originalXpWalletOrGrantsChanged":False,
    }
    meta_path.write_text(json.dumps(m,ensure_ascii=False,indent=2)+"\n")
    return m["weekly100408Point1"]

if __name__=="__main__":
    cli=argparse.ArgumentParser()
    cli.add_argument("workspace",type=Path)
    print(json.dumps(bind(cli.parse_args().workspace),ensure_ascii=False))
