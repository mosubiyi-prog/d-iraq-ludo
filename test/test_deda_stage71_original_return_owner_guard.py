#!/usr/bin/env python3
"""DEDA: original-ID return must not depend on premium inventory resolution.

Source contract only. Flutter analysis must also pass in the QA workflow.
No Firebase/Play write or Auth token should ever be used by this test.
"""
from pathlib import Path

src = Path("lib/deda_stage71_free_owned_use_profile.dart").read_text()

service = src.split("class DedaStage71OwnedIdentifierService {", 1)[1].split(
    "/// User's Edit Profile:", 1)[0]
proof = service.split("static Future<String> _requireOriginal(", 1)[1].split(
    "static Future<List<DedaStage71OwnedIdentifier>> owned(", 1)[0]
panel = src.split("class _DedaStage71OwnedIdsPanelState", 1)[1].split(
    "/// On the user's personal hero", 1)[0]
load = panel.split("Future<void> _load()", 1)[1].split("Future<void> _use(", 1)[0]
render = panel.split("Widget build(BuildContext context)", 1)[1]

assert "DedaQa32ManagerOriginalOwnerProof.authentic(" in proof
assert "deda_sessions" in proof and "deda_share_ids" in proof
assert "GetOptions(source: Source.server)" in proof
assert "user.uid" in proof
assert "verifyOriginalOwner(String originalId)" in proof
assert "_requireOriginal(originalId)" in proof

# Regression: the owner must see the immutable original row after proof even
# if the paid inventory or active-alias receipt read errors or takes longer.
assert "verifyOriginalOwner(original)" in load
assert load.index("verifyOriginalOwner(original)") < load.index("readPremium()")
assert "Future<void> readActive()" in load and "Future<void> readPremium()" in load
assert "await Future.wait<void>([readActive(), readPremium()])" in load
assert "_ids = null;" in load and "_verifiedUid = null;" in load
assert "if (!stillSameOwner() || provenUid != uid) return;" in load
assert "if (!stillSameOwner() || _verifiedUid != uid) return;" in load
assert "final originalVerified = _verifiedUid != null" in render
assert "final currentRows = originalVerified ? _ids : null" in render
assert "if (originalVerified)\n              ListTile(" in render
assert "if (currentRows != null)\n              ListTile(" not in render
assert "for(final owned in currentRows ?? <DedaStage71OwnedIdentifier>[])" in render
assert "uid == null || uid != _verifiedUid" in panel

# Original-use is still server-authoritative, never a local cosmetic toggle.
use = service.split("static Future<void> use(", 1)[1]
assert "final uid=await _requireOriginal(originalId);" in use
assert "if (identifier!=originalId)" in use
assert "final persisted=await active(originalId);" in use
assert "if(persisted!=identifier)" in use
assert "publishOwnerVerified(" in use
assert "DedaVerifiedActiveIdStore.confirmed(" in use
print("PASS: original reactivation decoupled from premium loading, exact owner guard retained")
