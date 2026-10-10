"""Surgical, READ-ONLY production-rules merge PREVIEW for DEDA manager gifts.

Requires saved exact live rule source from Firebase Rules API (GET only).
No credentials, network, Firebase update, or APK build inside this script.
NEVER deploy output without owner approval and separate real-account QA.
"""
import hashlib
import sys
from pathlib import Path

LIVE_SHA18 = "c5b444a132c894e933"
if len(sys.argv) != 2:
    sys.exit("USAGE: python3 tools/deda_preview_merge_live_admin_gifts_2026_10_10.py <live.rules>")
live = Path(sys.argv[1]).read_text(encoding="utf-8")
candidate = Path("firestore.rules").read_text(encoding="utf-8")
digest = lambda s: hashlib.sha256(s.encode()).hexdigest()[:18]
if digest(live) != LIVE_SHA18:
    sys.exit("SAFE_STOP: published Firebase rules changed; refuse merge")
if "DEDA_ADMIN_SECURE_PENDING_GIFTS_2026_10_10" not in candidate:
    sys.exit("SAFE_STOP: development reviewed gift rules not found")
if candidate.count("function verifiedDiamondsPersonalOwner(publicId)") != 1:
    sys.exit("SAFE_STOP: verified recipient owner helper missing")
if "function verifiedDiamondsPersonalOwner(publicId)" in live:
    sys.exit("SAFE_STOP: live already has recipient helper; manual review required")

def extract(source: str, prefix: str) -> str:
    if source.count(prefix) != 1:
        raise ValueError(f"Ambiguous or missing source block {prefix}")
    start = source.index(prefix)
    # skip brackets in path placeholders like /{publicId}.
    brace = source.index("{", start + len(prefix))
    depth = 0
    end = None
    for i in range(brace, len(source)):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                end = i + 1
                break
    if end is None:
        raise ValueError(f"Unclosed rule block {prefix}")
    return source[start:end]

# Preserve the *full* original live source, including distinct DEDA admins,
# social, GPS, login, Telegram, tasks, personal wallet and other rules.
# The only replaced blocks are these exact 3 gift collections.
collections = [
    "match /deda_admin_diamond_wallets/{adminUid}",
    "match /deda_diamond_gift_balances/{publicId}",
    "match /deda_diamond_gifts/{giftId}",
]
merged = live
old_new = []
for name in collections:
    old = extract(live, name)
    new = extract(candidate, name)
    if old == new:
        raise ValueError(f"Live gift block already matches candidate: {name}")
    if merged.count(old) != 1:
        raise ValueError(f"Cannot replace exactly one {name}")
    merged = merged.replace(old, new, 1)
    old_new.append((old, new))

# All added helpers are pure Firestore Rules functions with static names;
# none of the live login/social/account-owner functions is replaced.
helpers = [
    "function verifiedDiamondsPersonalOwner(publicId)",
    "function verifiedGiftGeneralManager()",
    "function adminGiftPath(giftId)",
    "function adminGiftWalletPath(adminUid)",
    "function userGiftBalancePath(publicId)",
    "function validGiftClaim(giftId, publicId)",
]
insert = "\n\n" + "\n\n".join("    " + extract(candidate, p) for p in helpers) + "\n\n"
anchor = "    // DEDA_SOCIAL_ADMIN_DIAMONDS_100270"
if merged.count(anchor) != 1 or live.count(anchor) != 1:
    raise ValueError("Unexpected live gift location; manual review required")
merged = merged.replace(anchor, insert + anchor, 1)

# REVERSIBILITY PROOF: a surgical merge must restore EXACT original live text
# when removing only its newly inserted helpers and these replaced blocks.
reverse = merged.replace(insert, "", 1)
for old, new in reversed(old_new):
    if reverse.count(new) != 1:
        raise ValueError("Unexpected merged code duplication")
    reverse = reverse.replace(new, old, 1)
if reverse != live:
    raise ValueError("SAFE_STOP: non-gift production rules were modified")

for name in collections:
    if merged.count(name) != 1:
        raise ValueError("Unexpected duplication of gift collection")
for name in helpers:
    if merged.count(name) != 1:
        raise ValueError("Unexpected duplication of helper")
for marker in [
    "match /deda_gm_personal_diamond_wallets/{accountKey}",
    "match /deda_social_direct_days/{dayId}",
    "match /deda_social_direct_drafts/{draftId}",
    "match /admin_audit/{auditId}",
]:
    if merged.count(marker) != live.count(marker):
        raise ValueError(f"Non-gift critical rule section changed {marker}")
if "lastGiftId" not in merged or "lastClaimGiftId" not in merged:
    raise ValueError("Gift debit/claim mandatory transaction markers missing")
Path("firestore.rules").write_text(merged, encoding="utf-8")
print("LIVE_SHA18", digest(live))
print("MERGED_REVIEW_SHA18", digest(merged))
print("REVERSE_DIFF_PROOF: PASS — only 3 gift rules and 6 gift helpers changed")
print("NO FIREBASE API WRITE. REVIEW and EMULATOR tests still required.")
