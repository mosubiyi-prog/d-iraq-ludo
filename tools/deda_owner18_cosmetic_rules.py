"""Targeted native cosmetic account backup. Existing purchase trust is kept.

Does not authorize balance increases, change accounts, IDs, maps or tasks.
Candidate is tested before release. No rule deployment without --deploy.
"""
import hashlib
import json
import sys
from pathlib import Path

MARKER = '// DEDA_OWNER18_NATIVE_COSMETIC_ACCOUNT_BACKUP'
RULE = '''
    // DEDA_OWNER18_NATIVE_COSMETIC_ACCOUNT_BACKUP
    // The existing native shop is client-authoritative for legacy cosmetics.
    // This backs up that same per-account inventory; it is not a payment
    // attestation and never grants a currency balance or premium identifier.
    function nativeCosmeticOwner(publicId) {
      return verifiedDiamondsPersonalOwner(publicId) || (signedIn()
        && publicId.matches('^@DEDA-[A-Z0-9]{6}$')
        && exists(/databases/$(database)/documents/users/$(request.auth.uid))
        && exists(/databases/$(database)/documents/deda_sessions/$(request.auth.uid))
        && exists(/databases/$(database)/documents/deda_share_ids/$(publicId))
        && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.accountKey
          == get(/databases/$(database)/documents/deda_sessions/$(request.auth.uid)).data.accountKey
        && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.get('sharePersonalId', publicId) == publicId
        && get(/databases/$(database)/documents/deda_share_ids/$(publicId)).data.ownerUid == request.auth.uid
        && get(/databases/$(database)/documents/deda_share_ids/$(publicId)).data.kind == 'personal'
        && get(/databases/$(database)/documents/deda_share_ids/$(publicId)).data.active == true);
    }
    function nativeCosmeticsValid(publicId) {
      let d = request.resource.data;
      return d.originalId == publicId
        && d.updatedAt == request.time
        && d.keys().hasOnly(['originalId','ownedStyles','ownedFrames','pendingFrames',
          'activeBadges','avatar','frame','background','updatedAt'])
        && d.get('ownedStyles', []) is list
        && d.get('ownedStyles', []).size() <= 12
        && d.get('ownedStyles', []).hasOnly(['frame_0','frame_1','frame_2',
          'frame_3','frame_4','frame_5','badge_member','badge_spark','badge_elite',
          'badge_royal','badge_season1','badge_legendary'])
        && d.get('activeBadges', []) is list
        && d.get('activeBadges', []).size() <= 1
        && d.get('activeBadges', []).hasOnly(d.get('ownedStyles', []))
        && d.get('ownedFrames', []) is list
        && d.get('ownedFrames', []).size() <= 13
        && d.get('ownedFrames', []).hasOnly(['FRAME_03','FRAME_05','FRAME_06',
          'FRAME_07','FRAME_08','FRAME_09','FRAME_10','FRAME_11','FRAME_12',
          'FRAME_13','FRAME_14','FRAME_15','FRAME_16'])
        && d.get('pendingFrames', []) is list
        && d.get('pendingFrames', []).size() <= 13
        && d.get('pendingFrames', []).hasOnly(['FRAME_03','FRAME_05','FRAME_06',
          'FRAME_07','FRAME_08','FRAME_09','FRAME_10','FRAME_11','FRAME_12',
          'FRAME_13','FRAME_14','FRAME_15','FRAME_16'])
        && d.get('avatar',0) is int && d.get('avatar',0) >= 0 && d.get('avatar',0) <= 8
        && d.get('frame',0) is int && d.get('frame',0) >= 0 && d.get('frame',0) <= 18
        && d.get('background',0) is int && d.get('background',0) >= 0 && d.get('background',0) <= 8;
    }
    match /deda_native_account_cosmetics/{publicId} {
      allow get: if nativeCosmeticOwner(publicId);
      allow list, delete: if false;
      allow create: if nativeCosmeticOwner(publicId) && nativeCosmeticsValid(publicId);
      allow update: if nativeCosmeticOwner(publicId) && nativeCosmeticsValid(publicId)
        && request.resource.data.originalId == resource.data.originalId
        && request.resource.data.get('ownedStyles', []).hasAll(resource.data.get('ownedStyles', []))
        && request.resource.data.get('ownedFrames', []).hasAll(resource.data.get('ownedFrames', []));
    }
'''

