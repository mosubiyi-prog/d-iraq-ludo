#!/usr/bin/env python3
"""100454: repair the existing-owner Firebase session handoff in disposable QA builds.

This patches ONLY the original full-application assembly after all prior binders.
It does NOT touch the protected source APK, Google Play, Firebase, A/B/C accounts,
or use the incomplete replacement-phone financial/recovery guardian.

The flow requires explicit phone+PIN -> EXISTING password FirebaseAuth UID ->
live server directory/user/session/original-ID proof -> existing UID session
readback -> verified local login. No anonymous UID, no new account, no writes
to Firestore, no Google link, no credential creation, no balance change.
"""
from __future__ import annotations

import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MAIN = "lib/main.dart"
ENTRY = "  Widget _buildExistingAccountForm("
NEXT = "\n  void _openExistingAccount() {"

def exactly_one(text: str, old: str, new: str, name: str) -> str:
    count = text.count(old)
    if count != 1:
        raise ValueError(f"SAFE_STOP_100454_{name}_{count}")
    return text.replace(old, new, 1)

def bind(project: Path) -> None:
    project = project.resolve()
    root = ROOT.resolve()
    if project == root or root in project.parents or project in root.parents:
        raise ValueError("SAFE_STOP_100454_PROTECTED_SOURCE")
    file = project / MAIN
    if not file.is_file() or not (project / "internal-build-inputs.json").is_file():
        raise ValueError("SAFE_STOP_100454_MISSING_FULL_ASSEMBLY")
    source = file.read_text(encoding="utf-8")
    for expected in (
        "DEDA_100441_FRIENDS_RETRY_FIX",
        "DedaCurrentUidProbe100453.open(context)",
        "DedaUnifiedRoomRuntimeReadOnly.preflightOnHome()",
        "DedaMissingOwnerEntryPolicy.canOffer",
        "DedaLinkedOwnerGuardianAssembly.prepare();",
    ):
        if expected not in source:
            raise ValueError("SAFE_STOP_100454_MISSING_PRIOR_GUARD_" + expected)
    if source.count(ENTRY) != 1 or source.count(NEXT) != 1:
        raise ValueError("SAFE_STOP_100454_LOGIN_FORM_NOT_UNIQUE")
    start = source.index(ENTRY)
    end = source.index(NEXT, start)
    section = source[start:end]
    begin_marker = '          // The checkbox on "لدي حساب" supplies independent explicit'
    end_marker = "          final profile ="
    if section.count(begin_marker) != 1 or section.count(end_marker) != 1:
        raise ValueError("SAFE_STOP_100454_ORIGINAL_RECOVERY_CALLBACK_CHANGED")
    before = section.index(begin_marker)
    after = section.index(end_marker, before)
    previous = section[before:after]
    for token in (
        "DedaStep2RecoveryIntentStore", "DedaLinkedOwnerGuardianAssembly.prepare()",
        "loginAndPrepare(", "login.fullAccountRestored", "recoveryIntentId:",
    ):
        if token not in previous:
            raise ValueError("SAFE_STOP_100454_MISSING_UNSAFE_RECOVERY_PATH_" + token)
    safe = """          // 100454: Original-account Firebase SESSION ONLY, not recovery.
          // No new anonymous UID, no restore journal, no server mutation.
          // All checks are on the original FirebaseAuth principal and server.
          final port = DedaLinkedOwnerFirebasePortCandidate(
            auth: FirebaseAuth.instance,
            db: FirebaseFirestore.instance,
            functions: FirebaseFunctions.instance,
          );
          final originalUid = await DedaLoginHandoff(port).login(
            phone: phone,
            pin: pin,
            explicitUserAction: true,
            isCurrentIntent: () => mounted && pageContext.mounted,
          );
          final proven = port.current();
          final originalId = proven.originalId;
          if (originalId == null || proven.uid != originalUid ||
              !proven.verifiedOriginalOwnerProvider) {
            throw StateError('owner-100454-original-uid-not-proven');
          }
"""
    section = section[:before] + safe + section[after:]
    section = exactly_one(section, "originalId: login.originalId!",
                          "originalId: originalId", "original_id")
    section = exactly_one(section, "expectedUid: login.originalUid",
                          "expectedUid: originalUid", "profile_uid")
    section = exactly_one(section, "verifiedOriginalUid: login.originalUid",
                          "verifiedOriginalUid: originalUid", "saved_uid")
    section = exactly_one(section,
                          "      initialPhone: initialPhone,\n",
                          "      initialPhone: initialPhone,\n      sessionOnly: true,\n",
                          "session_only_ui")
    source = source[:start] + section + source[end:]
    source = exactly_one(source,
        "import 'deda_step2_existing_account_signin_page.dart';",
        "import 'deda_step2_existing_account_signin_page.dart';\n"
        "import 'deda_step2_linked_owner_firebase_port.dart';\n"
        "import 'deda_step2_linked_owner_flutter_handoff.dart';\n"
        "import 'package:cloud_functions/cloud_functions.dart';",
        "imports")
    # Recovery code stays in repository but NEVER enters the 100454 login path.
    repaired = source[source.index(ENTRY):source.index(NEXT, source.index(ENTRY))]
    for forbidden in ("loginAndPrepare(", "DedaStep2RecoveryIntentStore",
                      "signInAnonymously(", "createAccount(", "linkWithCredential(",
                      "DedaLinkedOwnerGuardianAssembly.prepare();"):
        if forbidden in repaired:
            raise ValueError("SAFE_STOP_100454_RECOVERY_OR_NEW_UID_" + forbidden)
    for required in ("DedaLoginHandoff(port).login(",
                     "verifiedCanonicalProfile: true",
                     "expectedUid: originalUid",
                     "sessionOnly: true"):
        if required not in repaired:
            raise ValueError("SAFE_STOP_100454_MISSING_GUARD_" + required)
    file.write_text(source, encoding="utf-8")
    print("PASS_100454_EXISTING_UID_FIREBASE_LOGIN_ONLY_NO_RECOVERY_NO_NEW_UID")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("project", type=Path)
    bind(parser.parse_args().project)
