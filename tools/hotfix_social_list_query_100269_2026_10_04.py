from pathlib import Path

path = Path('firestore.rules')
text = path.read_text(encoding='utf-8')
marker = '// DEDA_SOCIAL_LIST_QUERY_HOTFIX_100269'
if marker in text:
    print('social list-query hotfix already applied')
    raise SystemExit(0)

old = '''      // Collection queries stay restricted to the current user's relations.
      allow list: if signedIn()
        && resource.data.members is list
        && (
          currentUserHasShareId(resource.data.requesterPublicId)
          || currentUserHasShareId(resource.data.recipientPublicId)
        );'''

new = '''      // DEDA_SOCIAL_LIST_QUERY_HOTFIX_100269
      // Collection queries are allowed only when each candidate relation
      // contains the signed-in account's stable personal DEDA ID. The app
      // queries with members array-contains that exact stable ID.
      allow list: if signedIn()
        && exists(/databases/$(database)/documents/users/$(request.auth.uid))
        && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.keys().hasAny(['sharePersonalId'])
        && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.sharePersonalId is string
        && resource.data.members is list
        && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.sharePersonalId in resource.data.members;'''

if text.count(old) != 1:
    raise SystemExit(f'expected one first-request list block, found {text.count(old)}')

text = text.replace(old, new, 1)
path.write_text(text, encoding='utf-8')
print('applied DEDA social list-query hotfix 100269')
