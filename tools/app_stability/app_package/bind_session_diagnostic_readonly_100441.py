#!/usr/bin/env python3
"""Add manual READ-ONLY Firebase session check to disposable fully assembled DEDA.

No auth state changes, no Firebase writes and no changes to 100440 reference.
Run after stage3/friends/missing-owner binder in a temporary full project.
"""
from __future__ import annotations
import argparse
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MODULE = "deda_session_diagnostic_readonly_100441.dart"

def once(text: str, old: str, new: str, title: str) -> str:
    n = text.count(old)
    if n != 1:
        raise ValueError("BLOCK_DIAG_STAGE_ANCHOR:" + title + ":" + str(n))
    return text.replace(old, new, 1)

def bind(project: Path) -> None:
    project = project.resolve()
    if project == ROOT or ROOT in project.parents or project in ROOT.parents:
        raise ValueError("BLOCK_DIAG_NEVER_EDIT_REFERENCE")
    main_path = project / "lib/main.dart"
    target = project / "lib" / MODULE
    if not main_path.exists() or target.exists():
        raise ValueError("BLOCK_DIAG_ALREADY_BOUND_OR_MISSING_SOURCE")
    content = main_path.read_text()
    if "DedaSessionDiagnosticReadOnlyTile" in content or \
            "DEDA_100441_FRIENDS_RETRY_FIX" not in content or \
            "DedaSessionRescueStage3Bridge" not in content:
        raise ValueError("BLOCK_DIAG_REQUIRES_COMPLETE_STAGE3_FRIENDS")

    content = once(
        content,
        "import 'deda_session_missing_owner_entry_100441.dart';",
        "import 'deda_session_missing_owner_entry_100441.dart';\n"
        "import 'deda_session_diagnostic_readonly_100441.dart';",
        "settings diagnostic import",
    )
    anchor = """                  _sectionTitle(
                      dedaText('الصوت والملاحة', 'Voice & navigation')),"""
    replacement = """                  // Manual diagnostic: does not sign in/out, link Google,
                  // create any Firebase UID, change gifts or write Firestore.
                  _sectionTitle(dedaText(
                    'تشخيص الجلسة', 'Session diagnostics')),
                  Card(child: DedaSessionDiagnosticReadOnlyTile(
                    phone: DedaPreferences.accountPhone.trim().isNotEmpty
                        ? DedaPreferences.accountPhone
                        : DedaPreferences.phone,
                  )),
                  _sectionTitle(
                      dedaText('الصوت والملاحة', 'Voice & navigation')),"""
    content = once(content, anchor, replacement,
                   "Settings diagnostic card before navigation audio")
    if content.count("DedaSessionDiagnosticReadOnlyTile(") != 1:
        raise ValueError("BLOCK_DIAG_NONUNIQUE_TILE")
    diagnostic = ROOT / "lib" / MODULE
    module_content = diagnostic.read_text()
    banned = ("signInAnonymously(", "signOut(", ".set(", ".update(",
              ".delete(", "linkWithCredential(", "createUserWithEmailAndPassword(")
    for item in banned:
        if item in module_content:
            raise ValueError("BLOCK_DIAG_WRITE_OR_AUTH:" + item)
    # Validate entire original page before writing to temporary workspace.
    main_path.write_text(content)
    shutil.copy2(diagnostic, target)
    print("PASS_READONLY_SESSION_DIAG_IN_SETTINGS_NO_AUTH_OR_FIRESTORE_WRITE")

if __name__ == "__main__":
    arg = argparse.ArgumentParser()
    arg.add_argument("project", type=Path)
    bind(arg.parse_args().project)
