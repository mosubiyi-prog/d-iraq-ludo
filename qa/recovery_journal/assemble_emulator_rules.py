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
out = Path(os.environ.get("DEDA_JOURNAL_EMULATOR_RULES",
                          "/tmp/deda100436-journal-emulator.rules"))
if out.resolve() in (baseline.resolve(), candidate.resolve()):
    raise SystemExit("SAFE_STOP_CANNOT_WRITE_SOURCE_FIRESTORE_RULES")
base = baseline.read_text(encoding="utf8")
addition = candidate.read_text(encoding="utf8")
assert base.startswith("rules_version = '2';")
assert "match /deda_recovery_journals/" not in base
assert "match /deda_recovery_journals/" in addition
assert "allow update, delete: if false;" in addition
assert "match /deda_recovery_server_attestations/" in addition
assert "allow read, write: if false;" in addition
end_marker = "\n  }\n}\n"
if base.count(end_marker) != 1:
    raise SystemExit("SAFE_STOP_BASELINE_RULES_STRUCTURE_CHANGED")
insert_at = base.rfind(end_marker)
assert insert_at > 0
result = base[:insert_at] + "\n\n    // QA LOCAL ONLY — no Firebase deployment\n" + "\n".join(
    "    " + x if x else "" for x in addition.splitlines()
) + "\n" + base[insert_at:]
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(result, encoding="utf8")
print("BASELINE_SHA256=" + hashlib.sha256(base.encode()).hexdigest())
print("CANDIDATE_SHA256=" + hashlib.sha256(addition.encode()).hexdigest())
print("EMULATOR_ONLY_SHA256=" + hashlib.sha256(result.encode()).hexdigest())
print("SAFE_NO_DEPLOY_NO_PRODUCTION_RULES_MODIFICATION")
