#!/usr/bin/env python3
"""DEDA owner19 Stage52 — PREVIEW-ONLY wallet Firestore rules hardening.

Reads the existing repo firestore.rules and produces a local candidate in
an explicit destination path. NEVER overwrites or deploys real rules. Release
still requires manual wallet provenance review, Google Play owner approval
and emulator/real-client compatibility acceptance.
"""
from pathlib import Path
import sys

GM_START = "    match /deda_gm_personal_diamond_wallets/{accountKey} {"
GM_END = "\n    // DEDA_ADMIN_SECURE_PENDING_GIFTS_2026_10_10"
GIFT_START = "    match /deda_diamond_gift_balances/{publicId} {"
GIFT_END = "\n    match /deda_diamond_gifts/{giftId} {"
GM_CREATE = "      allow create: if isGeneralManagerPersonalAccount(accountKey)"
GM_UPDATE = "      allow update: if isGeneralManagerPersonalAccount(accountKey)"
GIFT_CLIENT_DECREASE = """          // Existing legitimate purchases may only DECREASE this balance.
          (request.resource.data.balance <= resource.data.balance
            && request.resource.data.diff(resource.data).affectedKeys().hasOnly([
              'balance', 'updatedAt'
            ]))
          ||
"""
GIFT_LEGIT_CLAIM = """          // The sole way to increase is claiming ONE existing pending gift.
          (request.resource.data.balance > resource.data.balance"""


def _slice(text: str, start: str, end: str):
    if text.count(start) != 1 or text.count(end) != 1:
        raise ValueError("SAFE_STOP: original wallet rule boundary changed")
    a = text.index(start)
    b = text.index(end, a + len(start))
    return a, b, text[a:b]


def candidate(current: str) -> str:
    if "STAGE52_CANDIDATE_ONLY_NO_DEPLOY" in current:
        raise ValueError("SAFE_STOP: never harden an already modified policy")
    gm_a, gm_b, gm = _slice(current, GM_START, GM_END)
    gift_a, gift_b, gift = _slice(current, GIFT_START, GIFT_END)
    if not gm_a < gm_b < gift_a < gift_b:
        raise ValueError("SAFE_STOP: wallet rules moved or reordered")
    if gm.count(GM_CREATE) != 1 or gm.count(GM_UPDATE) != 1:
        raise ValueError("SAFE_STOP: manager wallet source policy changed")
    if gift.count(GIFT_CLIENT_DECREASE) != 1 or \
            gift.count(GIFT_LEGIT_CLAIM) != 1:
        raise ValueError("SAFE_STOP: existing gift claim/debit clause changed")

    # Admin SDK bypasses Firestore client rules for trusted transactions. A
    # client cannot mint/replenish its own personal manager testing million,
    # nor spend/decrease it without a trusted server purchase receipt.
    create_a = gm.index(GM_CREATE)
    update_a = gm.index(GM_UPDATE, create_a)
    delete_a = gm.index("      allow delete: if false;", update_a)
    gm_revised = (
        gm[:create_a] +
        "      // STAGE52_CANDIDATE_ONLY_NO_DEPLOY\n" +
        "      // GM test-money creation and debits require reviewed backend\n" +
        "      // provenance; reject all client writes in the candidate.\n" +
        "      allow create, update: if false;\n\n" +
        gm[delete_a:]
    )
    # Preserve the existing authorized gift claim transaction including its
    # exact pre-existing gift/status checks, but deny all CLIENT-only decreases.
    gift_revised = gift.replace(GIFT_CLIENT_DECREASE, "", 1)
    if not (gift_revised.count(GIFT_LEGIT_CLAIM) == 1 and
            gift_revised.count("&& validGiftClaim(") == gift.count("&& validGiftClaim(")):
        raise ValueError("SAFE_STOP: pending-gift credit must stay intact")
    modified = (
        current[:gm_a] + gm_revised + current[gm_b:gift_a] +
        gift_revised + current[gift_b:]
    )
    if modified.replace(gm_revised, gm, 1).replace(
            gift_revised, gift, 1) != current:
        raise ValueError("SAFE_STOP: unrelated Firebase rules would change")
    if "allow get: if isGeneralManagerPersonalAccount(accountKey);" not in gm_revised:
        raise ValueError("SAFE_STOP: manager legacy balance read changed")
    if "allow create: if verifiedDiamondsPersonalOwner(publicId)" not in gift_revised:
        raise ValueError("SAFE_STOP: legitimate gift claim create removed")
    return modified


def inspect(current: str) -> dict:
    # Source-level observation only, not a claim about deployed live rules.
    _, _, gm = _slice(current, GM_START, GM_END)
    _, _, gift = _slice(current, GIFT_START, GIFT_END)
    return {
        "client_manager_test_million_create_permitted":
            GM_CREATE in gm,
        "client_manager_wallet_debit_permitted":
            GM_UPDATE in gm,
        "client_gift_wallet_unreceipted_debit_permitted":
            GIFT_CLIENT_DECREASE in gift,
        "gift_claim_branch_preserved":
            GIFT_LEGIT_CLAIM in gift,
        "ready_to_deploy": False,
    }


def main():
    if len(sys.argv) != 3:
        raise SystemExit("Usage: script firestore.rules /tmp/stage52-candidate.rules")
    source = Path(sys.argv[1]).resolve()
    destination = Path(sys.argv[2]).resolve()
    if source == destination or destination.name == "firestore.rules" or \
            not str(destination).startswith("/tmp/"):
        raise SystemExit("SAFE_STOP: only an explicit /tmp/ candidate path allowed")
    original = source.read_text(encoding="utf8")
    before = inspect(original)
    revised = candidate(original)
    after = inspect(revised)
    assert before["client_gift_wallet_unreceipted_debit_permitted"]
    assert not after["client_gift_wallet_unreceipted_debit_permitted"]
    assert not after["client_manager_test_million_create_permitted"]
    assert not after["client_manager_wallet_debit_permitted"]
    assert after["gift_claim_branch_preserved"]
    destination.write_text(revised, encoding="utf8")
    print("PASS: isolated candidate blocks client balance decreases and")
    print("      client self-mint of the GM test million; gift claims retained")
    print("PASS: existing firestore.rules NOT CHANGED, NO DEPLOY")
    print("BLOCKED: live adoption needs owner wallet/source audit and emulator QA")


if __name__ == "__main__":
    main()
