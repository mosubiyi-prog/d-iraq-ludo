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
    // Group001 manager exclusive100 NEVER appears here.
    function stage70StockPath(identifier) {
      return /databases/$(database)/documents/deda_stage70_group002_stock/$(identifier);
    }
    function stage70RegistryPath(identifier) {
      return /databases/$(database)/documents/deda_stage70_group002_registry/$(identifier);
    }
    function stage70ReceiptPath(receiptId) {
      return /databases/$(database)/documents/deda_stage70_group002_receipts/$(receiptId);
    }
    function stage70SaleReceiptId(publicId, identifier) {
      return publicId + '__' + identifier;
    }
    function stage70SaleIdFormat(identifier) {
      return identifier is string
        && identifier.matches('^@DEDA-[A-Z0-9]{6}$');
    }
    function stage70Spend(publicId) {
      let id = request.resource.data.get('lastPurchaseIdentifier', '');
      let receiptId = stage70SaleReceiptId(publicId,id);
      return stage70SaleIdFormat(id)
        && request.resource.data.lastPurchaseReceiptId == receiptId
        && resource.data.balance is int
        && resource.data.balance >= 10000
        && request.resource.data.balance == resource.data.balance - 10000
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly([
          'balance', 'updatedAt', 'lastPurchaseIdentifier',
          'lastPurchaseReceiptId'
        ])
        && exists(stage70StockPath(id))
        && get(stage70StockPath(id)).data.approved == true
        && get(stage70StockPath(id)).data.group == '002'
        && get(stage70StockPath(id)).data.priceDiamonds == 10000
        && get(stage70StockPath(id)).data.status == 'available'
        && !exists(stage70RegistryPath(id))
        && !exists(stage70ReceiptPath(receiptId))
        && existsAfter(stage70StockPath(id))
        && getAfter(stage70StockPath(id)).data.status == 'sold'
        && getAfter(stage70StockPath(id)).data.soldToOriginalId == publicId
        && getAfter(stage70StockPath(id)).data.receiptId == receiptId
        && existsAfter(stage70RegistryPath(id))
        && getAfter(stage70RegistryPath(id)).data.publicId == publicId
        && getAfter(stage70RegistryPath(id)).data.receiptId == receiptId
        && existsAfter(stage70ReceiptPath(receiptId))
        && getAfter(stage70ReceiptPath(receiptId)).data.publicId == publicId
        && getAfter(stage70ReceiptPath(receiptId)).data.identifier == id
        && getAfter(stage70ReceiptPath(receiptId)).data.cost == 10000;
    }
    match /deda_stage70_group002_stock/{identifier} {
      // An actual owner-approved inventory is pre-provisioned by a trusted
      // administrator, NOT by any client. Nothing auto-publishes fake stock.
      allow get: if signedIn();
      allow list: if signedIn() && request.query.limit <= 100;
      allow create, delete: if false;
      allow update: if request.resource.data.soldToOriginalId is string
        && verifiedDiamondsPersonalOwner(request.resource.data.soldToOriginalId)
        && stage70SaleIdFormat(identifier)
        && resource.data.identifier == identifier
        && resource.data.group == '002'
        && resource.data.approved == true
        && resource.data.priceDiamonds == 10000
        && resource.data.status == 'available'
        && request.resource.data.status == 'sold'
        && request.resource.data.soldAt == request.time
        && request.resource.data.receiptId ==
          stage70SaleReceiptId(request.resource.data.soldToOriginalId, identifier)
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly([
          'status','soldToOriginalId','soldAt','receiptId'
        ])
        && !exists(stage70RegistryPath(identifier))
        && existsAfter(stage70RegistryPath(identifier))
        && getAfter(stage70RegistryPath(identifier)).data.publicId ==
          request.resource.data.soldToOriginalId
        && existsAfter(stage70ReceiptPath(request.resource.data.receiptId))
        && getAfter(stage70ReceiptPath(request.resource.data.receiptId)).data.cost == 10000;
    }
    match /deda_stage70_group002_registry/{identifier} {
      allow get: if signedIn();
      allow list: if signedIn() && request.query.limit <= 100
        && verifiedDiamondsPersonalOwner(resource.data.publicId);
      allow update, delete: if false;
      allow create: if stage70SaleIdFormat(identifier)
        && request.resource.data.identifier == identifier
        && request.resource.data.publicId is string
        && verifiedDiamondsPersonalOwner(request.resource.data.publicId)
        && request.resource.data.kind == 'group002'
        && request.resource.data.receiptId ==
          stage70SaleReceiptId(request.resource.data.publicId,identifier)
        && request.resource.data.createdAt == request.time
        && request.resource.data.keys().hasOnly([
          'identifier','publicId','kind','receiptId','createdAt'
        ])
        && exists(stage70StockPath(identifier))
        && get(stage70StockPath(identifier)).data.status == 'available'
        && existsAfter(stage70StockPath(identifier))
        && getAfter(stage70StockPath(identifier)).data.status == 'sold'
        && getAfter(stage70StockPath(identifier)).data.soldToOriginalId ==
          request.resource.data.publicId
        && existsAfter(stage70ReceiptPath(request.resource.data.receiptId))
        && getAfter(stage70ReceiptPath(request.resource.data.receiptId)).data.identifier == identifier;
    }
    match /deda_stage70_group002_receipts/{receiptId} {
      allow get: if verifiedDiamondsPersonalOwner(resource.data.publicId);
      allow list, update, delete: if false;
      allow create: if request.resource.data.publicId is string
        && verifiedDiamondsPersonalOwner(request.resource.data.publicId)
        && stage70SaleIdFormat(request.resource.data.identifier)
        && receiptId == stage70SaleReceiptId(
          request.resource.data.publicId,request.resource.data.identifier)
        && request.resource.data.kind == 'group002'
        && request.resource.data.cost == 10000
        && request.resource.data.createdAt == request.time
        && request.resource.data.keys().hasOnly([
          'publicId','identifier','kind','cost','createdAt'
        ])
        && exists(stage70StockPath(request.resource.data.identifier))
        && get(stage70StockPath(request.resource.data.identifier)).data.status == 'available'
        && existsAfter(stage70StockPath(request.resource.data.identifier))
        && getAfter(stage70StockPath(request.resource.data.identifier)).data.status == 'sold'
        && getAfter(stage70StockPath(request.resource.data.identifier)).data.receiptId == receiptId
        && existsAfter(stage70RegistryPath(request.resource.data.identifier))
        && getAfter(stage70RegistryPath(request.resource.data.identifier)).data.publicId ==
          request.resource.data.publicId
        && existsAfter(
          /databases/$(database)/documents/deda_diamond_gift_balances/$(request.resource.data.publicId))
        && getAfter(
          /databases/$(database)/documents/deda_diamond_gift_balances/$(request.resource.data.publicId)
          ).data.lastPurchaseReceiptId == receiptId;
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
