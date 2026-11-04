#!/usr/bin/env python3
"""Construct local Emulator-only rules from pinned 100436 + vault candidate.

NEVER writes firestore.rules, Firebase prod or Cloud resources.
Fails if the checkpoint no longer exactly matches the owner-approved baseline.
"""
from pathlib import Path
import hashlib
import os

BASELINE_RULES_SHA256 = None  # QA guards use verified Git file SHA in workflow.
root = Path(__file__).resolve().parents[2]
baseline = root / "firestore.rules"
candidate = root / "qa/recovery_journal/deda_recovery_journal_rules_CANDIDATE_NOT_DEPLOYED.rules"
session_candidate = root / "qa/recovery_journal/deda_linked_owner_session_bootstrap_CANDIDATE_NOT_DEPLOYED.rules"
out = Path(os.environ.get("DEDA_JOURNAL_EMULATOR_RULES",
                          "/tmp/deda100436-journal-emulator.rules"))
if out.resolve() in (baseline.resolve(), candidate.resolve()):
    raise SystemExit("SAFE_STOP_CANNOT_WRITE_SOURCE_FIRESTORE_RULES")
base = baseline.read_text(encoding="utf8")
addition = candidate.read_text(encoding="utf8")
session_addition = session_candidate.read_text(encoding="utf8")
assert "allow read, write: if false;" in session_addition
assert "dedaLinkedOriginalOwnerSessionBootstrap" in session_addition
assert base.startswith("rules_version = '2';")
assert "match /deda_recovery_journals/" not in base
assert "match /deda_recovery_journals/" in addition
assert "allow update, delete: if false;" in addition
assert "match /deda_recovery_server_attestations/" in addition
assert "allow read, write: if false;" in addition
end_marker = "\n  }\n}\n"
if base.count(end_marker) != 1:
    raise SystemExit("SAFE_STOP_BASELINE_RULES_STRUCTURE_CHANGED")
# Insert ONE narrowly scoped OR alternative INSIDE existing session proof
# parentheses. All preexisting session field/UID checks stay mandatory.
session_start = base.find("    match /deda_sessions/{uid} {")
session_end = base.find("    match /deda_account_profiles/{accountKey} {", session_start)
if session_start < 0 or session_end < 0:
    raise SystemExit("SAFE_STOP_SESSION_RULE_NOT_FOUND")
session_old = base[session_start:session_end]
old_head = """        && (
          (
            exists(/databases/$(database)/documents/deda_auth_attempts/$(uid))"""
new_head = """        && (
          (
            request.auth.token.firebase.sign_in_provider == 'anonymous'
            && (
              (
                exists(/databases/$(database)/documents/deda_auth_attempts/$(uid))"""
old_tail = """              in get(/databases/$(database)/documents/deda_account_profiles/$(request.resource.data.accountKey)).data.trustedInstallIds
          )
        );"""
new_tail = """              in get(/databases/$(database)/documents/deda_account_profiles/$(request.resource.data.accountKey)).data.trustedInstallIds
          )
            )
          )
          || (
            request.auth.token.firebase.sign_in_provider == 'password'
            && dedaLinkedOriginalOwnerSessionBootstrap(uid, request.resource.data)
          )
        );"""
# Linked password sessions must NOT inherit the legacy anonymous UID's
# saved PIN attempt or trustedInstallId as an alternative to the NEW grant.
# Old anon / Play 100340 clients keep their existing PIN + trust paths.
if session_old.count(old_head) != 1 or session_old.count(old_tail) != 1:
    raise SystemExit("SAFE_STOP_SESSION_RULE_UNEXPECTED_SHAPE")
patched_session = session_old.replace(old_head, new_head).replace(old_tail, new_tail)
# Linked owner sign-out on one phone must NEVER delete the shared
# original-UID session needed by other signed-in phones. The released
# anonymous PIN client can still delete its own legacy session on logout.
old_delete = "      allow delete: if signedIn() && request.auth.uid == uid;"
new_delete = """      allow delete: if signedIn()
        && request.auth.uid == uid
        && request.auth.token.firebase.sign_in_provider == 'anonymous';"""
if patched_session.count(old_delete) != 1:
    raise SystemExit("SAFE_STOP_SESSION_DELETE_RULE_UNEXPECTED_SHAPE")
patched_session = patched_session.replace(old_delete, new_delete)
base = base[:session_start] + patched_session + base[session_end:]
insert_at = base.rfind(end_marker)
assert insert_at > 0
result = base[:insert_at] + "\n\n    // QA LOCAL ONLY — no Firebase deployment\n" + "\n".join(
    "    " + x if x else "" for x in (session_addition + "\n" + addition).splitlines()
) + "\n" + base[insert_at:]
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(result, encoding="utf8")
print("BASELINE_SHA256=" + hashlib.sha256(base.encode()).hexdigest())
print("CANDIDATE_SHA256=" + hashlib.sha256(addition.encode()).hexdigest())
print("SESSION_CANDIDATE_SHA256=" + hashlib.sha256(session_addition.encode()).hexdigest())
print("EMULATOR_ONLY_SHA256=" + hashlib.sha256(result.encode()).hexdigest())
print("SAFE_NO_DEPLOY_NO_PRODUCTION_RULES_MODIFICATION")
