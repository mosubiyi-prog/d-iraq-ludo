#!/usr/bin/env python3
"""Stage70: atomic, owner-approved Group002 10,000-diamond Spark sale.

Offline candidate extension to *actual published* Firebase rules, as safely
hardened by Stage69. No Firestore production writes/deploy/APK and NO Group001
secret catalogue in APK, public Firestore or CI output. Group002 stock is
strictly server-seeded, immutable approval + price; unseeded IDs cannot be
purchased. Atomic wallet debit, reserved stock sold state, receipt and unique
registry grant. The exact owner always stays unchanged.
"""
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
from deda_stage69_merge_5000_checkout_into_live_rules_READONLY_NO_DEPLOY import (
    candidate as stage69, WALLET, match_end
)

BASE_MARKER='STAGE66_FIRESTORE_ONLY_CANDIDATE_NO_DEPLOY'
MARKER='STAGE70_GROUP002_FIXED_10000_SPARK_NO_DEPLOY'
OUT=Path('/tmp/deda-stage70-candidate.rules')
RULE = """
    // STAGE70_GROUP002_FIXED_10000_SPARK_NO_DEPLOY
    // 2-document atomic wallet and unique ownership receipt; no GM secrets.
    function stage70StockPath(identifier) {
      return /databases/$(database)/documents/deda_stage70_group002_stock/$(identifier);
    }
    function stage70RegistryPath(identifier) {
      return /databases/$(database)/documents/deda_stage70_group002_registry/$(identifier);
    }
    function stage70SaleIdFormat(identifier) {
      return identifier is string && identifier.matches('^@DEDA-[A-Z0-9]{6}$');
    }
    function stage70Spend(publicId) {
      let id = request.resource.data.get('lastPurchaseIdentifier', '');
      return stage70SaleIdFormat(id)
        && resource.data.balance >= 10000
        && request.resource.data.balance == resource.data.balance - 10000
        && request.resource.data.lastPurchaseReceiptId == publicId + '__' + id
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly([
          'balance','updatedAt','lastPurchaseIdentifier','lastPurchaseReceiptId'
        ])
        && !exists(stage70RegistryPath(id))
        && existsAfter(stage70RegistryPath(id))
        && getAfter(stage70RegistryPath(id)).data.publicId == publicId
        && getAfter(stage70RegistryPath(id)).data.cost == 10000;
    }
    match /deda_stage70_group002_stock/{identifier} {
      // Inventory approval can be written only by trusted Admin SDK.
      allow get: if signedIn();
      allow list: if signedIn() && request.query.limit <= 100;
      allow create, update, delete: if false;
    }
    function stage70ApprovedStock(identifier) {
      let item = get(stage70StockPath(identifier)).data;
      return item.identifier == identifier
        && item.group == '002'
        && item.approved == true
        && item.priceDiamonds == 10000
        && item.status == 'available';
    }
    function stage70ExactWalletDebit(publicId, receiptId) {
      let path = /databases/$(database)/documents/deda_diamond_gift_balances/$(publicId);
      let previous = get(path).data;
      let current = getAfter(path).data;
      return previous.balance >= 10000
        && current.balance == previous.balance - 10000
        && current.lastPurchaseReceiptId == receiptId;
    }
    match /deda_stage70_group002_registry/{identifier} {
      // The unique immutable ownership record doubles as checkout receipt.
      allow get: if signedIn();
      allow list, update, delete: if false;
      allow create: if signedIn()
        && stage70SaleIdFormat(identifier)
        && request.resource.data.publicId is string
        && request.resource.data.identifier == identifier
        && request.resource.data.kind == 'group002'
        && request.resource.data.cost == 10000
        && request.resource.data.receiptId ==
           request.resource.data.publicId + '__' + identifier
        && request.resource.data.createdAt == request.time
        && request.resource.data.keys().hasOnly([
          'identifier','publicId','kind','cost','receiptId','createdAt'
        ])
        && stage70ApprovedStock(identifier)
        && stage70ExactWalletDebit(
          request.resource.data.publicId,request.resource.data.receiptId);
    }


"""
WALLET_ALLOW = """
      // STAGE70_SALE_CHARGE_ONLY_WITH_IMMUTABLE_REGISTRY_AND_RECEIPT
      allow update: if verifiedDiamondsPersonalOwner(publicId)
        && stage70Spend(publicId);
"""
def extend(stage69_rules: str) -> str:
    if stage69_rules.count(BASE_MARKER)!=1 or MARKER in stage69_rules:
        raise ValueError('STAGE70_SOURCE_MISMATCH')
    if stage69_rules.count(WALLET)!=1 or 'STAGE69_SPARK_ADDITIVE_CARD_ALLOWANCE_OFFLINE_ONLY' not in stage69_rules:
        raise ValueError('STAGE70_UNHARDENED_WALLET')
    p=stage69_rules.index(WALLET)
    end=match_end(stage69_rules,p)
    wallet=stage69_rules[p:end+1]
    if wallet.count('STAGE69_SPARK_ADDITIVE_CARD_ALLOWANCE_OFFLINE_ONLY')!=1:
        raise ValueError('STAGE70_MISSING_ATOMIC_CARD_RULE')
    updated_wallet=wallet[:-1]+WALLET_ALLOW+wallet[-1:]
    result=stage69_rules[:p]+RULE+updated_wallet+stage69_rules[end+1:]
    if result.replace(RULE,'',1).replace(WALLET_ALLOW,'',1)!=stage69_rules:
        raise ValueError('STAGE70_UNEXPECTED_RULE_DIFF')
    if result.count(MARKER)!=1 or result.count('STAGE70_SALE_CHARGE_ONLY_WITH_IMMUTABLE_REGISTRY_AND_RECEIPT')!=1:
        raise ValueError('STAGE70_DUPLICATE_RULES')
    return result

def candidate(live: str) -> str:
    return extend(stage69(live))

if __name__=='__main__':
    if len(sys.argv)!=2 or Path(sys.argv[1])!=Path('/tmp/deda-stage66-candidate.rules'):
        raise SystemExit('SAFE_STOP_ONLY_STAGE69_TMP_RULES')
    s=Path(sys.argv[1]).read_text()
    OUT.write_text(extend(s))
    print('PASS_STAGE70_GROUP002_CANDIDATE_CREATED_NO_FIREBASE_DEPLOY')
