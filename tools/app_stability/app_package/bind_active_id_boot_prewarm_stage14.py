"""DEDA 100389: warm already VERIFIED active-ID UI cache BEFORE first paint.

Applies only to a temporary, protected signed-100388 original candidate workspace.
Leaves existing Stage71 live owner verification and use/ownership rules intact.
Can show the last server-confirmed same-UID ID immediately on return to profile,
then normal owner verification reconciles any change. A new install / other
phone with no verified local cache must still load from server: never invent
or derive a premium ID from phone, balance, local task points or unsigned hints.
"""
import argparse
import hashlib
import json
from pathlib import Path

REPO=Path(__file__).resolve().parents[3]
PACKAGE="com.diraq.ludo.d_iraq_ludo"


def once(s,before,after,label):
    if s.count(before)!=1:
        raise ValueError("stage14 preload source mismatch: "+label)
    return s.replace(before,after,1)


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def bind(project):
    project=Path(project).resolve()
    if project==REPO or project in REPO.parents or REPO in project.parents:
        raise ValueError("cannot mutate original DEDA repository")
    manifest=project/"internal-build-inputs.json"
    main_file=project/"lib/main.dart"
    store_file=project/"lib/deda_verified_active_id_store.dart"
    if not manifest.is_file() or not store_file.is_file():
        raise ValueError("stage13 isolated original 100388 build inputs required")
    data=json.loads(manifest.read_text())
    prior=data.get("sourceHashes") or {}
    if (data.get("versionCode")!=100388 or
        data.get("variant")!="candidate" or
        data.get("package")!=PACKAGE or
        data.get("completeOwnerDelivery") is not False or
        data.get("productionExecutionPerformed") is not False or
        data.get("financialRestoreEnabled") is not False or
        not data.get("weeklyStage13",{}).get("sameOfficialPackage") or
        data.get("weeklyStage13",{}).get("realRankingsAvailable") is not False or
        any(not (project/p).is_file() or sha(project/p)!=h
            for p,h in prior.items())):
        raise ValueError("original signed 100388 candidate drifted")

    main=main_file.read_text()
    store=store_file.read_text()
    if "import 'package:firebase_auth/firebase_auth.dart';" not in main:
        main=once(
            main,"import 'package:firebase_core/firebase_core.dart';",
            "import 'package:firebase_core/firebase_core.dart';\n"
            "import 'package:firebase_auth/firebase_auth.dart';",
            "firebase_auth import")
    if "import 'deda_verified_active_id_store.dart';" not in main:
        main=once(main,"import 'deda_backend.dart';",
            "import 'deda_backend.dart';\n"
            "import 'deda_verified_active_id_store.dart';",
            "prewarm store import")
    main=once(main,
        "  await DedaPreferences.load();",
        """  await DedaPreferences.load();
  // Already server-confirmed display IDs are rehydrated BEFORE any profile
  // widget is mounted. Session UID is obtained from current Firebase Auth;
  // this is a presentation cache only, NEVER premium ID authorization.
  try {
    if (Firebase.apps.isNotEmpty) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) {
        await DedaVerifiedActiveIdStore.preloadForUid(uid);
      }
    }
  } catch (_) {
    // Offline / first login / no saved owner display: Stage71 server
    // verification still handles the profile normally; no guessed ID.
  }
""",
        "boot after loaded preferences before Flutter first frame")
    store=once(store,
        "  static Future<void> restore(String uid, String originalId) {",
        """  /// Cold-start hydration for one authenticated Firebase UID only.
  /// Existing disk entries were written by Stage71 after authenticated
  /// readback. NEVER mix UIDs, and do not turn cache into purchase authority.
  /// Reusing last-confirmed display is optimistic UI; Stage71 must reconcile
  /// a new active ID changed remotely. Fresh phones with no local cache wait
  /// for real verification and MUST NOT show an invented identifier.
  static Future<void> preloadForUid(String uid) async {
    if (uid.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      const prefix = 'deda_verified_active_display_v1_';
      for (final name in prefs.getKeys()) {
        if (!name.startsWith(prefix)) continue;
        final raw = prefs.getString(name);
        if (raw == null) continue;
        DedaVerifiedActiveId? saved;
        try {
          saved = DedaVerifiedActiveId.fromJson(jsonDecode(raw));
        } catch (_) {
          continue;
        }
        if (saved == null || !saved.wellFormed ||
            saved.uid != uid ||
            name != _prefsKey(saved.uid, saved.originalId)) continue;
        final key = _key(uid, saved.originalId);
        if (_memory.containsKey(key)) continue; // newer server read wins
        _memory[key] = saved;
        revision.value += 1;
      }
    } catch (_) {
      // File absence or damaged saved UI must never interrupt DEDA start.
    }
  }

  static Future<void> restore(String uid, String originalId) {""",
        "restore known verified ID before first frame")
    main_file.write_text(main)
    store_file.write_text(store)
    modified={p for p,h in prior.items() if sha(project/p)!=h}
    if modified!={"lib/main.dart","lib/deda_verified_active_id_store.dart"}:
        raise ValueError("unsafe source changes: "+repr(modified))
    data["sourceHashes"]={
        str(p.relative_to(project)):sha(p)
        for p in sorted((project/"lib").rglob("*.dart"))
    }
    data["sourceHashes"].update({
      "pubspec.yaml":sha(project/"pubspec.yaml"),
      "pubspec.lock":sha(project/"pubspec.lock"),
    })
    data["versionCode"]=100389
    data["activeIdStage14"]={
        "preloadedBeforeFirstFrame":True,
        "sessionScopedUidOnly":True,
        "reusePreviouslyServerConfirmedDisplayOnly":True,
        "serverStillRevalidates":True,
        "firstUseFreshInstallMightWait":True,
        "existingUserWalletModified":False,
        "remotePremiumIdChangedMayRequireReconciliation":True,
        "original100388Protected":True,
        "privateQaOnly":True,
    }
    data["purpose"]="ORIGINAL 100389 PRIVATE ID DISPLAY COLD START QA NO PLAY"
    manifest.write_text(json.dumps(data,indent=2,ensure_ascii=False)+"\n")
    return data["activeIdStage14"]


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project",type=Path)
    args=parser.parse_args()
    print(json.dumps(bind(args.project),ensure_ascii=False))
