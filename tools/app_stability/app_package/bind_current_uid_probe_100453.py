#!/usr/bin/env python3
"""Bind a QA-only, one-tap current Firebase UID fingerprint to FULL DEDA.

Does not reintroduce removed diagnostics/Google cards. The generated app
contains one settings AppBar action only when a temporary build flag is true.
Never change the source repository or protected reference in-place.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[3]
PROBE = "deda_current_uid_probe_100453.dart"
FINGERPRINT = "deda_session_diagnostic_readonly_100441.dart"


def once(text: str, previous: str, replacement: str) -> str:
    if text.count(previous) != 1:
        raise ValueError("SAFE_STOP_UID_PROBE_MAIN_ANCHOR_NOT_UNIQUE")
    return text.replace(previous, replacement, 1)


def bind(project: Path) -> None:
    root = ROOT.resolve()
    project = project.resolve()
    if project == root or root in project.parents or project in root.parents:
        raise ValueError("SAFE_STOP_NEVER_PATCH_DEDA_REPOSITORY")
    page = project / "lib" / "main.dart"
    if not page.is_file():
        raise ValueError("SAFE_STOP_FULL_APP_MISSING")
    original = page.read_text(encoding="utf-8")
    if not all(token in original for token in (
        "DEDA_100441_FRIENDS_RETRY_FIX",
        "DedaUnifiedRoomRuntimeReadOnly.preflightOnHome()",
        "DedaMissingOwnerEntryPolicy.canOffer")):
        raise ValueError("SAFE_STOP_REQUIRES_PROTECTED_COMPLETE_APP")
    if any(token in original for token in (
        "DedaSessionDiagnosticReadOnlyTile(",
        "DedaGoogleSettingsLinkCard(",
        "deda_current_uid_probe_100453.dart")):
        raise ValueError("SAFE_STOP_REMOVED_CARDS_OR_ALREADY_BOUND")
    targets = [project / "lib" / name for name in (PROBE, FINGERPRINT)]
    if any(path.exists() for path in targets):
        raise ValueError("SAFE_STOP_UID_PROBE_TARGET_EXISTS")

    new = once(original,
        "import 'deda_session_missing_owner_entry_100441.dart';",
        "import 'deda_session_missing_owner_entry_100441.dart';\n"
        "import 'deda_current_uid_probe_100453.dart';")
    anchor = """        title: Text(dedaText('الإعدادات', 'Settings')),
        centerTitle: true,"""
    replacement = """        title: Text(dedaText('الإعدادات', 'Settings')),
        centerTitle: true,
        // QA-only current UID fingerprint. No deleted settings card,
        // silent session change, Google link, Firestore read or account write.
        actions: [
          if (dedaCurrentUidProbe100453Qa)
            IconButton(
              icon: const Icon(Icons.fingerprint),
              tooltip: dedaText('فحص UID الحالي', 'Current UID check'),
              onPressed: () => DedaCurrentUidProbe100453.open(context),
            ),
        ],"""
    new = once(new, anchor, replacement)
    if new.count("DedaCurrentUidProbe100453.open(context)") != 1:
        raise ValueError("SAFE_STOP_UID_PROBE_ACTION_NOT_EXACTLY_ONCE")
    source = (ROOT / "lib" / PROBE).read_text(encoding="utf-8")
    for forbidden in ("signInAnonymously(", "signOut(", "signInWith",
                      "createUser(", "linkWithCredential(", ".set(",
                      ".update(", ".delete(", ".add(", ".doc("):
        if forbidden in source:
            raise ValueError("SAFE_STOP_AUTH_OR_DB_MUTATION_" + forbidden)
    for filename, target in zip((PROBE, FINGERPRINT), targets):
        shutil.copy2(ROOT / "lib" / filename, target)
    page.write_text(new, encoding="utf-8")
    print("PASS_QA_UID_PROBE_BOUND_ONLY_TO_SETTINGS_APPBAR_NO_CARD_NO_AUTH_CHANGE")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("project", type=Path)
    bind(p.parse_args().project)
