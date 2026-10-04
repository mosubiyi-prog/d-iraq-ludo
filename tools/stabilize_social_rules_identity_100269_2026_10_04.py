from pathlib import Path

path = Path('firestore.rules')
text = path.read_text(encoding='utf-8')
marker = '// DEDA_SOCIAL_STABLE_RULES_100269'
if marker in text:
    print('DEDA stable social rules already applied')
    raise SystemExit(0)
if '// DEDA_SOCIAL_RULES_100269' not in text:
    raise SystemExit('base social rules 100269 must be applied first')

old_profile_update = '''      allow update: if signedIn()
        && resource.data.ownerUid == request.auth.uid
        && request.resource.data.ownerUid == resource.data.ownerUid
        && request.resource.data.publicId == resource.data.publicId'''
new_profile_update = '''      allow update: if signedIn()
        && currentUserHasShareId(publicId)
        && request.resource.data.ownerUid == request.auth.uid
        && request.resource.data.publicId == resource.data.publicId'''
if text.count(old_profile_update) != 1:
    raise SystemExit('social profile update identity anchor missing')
text = text.replace(old_profile_update, new_profile_update, 1)

old_profile_diff = '''        && request.resource.data.diff(resource.data).affectedKeys().hasOnly([
          'displayName', 'avatarStyle', 'frameStyle', 'backgroundStyle',
          'level', 'badges', 'updatedAt'
        ]);

      allow delete: if signedIn() && resource.data.ownerUid == request.auth.uid;'''
new_profile_diff = '''        && request.resource.data.diff(resource.data).affectedKeys().hasOnly([
          'ownerUid', 'displayName', 'avatarStyle', 'frameStyle', 'backgroundStyle',
          'level', 'badges', 'updatedAt'
        ]);

      allow delete: if signedIn() && currentUserHasShareId(publicId);'''
if text.count(old_profile_diff) != 1:
    raise SystemExit('social profile diff/delete anchor missing')
text = text.replace(old_profile_diff, new_profile_diff, 1)

old_read = '''      allow read: if signedIn()
        && resource.data.members is list
        && request.auth.uid in resource.data.members;'''
new_read = '''      allow read: if signedIn()
        && resource.data.members is list
        && (
          currentUserHasShareId(resource.data.requesterPublicId)
          || currentUserHasShareId(resource.data.recipientPublicId)
        );'''
if text.count(old_read) != 1:
    raise SystemExit('friendship read identity anchor missing')
text = text.replace(old_read, new_read, 1)

old_create = '''        && request.resource.data.members is list
        && request.resource.data.members.size() == 2
        && request.auth.uid in request.resource.data.members
        && request.resource.data.requesterUid == request.auth.uid
        && request.resource.data.recipientUid is string
        && request.resource.data.recipientUid != request.auth.uid
        && request.resource.data.recipientUid in request.resource.data.members
        && request.resource.data.requesterPublicId is string
        && request.resource.data.recipientPublicId is string'''
new_create = '''        && request.resource.data.members is list
        && request.resource.data.members.size() == 2
        && request.resource.data.requesterPublicId is string
        && request.resource.data.recipientPublicId is string
        && request.resource.data.requesterPublicId != request.resource.data.recipientPublicId
        && request.resource.data.requesterUid == request.resource.data.requesterPublicId
        && request.resource.data.recipientUid == request.resource.data.recipientPublicId
        && request.resource.data.requesterPublicId in request.resource.data.members
        && request.resource.data.recipientPublicId in request.resource.data.members
        && currentUserHasShareId(request.resource.data.requesterPublicId)'''
if text.count(old_create) != 1:
    raise SystemExit('friendship create identity anchor missing')
text = text.replace(old_create, new_create, 1)

old_update = '''      allow update: if signedIn()
        && resource.data.status == 'pending'
        && resource.data.recipientUid == request.auth.uid'''
new_update = '''      allow update: if signedIn()
        && resource.data.status == 'pending'
        && currentUserHasShareId(resource.data.recipientPublicId)'''
if text.count(old_update) != 1:
    raise SystemExit('friendship update identity anchor missing')
text = text.replace(old_update, new_update, 1)

old_delete = '''      allow delete: if signedIn()
        && resource.data.members is list
        && request.auth.uid in resource.data.members;'''
new_delete = '''      allow delete: if signedIn()
        && resource.data.members is list
        && (
          currentUserHasShareId(resource.data.requesterPublicId)
          || currentUserHasShareId(resource.data.recipientPublicId)
        );'''
if text.count(old_delete) != 1:
    raise SystemExit('friendship delete identity anchor missing')
text = text.replace(old_delete, new_delete, 1)

text = text.replace('// DEDA_SOCIAL_RULES_100269',
                    '// DEDA_SOCIAL_RULES_100269\n    ' + marker, 1)
path.write_text(text, encoding='utf-8')
print('applied stable DEDA ID Firestore social rules 100269')