def candidate(active):
    if MARKER in active:
        return active
    updated = active
    a = updated.index('    match /deda_social_profiles/{publicId} {')
    b = updated.index('    match /deda_friendships/', a)
    social = updated[a:b]
    for field, maximum in [('avatarStyle', 8), ('frameStyle', 18), ('backgroundStyle', 8)]:
        old = f'request.resource.data.{field} <= 5'
        assert social.count(old) == 2, 'unexpected public appearance validator'
        social = social.replace(old, f'request.resource.data.{field} <= {maximum}')
    updated = updated[:a] + social + updated[b:]
    old_owner = '&& route.data.ownerUid == request.auth.uid;'
    assert updated.count(old_owner) == 1, 'unexpected public alias owner validator'
    updated = updated.replace(old_owner,
        '&& verifiedDiamondsPersonalOwner(originalId);', 1)
    end = updated.rfind('\n  }')
    assert end > 0 and updated[end:].lstrip().startswith('}\n}')
    return updated[:end] + '\n' + RULE + updated[end:]

def main():
    root = Path('owner18-diagnostics')
    active = (root/'active.rules').read_text()
    proposed = candidate(active)
    target = Path('/tmp/deda-owner18-cosmetics.rules')
    if '--deploy' not in sys.argv:
        target.write_text(proposed)
        print('Prepared cosmetic-only candidate. No deployment or document writes.')
        return
    assert target.read_text() == proposed
    assert Path('/tmp/deda-owner18-cosmetics-tests-passed').read_text().strip() == hashlib.sha256(proposed.encode()).hexdigest()
    # Use only the explicit existing service-account credential, never metadata.
    import os
    from google.oauth2 import service_account
    from google.auth.transport.requests import AuthorizedSession
    raw = os.getenv('DEDA_STAGE69_PRIMARY_SA') or os.getenv('DEDA_STAGE69_SECONDARY_SA')
    info = json.loads(raw)
    assert info['project_id'] == 'deda-25b88'
    cred = service_account.Credentials.from_service_account_info(info,
        scopes=['https://www.googleapis.com/auth/cloud-platform'])
    http = AuthorizedSession(cred)
    base = 'https://firebaserules.googleapis.com/v1'
    release = f'{base}/projects/deda-25b88/releases/cloud.firestore'
    def api(method,url,**kwargs):
        r=http.request(method,url,timeout=35,**kwargs);r.raise_for_status();return r.json()
    old = api('GET', release)
    oldname = old['rulesetName']
    original = api('GET', f'{base}/{oldname}')
    current = '\n'.join(x['content'] for x in original['source']['files'])
    assert current == active, 'live policy changed since candidate tests'
    if current == proposed:
        print('Cosmetic account backup policy already matches tested candidate')
        return
    created = api('POST', f'{base}/projects/deda-25b88/rulesets',
        json={'source':{'files':[{'name':'firestore.rules','content':proposed}]}})
    newname = created['name']
    assert api('GET',release)['rulesetName'] == oldname
    body = lambda name: {'name':'projects/deda-25b88/releases/cloud.firestore',
        'release':{'name':'projects/deda-25b88/releases/cloud.firestore','rulesetName':name}}
    try:
        api('PATCH',release,params={'updateMask':'rulesetName'},json=body(newname))
        assert api('GET',release)['rulesetName'] == newname
    except Exception:
        if api('GET',release)['rulesetName'] == newname:
            api('PATCH',release,params={'updateMask':'rulesetName'},json=body(oldname))
        raise
    (root/'cosmetic-policy-release.json').write_text(json.dumps({'before':oldname,
        'after':newname,'candidateSha256':hashlib.sha256(proposed.encode()).hexdigest()},indent=2))
    print('Tested cosmetic-only policy released; no user, balance or identifier documents changed')

if __name__ == '__main__':
    main()
