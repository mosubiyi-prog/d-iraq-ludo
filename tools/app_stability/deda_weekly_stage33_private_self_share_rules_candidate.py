#!/usr/bin/env python3
"""Private Stage33 proposed additive fix for the deployed DEDA location-share
self-recipient gap. Read fetched LIVE rules in runner temp, construct a patched
ephemeral *local emulator* candidate. NEVER deploy, log, or upload full rules.
"""
from pathlib import Path
import os

def main():
    orig=Path(os.environ["DEDA_STAGE24_LIVE_RULES_TMPFILE"]).resolve()
    dest=Path(os.environ["DEDA_STAGE33_PATCHED_RULES_FILE"]).resolve()
    temp=Path(os.environ["RUNNER_TEMP"]).resolve()
    if orig.parent != temp or dest.parent != temp or orig==dest:
        raise RuntimeError("stage33-only-runner-temp-input-and-output")
    if orig.suffix!=".rules" or dest.suffix!=".rules":
        raise RuntimeError("stage33-no-rules-output")
    text=orig.read_text(encoding="utf-8")
    section="match /deda_location_shares/{shareId} {"
    if text.count(section)!=1:
        raise RuntimeError("stage33-share-rule-not-unique")
    before,rest=text.split(section,1)
    if "allow create: if signedIn()" not in rest:
        raise RuntimeError("stage33-create-rule-not-known")
    # Scope the addition to THIS match's allow create clause only.
    portion,after=rest.split("allow update:",1)
    target=(
        "&& request.resource.data.senderUid == request.auth.uid"
    )
    if portion.count(target)!=1:
        raise RuntimeError("stage33-create-identity-condition-mismatch")
    inserted=(
        target+"\n        "
        "&& request.resource.data.senderPublicId != "
        "request.resource.data.recipientPublicId"
    )
    revised=portion.replace(target,inserted,1)
    patched=before+section+revised+"allow update:"+after
    if patched==text or patched.replace(inserted,target,1)!=text:
        raise RuntimeError("stage33-not-a-single-additive-guard")
    dest.write_text(patched,encoding="utf-8")
    dest.chmod(0o600)
    print("STAGE33_SAFE_ADD_ONLY_SELF_SHARE_GUARD_TO_EPHEMERAL_LOCAL_RULES")
if __name__=="__main__":
    main()
