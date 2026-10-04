from pathlib import Path

path = Path('firestore.rules')
text = path.read_text(encoding='utf-8')
marker = '// DEDA_SOCIAL_RULES_100269'
if marker in text:
    print('DEDA social rules 100269 already present')
    raise SystemExit(0)

anchor = '  }\n}\n'
index = text.rfind(anchor)
if index < 0:
    raise SystemExit('firestore final database anchor not found')

block = r'''

    // DEDA_SOCIAL_RULES_100269
    // Personal social profile only. No place-owner/place data is stored here.
    match /deda_social_profiles/{publicId} {
      allow get: if signedIn();
      allow list: if false;

      allow create: if signedIn()
        && request.resource.data.publicId == publicId
        && request.resource.data.ownerUid == request.auth.uid
        && currentUserHasShareId(publicId)
        && request.resource.data.displayName is string
        && request.resource.data.displayName.size() >= 1
        && request.resource.data.displayName.size() <= 80
        && request.resource.data.avatarStyle is int
        && request.resource.data.avatarStyle >= 0
        && request.resource.data.avatarStyle <= 5
        && request.resource.data.frameStyle is int
        && request.resource.data.frameStyle >= 0
        && request.resource.data.frameStyle <= 5
        && request.resource.data.backgroundStyle is int
        && request.resource.data.backgroundStyle >= 0
        && request.resource.data.backgroundStyle <= 5
        && request.resource.data.level is int
        && request.resource.data.level >= 1
        && request.resource.data.level <= 999
        && request.resource.data.badges is list
        && request.resource.data.badges.size() <= 12
        && request.resource.data.createdAt == request.time
        && request.resource.data.updatedAt == request.time
        && request.resource.data.keys().hasOnly([
          'publicId', 'ownerUid', 'displayName', 'avatarStyle', 'frameStyle',
          'backgroundStyle', 'level', 'badges', 'createdAt', 'updatedAt'
        ]);

      allow update: if signedIn()
        && resource.data.ownerUid == request.auth.uid
        && request.resource.data.ownerUid == resource.data.ownerUid
        && request.resource.data.publicId == resource.data.publicId
        && request.resource.data.publicId == publicId
        && currentUserHasShareId(publicId)
        && request.resource.data.displayName is string
        && request.resource.data.displayName.size() >= 1
        && request.resource.data.displayName.size() <= 80
        && request.resource.data.avatarStyle is int
        && request.resource.data.avatarStyle >= 0
        && request.resource.data.avatarStyle <= 5
        && request.resource.data.frameStyle is int
        && request.resource.data.frameStyle >= 0
        && request.resource.data.frameStyle <= 5
        && request.resource.data.backgroundStyle is int
        && request.resource.data.backgroundStyle >= 0
        && request.resource.data.backgroundStyle <= 5
        && request.resource.data.level is int
        && request.resource.data.level >= 1
        && request.resource.data.level <= 999
        && request.resource.data.badges is list
        && request.resource.data.badges.size() <= 12
        && request.resource.data.updatedAt == request.time
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly([
          'displayName', 'avatarStyle', 'frameStyle', 'backgroundStyle',
          'level', 'badges', 'updatedAt'
        ]);

      allow delete: if signedIn() && resource.data.ownerUid == request.auth.uid;
    }

    match /deda_friendships/{pairKey} {
      // Queries are constrained by members array-contains current uid.
      allow read: if signedIn()
        && resource.data.members is list
        && request.auth.uid in resource.data.members;

      allow create: if signedIn()
        && request.resource.data.pairKey == pairKey
        && request.resource.data.members is list
        && request.resource.data.members.size() == 2
        && request.auth.uid in request.resource.data.members
        && request.resource.data.requesterUid == request.auth.uid
        && request.resource.data.recipientUid is string
        && request.resource.data.recipientUid != request.auth.uid
        && request.resource.data.recipientUid in request.resource.data.members
        && request.resource.data.requesterPublicId is string
        && request.resource.data.recipientPublicId is string
        && request.resource.data.requesterName is string
        && request.resource.data.recipientName is string
        && request.resource.data.status == 'pending'
        && request.resource.data.createdAt == request.time
        && request.resource.data.updatedAt == request.time
        && request.resource.data.keys().hasOnly([
          'pairKey', 'members', 'requesterUid', 'recipientUid',
          'requesterPublicId', 'recipientPublicId', 'requesterName',
          'recipientName', 'status', 'createdAt', 'updatedAt'
        ]);

      allow update: if signedIn()
        && resource.data.status == 'pending'
        && resource.data.recipientUid == request.auth.uid
        && request.resource.data.pairKey == resource.data.pairKey
        && request.resource.data.members == resource.data.members
        && request.resource.data.requesterUid == resource.data.requesterUid
        && request.resource.data.recipientUid == resource.data.recipientUid
        && request.resource.data.requesterPublicId == resource.data.requesterPublicId
        && request.resource.data.recipientPublicId == resource.data.recipientPublicId
        && request.resource.data.requesterName == resource.data.requesterName
        && request.resource.data.recipientName == resource.data.recipientName
        && request.resource.data.status in ['accepted', 'rejected']
        && request.resource.data.respondedAt == request.time
        && request.resource.data.updatedAt == request.time
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly([
          'status', 'respondedAt', 'updatedAt'
        ]);

      allow delete: if signedIn()
        && resource.data.members is list
        && request.auth.uid in resource.data.members;
    }
'''

text = text[:index] + block + '\n' + text[index:]
path.write_text(text, encoding='utf-8')
print('applied DEDA social Firestore rules 100269')
