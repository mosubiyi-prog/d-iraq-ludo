"""Stage16: repair the actual measured-startup branch omitted in 100389.

The signed private original 100389 already preloads verified same-UID active ID
only in the DISABLED unmeasured startup. Its regular measured startup uses a
loadPreferences callback that never calls preloadForUid. Apply to an isolated
original-package prepared workspace AFTER Stage13 and Stage14 binding ONLY.
Do not alter live auth/ownership, ID routing, financial data or Play release.
"""
from pathlib import Path
import argparse
import hashlib
import json

REPO = Path(__file__).resolve().parents[3]

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def bind(project):
    project=Path(project).resolve()
    if project==REPO or project in REPO.parents or REPO in project.parents:
        raise ValueError("Stage16 must NOT modify original repo")
    manifest=project/"internal-build-inputs.json"
    main=project/"lib/main.dart"
    meta=json.loads(manifest.read_text())
    if (meta.get("versionCode") != 100389 or
        meta.get("package") != "com.diraq.ludo.d_iraq_ludo" or
        meta.get("completeOwnerDelivery") is not False or
        meta.get("financialRestoreEnabled") is not False or
        meta.get("productionExecutionPerformed") is not False or
        meta.get("activeIdStage14",{}).get("preloadedBeforeFirstFrame") is not True or
        meta.get("flags",{}).get("DEDA_STABILITY_STARTUP_METRICS") is not True or
        any(not (project/p).is_file() or sha(project/p)!=h
            for p,h in meta["sourceHashes"].items())):
        raise ValueError("Expected protected 100389 measured-startup workspace")
    text=main.read_text()
    anchor="    loadPreferences: DedaPreferences.load,"
    if text.count(anchor)!=1 or text.count("await DedaVerifiedActiveIdStore.preloadForUid(uid);")!=1:
        raise ValueError("Expected one DISABLED startup preload and one measured callback")
    after="""    // This callback is the ACTUAL build's active STARTUP_METRICS=true path.
    // Preload last SERVER-CONFIRMED identity for the current authenticated
    // UID, before launching Flutter profile. No unverified ID is invented.
    loadPreferences: () async {
      await DedaPreferences.load();
      try {
        if (Firebase.apps.isNotEmpty) {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (uid != null && uid.isNotEmpty) {
            await DedaVerifiedActiveIdStore.preloadForUid(uid);
          }
        }
      } catch (_) {
        // Missing local UI cache / offline verification never blocks launch.
      }
    },"""
    text=text.replace(anchor,after,1)
    if text.count("await DedaVerifiedActiveIdStore.preloadForUid(uid);")!=2:
        raise ValueError("Both original and measured startup must preload")
    main.write_text(text)
    changed={p for p,h in meta["sourceHashes"].items()
             if sha(project/p)!=h}
    if changed!={"lib/main.dart"}:
        raise ValueError("Only prepared main.dart may change: "+str(changed))
    meta["sourceHashes"]["lib/main.dart"]=sha(main)
    meta["versionCode"]=100391
    meta["activeIdStage16"]={
        "measuredStartupActive":True,
        "measuredStartupBeforeRunApp":True,
        "oneUidOnly":True,
        "localPreviouslyServerConfirmedIdOnly":True,
        "serverAuthorityUnchanged":True,
        "freshPhoneMayNeedServerVerification":True,
        "original100388And100389Protected":True,
        "realBalanceXpOrGrantWrites":False,
        "privateQaOnly":True,
    }
    meta["purpose"]="DEDA 100391 PRIVATE PREWARM MEASURED STARTUP QA; NO PLAY"
    manifest.write_text(json.dumps(meta,ensure_ascii=False,indent=2)+"\n")
    return meta["activeIdStage16"]

if __name__=="__main__":
    cli=argparse.ArgumentParser(description=__doc__)
    cli.add_argument("project",type=Path)
    print(json.dumps(bind(cli.parse_args().project),ensure_ascii=False))
