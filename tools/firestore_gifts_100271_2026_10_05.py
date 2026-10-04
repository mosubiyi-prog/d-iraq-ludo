from pathlib import Path

path = Path('firestore.rules')
text = path.read_text(encoding='utf-8')
marker = '// DEDA_GIFTS_RULES_100271'
if marker in text:
    print('100271 gift rules already applied')
    raise SystemExit(0)

start_marker = '''    // Remote gift balance keyed by the stable personal DEDA ID. A manager may
    // only increase it; the owner may only decrease it when spending gifts.
'''
start = text.find(start_marker)
if start < 0:
    raise SystemExit('100270 remote gift rules block not found')

final_anchor = '  }\n}\n'
end = text.rfind(final_anchor)
if end < 0 or end <= start:
    raise SystemExit('firestore database closing anchor not found')

block = r'''    // DEDA_GIFTS_RULES_100271
    function isGeneralManagerPersonalAccount(accountKey) {
      return signedIn()
        && accountKey is string
        && sameAccount(accountKey)
        && exists(
          /databases/$(database)/documents/admin_entry_access/$(accountKey)
        )
        && get(
          /databases/$(database)/documents/admin_entry_access/$(accountKey)
        ).data.accountKey == accountKey
        && get(
          /databases/$(database)/documents/admin_entry_access/$(accountKey)
        ).data.active == true
        && get(
          /databases/$(database)/documents/admin_entry_access/$(accountKey)
        ).data.status == 'active'
        && get(
          /databases/$(database)/documents/admin_entry_access/$(accountKey)
        ).data.accessType == 'general_manager_gateway'
        && get(
          /databases/$(database)/documents/admin_entry_access/$(accountKey)
        ).data.allowedRole == 'general_manager';
    }

    function diamondGiftBefore(giftId) {
      return get(
        /databases/$(database)/documents/deda_diamond_gifts/$(giftId)
      ).data;
    }

    function diamondGiftAfter(giftId) {
      return getAfter(
        /databases/$(database)/documents/deda_diamond_gifts/$(giftId)
      ).data;
    }

    // Personal one-million testing wallet for the authorized general-manager
    // DEDA phone account. It is completely separate from the admin gift pool.
    match /deda_gm_personal_diamond_wallets/{accountKey} {
      allow get: if isGeneralManagerPersonalAccount(accountKey);
      allow list: if false;

      allow create: if isGeneralManagerPersonalAccount(accountKey)
        && request.resource.data.accountKey == accountKey
        && request.resource.data.initialBalance == 1000000
        && request.resource.data.balance == 1000000
        && request.resource.data.createdAt == request.time
        && request.resource.data.updatedAt == request.time
        && request.resource.data.keys().hasOnly([
          'accountKey', 'initialBalance', 'balance', 'createdAt', 'updatedAt'
        ]);

      allow update: if isGeneralManagerPersonalAccount(accountKey)
        && request.resource.data.accountKey == resource.data.accountKey
        && request.resource.data.initialBalance == resource.data.initialBalance
        && request.resource.data.initialBalance == 1000000
        && request.resource.data.balance is int
        && request.resource.data.balance >= 0
        && request.resource.data.balance <= resource.data.balance
        && request.resource.data.updatedAt == request.time
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly([
          'balance', 'updatedAt'
        ]);

      allow delete: if false;
    }

    // Claimed gift balance. Normal users can freely DECREASE their own balance
    // when buying style items. An INCREASE is allowed only in the same atomic
    // transaction that changes one matching gift from pending -> received.
    match /deda_diamond_gift_balances/{publicId} {
      allow get: if isGeneralManager() || currentUserHasShareId(publicId);
      allow list: if false;

      allow create: if currentUserHasShareId(publicId)
        && request.resource.data.publicId == publicId
        && request.resource.data.balance is int
        && request.resource.data.balance > 0
        && request.resource.data.lastClaimGiftId is string
        && request.resource.data.lastClaimGiftId.size() > 0
        && request.resource.data.createdAt == request.time
        && request.resource.data.updatedAt == request.time
        && request.resource.data.keys().hasOnly([
          'publicId', 'balance', 'lastClaimGiftId', 'createdAt', 'updatedAt'
        ])
        && diamondGiftBefore(request.resource.data.lastClaimGiftId).status == 'pending'
        && diamondGiftBefore(request.resource.data.lastClaimGiftId).targetPublicId == publicId
        && diamondGiftAfter(request.resource.data.lastClaimGiftId).status == 'received'
        && diamondGiftAfter(request.resource.data.lastClaimGiftId).targetPublicId == publicId
        && request.resource.data.balance ==
          diamondGiftBefore(request.resource.data.lastClaimGiftId).amount;

      allow update: if currentUserHasShareId(publicId)
        && request.resource.data.publicId == resource.data.publicId
        && request.resource.data.publicId == publicId
        && request.resource.data.balance is int
        && request.resource.data.balance >= 0
        && request.resource.data.updatedAt == request.time
        && (
          (
            // Spending already received diamonds: owner may only decrease.
            request.resource.data.balance <= resource.data.balance
            && request.resource.data.diff(resource.data).affectedKeys().hasOnly([
              'balance', 'updatedAt'
            ])
          )
          || (
            // Claim: exactly one pending gift funds exactly this increase.
            request.resource.data.balance > resource.data.balance
            && request.resource.data.lastClaimGiftId is string
            && request.resource.data.lastClaimGiftId.size() > 0
            && request.resource.data.balance == resource.data.balance +
              diamondGiftBefore(request.resource.data.lastClaimGiftId).amount
            && diamondGiftBefore(request.resource.data.lastClaimGiftId).status == 'pending'
            && diamondGiftBefore(request.resource.data.lastClaimGiftId).targetPublicId == publicId
            && diamondGiftAfter(request.resource.data.lastClaimGiftId).status == 'received'
            && diamondGiftAfter(request.resource.data.lastClaimGiftId).targetPublicId == publicId
            && request.resource.data.diff(resource.data).affectedKeys().hasOnly([
              'balance', 'lastClaimGiftId', 'updatedAt'
            ])
          )
        );

      allow delete: if false;
    }

    // Permanent gift ledger. General manager creates only pending admin gifts;
    // the target owner can read them and perform only pending -> received.
    match /deda_diamond_gifts/{giftId} {
      allow get, list: if isGeneralManager()
        || currentUserHasShareId(resource.data.targetPublicId);

      allow create: if isGeneralManager()
        && request.resource.data.giftId == giftId
        && request.resource.data.sourceType == 'admin'
        && request.resource.data.adminUid == request.auth.uid
        && request.resource.data.adminName is string
        && request.resource.data.adminName.size() >= 1
        && request.resource.data.senderLabel == 'إدارة DEDA'
        && request.resource.data.targetPublicId is string
        && request.resource.data.targetPublicId.size() >= 8
        && request.resource.data.targetName is string
        && request.resource.data.amount is int
        && request.resource.data.amount > 0
        && request.resource.data.reason is string
        && request.resource.data.reason.size() >= 1
        && request.resource.data.reason.size() <= 220
        && request.resource.data.status == 'pending'
        && request.resource.data.createdAt == request.time
        && request.resource.data.keys().hasOnly([
          'giftId', 'sourceType', 'adminUid', 'adminName', 'senderLabel',
          'targetPublicId', 'targetName', 'amount', 'reason', 'status',
          'createdAt'
        ]);

      allow update: if currentUserHasShareId(resource.data.targetPublicId)
        && resource.data.giftId == giftId
        && resource.data.status == 'pending'
        && request.resource.data.status == 'received'
        && request.resource.data.claimedAt == request.time
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly([
          'status', 'claimedAt'
        ])
        && (
          (
            exists(
              /databases/$(database)/documents/deda_diamond_gift_balances/$(resource.data.targetPublicId)
            )
            && getAfter(
              /databases/$(database)/documents/deda_diamond_gift_balances/$(resource.data.targetPublicId)
            ).data.balance == get(
              /databases/$(database)/documents/deda_diamond_gift_balances/$(resource.data.targetPublicId)
            ).data.balance + resource.data.amount
            && getAfter(
              /databases/$(database)/documents/deda_diamond_gift_balances/$(resource.data.targetPublicId)
            ).data.lastClaimGiftId == giftId
          )
          || (
            !exists(
              /databases/$(database)/documents/deda_diamond_gift_balances/$(resource.data.targetPublicId)
            )
            && getAfter(
              /databases/$(database)/documents/deda_diamond_gift_balances/$(resource.data.targetPublicId)
            ).data.balance == resource.data.amount
            && getAfter(
              /databases/$(database)/documents/deda_diamond_gift_balances/$(resource.data.targetPublicId)
            ).data.lastClaimGiftId == giftId
          )
        );

      allow delete: if false;
    }
'''

text = text[:start] + block + '\n' + text[end:]
path.write_text(text, encoding='utf-8')
print('applied DEDA 100271 secure pending gift + GM personal wallet rules')
