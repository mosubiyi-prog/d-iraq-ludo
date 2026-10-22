#!/usr/bin/env python3
"""Owner QA point01: build candidate LAB 1000-diamond rules IN MEMORY ONLY.

This extends audited Stage69 LIVE-policy-compatible candidate (never deploys).
Its trusted gift wallet is NOT the user's whole displayed diamonds; user/task/
historical manager balances cannot be silently treated as spendable.
No writes to actual Firestore or accounts; ONLY offline/emulator candidates.
"""
from deda_stage69_merge_5000_checkout_into_live_rules_READONLY_NO_DEPLOY import candidate as stage69_candidate, match_end

MARK = '// DEDA_100377_POINT01_LAB_FRAME_1000_RULES_OFFLINE_NO_DEPLOY'
WALLET = 'match /deda_diamond_gift_balances/{publicId} {'
OLD = '''      allow update: if verifiedDiamondsPersonalOwner(publicId)
        && stage66CardSpend(publicId);'''
NEW = '''      allow update: if verifiedDiamondsPersonalOwner(publicId)
        && (stage66CardSpend(publicId) || labFrameSpend(publicId));'''
RULE = r"""    // DEDA_100377_POINT01_LAB_FRAME_1000_RULES_OFFLINE_NO_DEPLOY
    function labFrameApproved(frameId) {
      return frameId in [
        'FRAME_03','FRAME_05','FRAME_06','FRAME_07','FRAME_08',
        'FRAME_09','FRAME_10','FRAME_11','FRAME_12','FRAME_13',
        'FRAME_14','FRAME_15','FRAME_16'
      ];
    }
    function labReceiptPath(publicId, frameId) {
      return /databases/$(database)/documents/deda_lab_frame_receipts/$(publicId)/frames/$(frameId);
    }
    function labOwnedPath(publicId, frameId) {
      return /databases/$(database)/documents/deda_lab_owned_frames/$(publicId)/frames/$(frameId);
    }
    function labFrameSpend(publicId) {
      let frameId = request.resource.data.get('lastLabFrameId', '');
      let receiptId = publicId + '_' + frameId;
      return labFrameApproved(frameId)
        && request.resource.data.lastLabFrameReceiptId == receiptId
        && request.resource.data.balance == resource.data.balance - 1000
        && resource.data.balance >= 1000
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly([
          'balance','updatedAt','lastLabFrameId','lastLabFrameReceiptId'
        ])
        && !exists(labReceiptPath(publicId, frameId))
        && existsAfter(labReceiptPath(publicId, frameId))
        && getAfter(labReceiptPath(publicId, frameId)).data.publicId == publicId
        && getAfter(labReceiptPath(publicId, frameId)).data.frameId == frameId
        && getAfter(labReceiptPath(publicId, frameId)).data.kind == 'lab_frame'
        && getAfter(labReceiptPath(publicId, frameId)).data.cost == 1000
        && existsAfter(labOwnedPath(publicId, frameId))
        && getAfter(labOwnedPath(publicId, frameId)).data.publicId == publicId
        && getAfter(labOwnedPath(publicId, frameId)).data.frameId == frameId
        && getAfter(labOwnedPath(publicId, frameId)).data.receiptId == receiptId;
    }
    match /deda_lab_frame_receipts/{publicId}/frames/{frameId} {
      allow get: if verifiedDiamondsPersonalOwner(publicId);
      allow list, update, delete: if false;
      allow create: if verifiedDiamondsPersonalOwner(publicId)
        && labFrameApproved(frameId)
        && request.resource.data.publicId == publicId
        && request.resource.data.frameId == frameId
        && request.resource.data.kind == 'lab_frame'
        && request.resource.data.cost == 1000
        && request.resource.data.createdAt == request.time
        && request.resource.data.keys().hasOnly([
          'publicId','frameId','kind','cost','createdAt'
        ])
        && exists(stage66WalletPath(publicId))
        && existsAfter(stage66WalletPath(publicId))
        && getAfter(stage66WalletPath(publicId)).data.balance ==
          get(stage66WalletPath(publicId)).data.balance - 1000
        && getAfter(stage66WalletPath(publicId)).data.lastLabFrameId == frameId
        && getAfter(stage66WalletPath(publicId)).data.lastLabFrameReceiptId ==
          publicId + '_' + frameId
        && existsAfter(labOwnedPath(publicId, frameId))
        && getAfter(labOwnedPath(publicId, frameId)).data.receiptId ==
          publicId + '_' + frameId;
    }
    match /deda_lab_owned_frames/{publicId}/frames/{frameId} {
      allow get: if verifiedDiamondsPersonalOwner(publicId);
      allow list, update, delete: if false;
      allow create: if verifiedDiamondsPersonalOwner(publicId)
        && labFrameApproved(frameId)
        && request.resource.data.publicId == publicId
        && request.resource.data.frameId == frameId
        && request.resource.data.receiptId == publicId + '_' + frameId
        && request.resource.data.createdAt == request.time
        && request.resource.data.keys().hasOnly([
          'publicId','frameId','receiptId','createdAt'
        ])
        && !exists(labReceiptPath(publicId, frameId))
        && existsAfter(labReceiptPath(publicId, frameId))
        && getAfter(labReceiptPath(publicId, frameId)).data.cost == 1000
        && getAfter(labReceiptPath(publicId, frameId)).data.publicId == publicId;
    }

"""

def candidate(actual_live_rules: str) -> str:
    base = stage69_candidate(actual_live_rules)
    if base.count(WALLET) != 1 or base.count(OLD) != 1:
        raise ValueError('SAFE_STOP_LAB_WALLET_STAGE69_DRIFT')
    if MARK in base or 'match /deda_lab_frame_receipts/' in base:
        raise ValueError('SAFE_STOP_LAB_EXISTS')
    wallet_at = base.index(WALLET)
    ending = match_end(base, wallet_at)
    body = base[wallet_at:ending+1]
    if body.count(OLD) != 1:
        raise ValueError('SAFE_STOP_NOT_STAGE69_SAFE_WALLET')
    result = base[:wallet_at] + RULE + base[wallet_at:ending+1].replace(
        OLD, NEW, 1) + base[ending+1:]
    if result.count(MARK) != 1 or result.count(NEW) != 1:
        raise ValueError('SAFE_STOP_LAB_BAD_RENDER')
    if result.replace(RULE, '', 1).replace(NEW, OLD, 1) != base:
        raise ValueError('SAFE_STOP_UNRELATED_FIRESTORE_RULES_CHANGE')
    return result

if __name__ == '__main__':
    raise SystemExit('NO_DEPLOY: import candidate(live_rules) only inside approved READONLY + local emulator QA')
