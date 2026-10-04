from pathlib import Path

path = Path('firestore.rules')
text = path.read_text(encoding='utf-8')
marker = '// DEDA_SOCIAL_FIRST_REQUEST_GET_HOTFIX_100269'
if marker in text:
    print('social first-request get hotfix already applied')
    raise SystemExit(0)

old = '''      allow read: if signedIn()
        && resource.data.members is list
        && (
          currentUserHasShareId(resource.data.requesterPublicId)
          || currentUserHasShareId(resource.data.recipientPublicId)
        );'''

new = '''      // DEDA_SOCIAL_FIRST_REQUEST_GET_HOTFIX_100269
      // A first friend request checks the deterministic relationship document
      // before creating it. Permit that exact GET when the document does not
      // exist yet; existing relationships remain readable only by either side.
      allow get: if signedIn()
        && (
          !exists(/databases/$(database)/documents/deda_friendships/$(pairKey))
          || (
            resource.data.members is list
            && (
              currentUserHasShareId(resource.data.requesterPublicId)
              || currentUserHasShareId(resource.data.recipientPublicId)
            )
          )
        );

      // Collection queries stay restricted to the current user's relations.
      allow list: if signedIn()
        && resource.data.members is list
        && (
          currentUserHasShareId(resource.data.requesterPublicId)
          || currentUserHasShareId(resource.data.recipientPublicId)
        );'''

if text.count(old) != 1:
    raise SystemExit(f'expected one stabilized friendship read block, found {text.count(old)}')

text = text.replace(old, new, 1)
path.write_text(text, encoding='utf-8')
print('applied first friend request GET hotfix 100269')
