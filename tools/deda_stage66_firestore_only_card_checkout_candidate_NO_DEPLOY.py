#!/usr/bin/env python3
"""Stage66: SPARK Firestore-only atomic card checkout security candidate.

Proof-of-concept, NOT a live-app checkout. Uses the Stage52 source-only
wallet-hardening candidate. Never modifies/deploys firestore.rules and does
not rely on Cloud Functions. Supports server-seeded gift wallet ONLY, not
unverified device-local earned diamonds. This path must not be enabled for
real DEDA users without reconciliation of deployed rules and wallet source.
"""
from pathlib import Path
from deda_owner19_stage52_wallet_rules_candidate_OFFLINE_NO_DEPLOY import candidate

MARKER = "// STAGE66_FIRESTORE_ONLY_CANDIDATE_NO_DEPLOY"
CLAIM = "          // The sole way to increase is claiming ONE existing pending gift."
RULE = """    // STAGE66_FIRESTORE_ONLY_CANDIDATE_NO_DEPLOY
    // Prototype: immutable one-per-color receipts, never original100 data.
    function stage66ReceiptPath(receiptId) {
      return /databases/$(database)/documents/deda_stage66_card_receipts/$(receiptId);
    }
    function stage66CardPath(receiptId) {
      return /databases/$(database)/documents/deda_stage66_owned_cards/$(receiptId);
    }
    function stage66WalletPath(publicId) {
      return /databases/$(database)/documents/deda_diamond_gift_balances/$(publicId);
    }
    function stage66CardStyle(style) {
      return style in ['gold', 'diamond', 'royal', 'pink'];
    }
    function stage66CardSpend(publicId) {
      let style = request.resource.data.get('lastPurchaseStyle', '');
      let receiptId = publicId + '_' + style;
      return stage66CardStyle(style)
        && request.resource.data.lastPurchaseReceiptId == receiptId
        && request.resource.data.balance == resource.data.balance - 5000
        && resource.data.balance >= 5000
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly([
          'balance', 'updatedAt', 'lastPurchaseStyle', 'lastPurchaseReceiptId'
        ])
        && !exists(stage66ReceiptPath(receiptId))
        && existsAfter(stage66ReceiptPath(receiptId))
        && getAfter(stage66ReceiptPath(receiptId)).data.publicId == publicId
        && getAfter(stage66ReceiptPath(receiptId)).data.style == style
        && getAfter(stage66ReceiptPath(receiptId)).data.cost == 5000
        && existsAfter(stage66CardPath(receiptId))
        && getAfter(stage66CardPath(receiptId)).data.publicId == publicId
        && getAfter(stage66CardPath(receiptId)).data.receiptId == receiptId;
    }
    match /deda_stage66_card_receipts/{receiptId} {
      allow get: if verifiedDiamondsPersonalOwner(resource.data.publicId);
      allow list, update, delete: if false;
      allow create: if request.resource.data.publicId is string
        && verifiedDiamondsPersonalOwner(request.resource.data.publicId)
        && stage66CardStyle(request.resource.data.style)
        && receiptId == request.resource.data.publicId + '_' + request.resource.data.style
        && request.resource.data.cost == 5000
        && request.resource.data.kind == 'card'
        && request.resource.data.createdAt == request.time
        && request.resource.data.keys().hasOnly([
          'publicId', 'style', 'kind', 'cost', 'createdAt'
        ])
        && exists(stage66WalletPath(request.resource.data.publicId))
        && existsAfter(stage66WalletPath(request.resource.data.publicId))
        && getAfter(stage66WalletPath(request.resource.data.publicId)).data.balance ==
          get(stage66WalletPath(request.resource.data.publicId)).data.balance - 5000
        && getAfter(stage66WalletPath(request.resource.data.publicId)).data.lastPurchaseReceiptId == receiptId
        && existsAfter(stage66CardPath(receiptId))
        && getAfter(stage66CardPath(receiptId)).data.receiptId == receiptId;
    }
    match /deda_stage66_owned_cards/{receiptId} {
      allow get: if verifiedDiamondsPersonalOwner(resource.data.publicId);
      allow list, update, delete: if false;
      allow create: if request.resource.data.publicId is string
        && verifiedDiamondsPersonalOwner(request.resource.data.publicId)
        && stage66CardStyle(request.resource.data.style)
        && receiptId == request.resource.data.publicId + '_' + request.resource.data.style
        && request.resource.data.receiptId == receiptId
        && request.resource.data.createdAt == request.time
        && request.resource.data.keys().hasOnly([
          'publicId', 'style', 'receiptId', 'createdAt'
        ])
        && !exists(stage66ReceiptPath(receiptId))
        && existsAfter(stage66ReceiptPath(receiptId))
        && getAfter(stage66ReceiptPath(receiptId)).data.cost == 5000
        && getAfter(stage66ReceiptPath(receiptId)).data.publicId == request.resource.data.publicId;
    }

"""
SPEND = """          // Fixed-price atomic Spark card debit. A receipt+ownership must
          // be created in the SAME transaction; replay without entitlement
          // is denied. Existing legitimate pending gift claim is preserved.
          (stage66CardSpend(publicId))
          ||
"""
def make(current: str) -> str:
    if MARKER in current: raise ValueError('SAFE_STOP_ALREADY_STAGE66')
    staged = candidate(current)
    if staged.count(CLAIM) != 1: raise ValueError('SAFE_STOP_GIFT_CLAIM_ANCHOR')
    if staged.count("    match /deda_diamond_gift_balances/{publicId} {") != 1:
        raise ValueError('SAFE_STOP_WALLET_PATH')
    if staged.count("    // DEDA_ADMIN_SECURE_PENDING_GIFTS_2026_10_10") != 1:
        raise ValueError('SAFE_STOP_OWNER_GIFT_BLOCK')
    # Insert functions and new collections at the sole protected gift boundary.
    staged = staged.replace(
        "    // DEDA_ADMIN_SECURE_PENDING_GIFTS_2026_10_10",
        RULE + "    // DEDA_ADMIN_SECURE_PENDING_GIFTS_2026_10_10", 1
    )
    staged = staged.replace(CLAIM, SPEND + CLAIM, 1)
    assert staged.count(MARKER) == 1
    assert staged.count("validGiftClaim(") == current.count("validGiftClaim(")
    assert "allow create, update: if false;" in staged
    return staged

if __name__ == '__main__':
    import sys
    if len(sys.argv) != 3:
        raise SystemExit("Usage: stage66.py firestore.rules /tmp/deda-stage66-candidate.rules")
    source, target = Path(sys.argv[1]), Path(sys.argv[2])
    if target.parent != Path('/tmp') or target.name != 'deda-stage66-candidate.rules' or source.resolve() == target.resolve():
        raise SystemExit('SAFE_STOP_MUST_OUTPUT_ONLY_TO_TMP')
    target.write_text(make(source.read_text()))
    print('PASS_STAGE66_GENERATED_NO_DEPLOY_NO_LIVE_DATA')
