from pathlib import Path

path = Path('firestore.rules')
text = path.read_text(encoding='utf-8')
marker = '// DEDA_SOCIAL_ADMIN_DIAMONDS_100270'
if marker in text:
    print('100270 social/admin diamond rules already applied')
    raise SystemExit(0)

old_list = '''      // DEDA_SOCIAL_LIST_QUERY_HOTFIX_100269
      // Collection queries are allowed only when each candidate relation
      // contains the signed-in account's stable personal DEDA ID. The app
      // queries with members array-contains that exact stable ID.
      allow list: if signedIn()
        && exists(/databases/$(database)/documents/users/$(request.auth.uid))
        && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.keys().hasAny(['sharePersonalId'])
        && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.sharePersonalId is string
        && resource.data.members is list
        && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.sharePersonalId in resource.data.members;'''
new_list = '''      // DEDA_SOCIAL_LIST_QUERY_HOTFIX_100269
      // DEDA_SOCIAL_QUERY_RULES_100270
      // 100270 uses two explicit equality queries: requesterPublicId == me
      // and recipientPublicId == me. Firestore can prove ownership directly
      // from either query without exposing anyone else's relationship list.
      allow list: if signedIn()
        && exists(/databases/$(database)/documents/users/$(request.auth.uid))
        && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.keys().hasAny(['sharePersonalId'])
        && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.sharePersonalId is string
        && (
          resource.data.requesterPublicId ==
            get(/databases/$(database)/documents/users/$(request.auth.uid)).data.sharePersonalId
          || resource.data.recipientPublicId ==
            get(/databases/$(database)/documents/users/$(request.auth.uid)).data.sharePersonalId
        );'''
if text.count(old_list) != 1:
    raise SystemExit(f'expected one 100269 list-query rule block, found {text.count(old_list)}')
text = text.replace(old_list, new_list, 1)

block = r'''

    // DEDA_SOCIAL_ADMIN_DIAMONDS_100270
    // A protected one-million-diamond administrative gift pool. This is not
    // the personal rewarded-ad wallet and cannot be opened by normal users.
    match /deda_admin_diamond_wallets/{adminUid} {
      allow get: if isGeneralManager() && request.auth.uid == adminUid;
      allow list: if false;

      allow create: if isGeneralManager()
        && request.auth.uid == adminUid
        && request.resource.data.adminUid == adminUid
        && request.resource.data.initialBalance == 1000000
        && request.resource.data.balance == 1000000
        && request.resource.data.createdAt == request.time
        && request.resource.data.updatedAt == request.time
        && request.resource.data.keys().hasOnly([
          'adminUid', 'initialBalance', 'balance', 'createdAt', 'updatedAt'
        ]);

      // The client may spend from the protected pool but can never refill it.
      allow update: if isGeneralManager()
        && request.auth.uid == adminUid
        && request.resource.data.adminUid == resource.data.adminUid
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

    // Remote gift balance keyed by the stable personal DEDA ID. A manager may
    // only increase it; the owner may only decrease it when spending gifts.
    match /deda_diamond_gift_balances/{publicId} {
      allow get: if isGeneralManager() || currentUserHasShareId(publicId);
      allow list: if false;

      allow create: if isGeneralManager()
        && request.resource.data.publicId == publicId
        && request.resource.data.balance is int
        && request.resource.data.balance > 0
        && request.resource.data.createdAt == request.time
        && request.resource.data.updatedAt == request.time
        && request.resource.data.keys().hasOnly([
          'publicId', 'balance', 'createdAt', 'updatedAt'
        ]);

      allow update: if request.resource.data.publicId == resource.data.publicId
        && request.resource.data.publicId == publicId
        && request.resource.data.balance is int
        && request.resource.data.balance >= 0
        && request.resource.data.updatedAt == request.time
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly([
          'balance', 'updatedAt'
        ])
        && (
          (isGeneralManager()
            && request.resource.data.balance >= resource.data.balance)
          || (currentUserHasShareId(publicId)
            && request.resource.data.balance <= resource.data.balance)
        );

      allow delete: if false;
    }

    // Immutable administrative audit records for every diamond gift.
    match /deda_diamond_gifts/{giftId} {
      allow get, list: if isGeneralManager();
      allow create: if isGeneralManager()
        && request.resource.data.giftId == giftId
        && request.resource.data.adminUid == request.auth.uid
        && request.resource.data.adminName is string
        && request.resource.data.adminName.size() >= 1
        && request.resource.data.targetPublicId is string
        && request.resource.data.targetPublicId.size() >= 8
        && request.resource.data.targetName is string
        && request.resource.data.amount is int
        && request.resource.data.amount > 0
        && request.resource.data.createdAt == request.time
        && request.resource.data.keys().hasOnly([
          'giftId', 'adminUid', 'adminName', 'targetPublicId',
          'targetName', 'amount', 'createdAt'
        ]);
      allow update, delete: if false;
    }
'''

anchor = '  }\n}\n'
index = text.rfind(anchor)
if index < 0:
    raise SystemExit('firestore final database anchor missing')
text = text[:index] + block + '\n' + text[index:]
path.write_text(text, encoding='utf-8')
print('applied 100270 social query + protected admin diamond rules')
