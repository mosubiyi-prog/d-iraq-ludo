#!/usr/bin/env python3
"""Append stage2 owner-domain rules only to a throwaway emulator rules file.

Never writes firestore.rules, never calls Firebase CLI, never talks to cloud.
"""
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: assembler <existing-emulator-rules-file>")
target = Path(sys.argv[1]).resolve()
source_file = Path("firestore.rules").resolve()
fragment_file = Path(
    "qa/stage2/deda_recovery_domain_rules_emulator_only.fragment.rules"
).resolve()
spark_evidence_file = Path(
    "qa/stage2/deda_spark_legacy_prelink_evidence_EMULATOR_ONLY.fragment.rules"
).resolve()

if (target == source_file or not target.is_file() or
        not fragment_file.is_file() or not spark_evidence_file.is_file()):
    raise SystemExit("SAFE_STOP_PROTECTED_OR_MISSING_RULES")
original = target.read_text(encoding="utf-8")
fragment = fragment_file.read_text(encoding="utf-8")
spark_evidence = spark_evidence_file.read_text(encoding="utf-8")
for collection in ("deda_progress_evidence", "deda_purchase_evidence"):
    if f"match /{collection}/" in original:
        raise SystemExit(f"SAFE_STOP_EXISTING_PRELINK_RULES:{collection}")
    if spark_evidence.count(f"match /{collection}/") != 1:
        raise SystemExit(f"SAFE_STOP_PRELINK_FRAGMENT_MISMATCH:{collection}")
if not original.startswith("rules_version = '2';"):
    raise SystemExit("SAFE_STOP_INVALID_BASELINE_RULES")
for collection in (
    "deda_friendships",
    "deda_social_profiles",
    "deda_profile_ui_migration",
    "deda_quiz_ui_snapshots",
    "deda_stage71_active_identifier",
):
    if f"match /{collection}/" in original:
        raise SystemExit(f"SAFE_STOP_EXISTING_SOURCE_REQUIRES_RECONCILIATION:{collection}")
    if fragment.count(f"match /{collection}/") != 1:
        raise SystemExit(f"SAFE_STOP_FRAGMENT_MISMATCH:{collection}")

anchor = "\n  }\n}\n"
cut = original.rfind(anchor)
if cut < 0 or original.count("\n  match /databases/{database}/documents {") != 1:
    raise SystemExit("SAFE_STOP_UNEXPECTED_RULES_CLOSURE")
updated = (original[:cut] + "\n" + fragment.rstrip() + "\n" +
           spark_evidence.rstrip() + "\n" + original[cut:])
target.write_text(updated, encoding="utf-8")
assert source_file.read_text(encoding="utf-8") == Path("firestore.rules").read_text(
    encoding="utf-8"
)
print("PASS_DEDA_STAGE2_EMULATOR_ONLY_DOMAIN_RULES_APPENDED")
