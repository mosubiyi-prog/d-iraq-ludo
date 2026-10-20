#!/usr/bin/env python3
"""Stage71 new owner agreement: FREE GM-only 200 IDs and free style cards.

Inject additive manager/recipient Firestore security rules into the EXACT
current published Firestore ruleset (fetched READ ONLY). Output ONLY /tmp
for disposable emulator. No change to deployed rules, wallet, user records
or private original-100 identifiers. Authenticated GM only may grant.
"""
import hashlib
import json
import os
from pathlib import Path

API='https://firebaserules.googleapis.com/v1/'
PROJECT='deda-25b88'
OUT=Path('/tmp/deda-stage71-free200-candidate.rules')
MARK='STAGE71_FREE_DUAL_200_ROLE_AND_UNIQUE_GRANT_NO_DEPLOY'
RULE="""
    // STAGE71_FREE_DUAL_200_ROLE_AND_UNIQUE_GRANT_NO_DEPLOY
    // Protected GROUP001 identities are in manager-only collection, never in
    // source code, APK or client-side static lists.
    function stage71Manager() {
      return isAdmin()
        && get(/databases/$(database)/documents/admins/$(request.auth.uid)).data.role == 'general_manager'
        && exists(/databases/$(database)/documents/users/$(request.auth.uid))
        && exists(/databases/$(database)/documents/deda_sessions/$(request.auth.uid))
        && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.accountKey ==
           get(/databases/$(database)/documents/deda_sessions/$(request.auth.uid)).data.accountKey;
    }
    function stage71CatalogPath(id) {
      return /databases/$(database)/documents/deda_stage71_admin_catalog/$(id);
    }
    function stage71RegistryPath(id) {
      return /databases/$(database)/documents/deda_stage71_granted_registry/$(id);
    }
    function stage71OriginalAccount(id) {
      return id is string && id.matches('^@DEDA-[A-Z0-9]{6}$')
        && exists(/databases/$(database)/documents/deda_share_ids/$(id))
        && get(/databases/$(database)/documents/deda_share_ids/$(id)).data.kind == 'personal'
        && get(/databases/$(database)/documents/deda_share_ids/$(id)).data.active == true;
    }
    function stage71SelfRecipient(id) {
      return signedIn()
        && exists(/databases/$(database)/documents/users/$(request.auth.uid))
        && exists(/databases/$(database)/documents/deda_sessions/$(request.auth.uid))
        && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.sharePersonalId == id
        && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.accountKey ==
           get(/databases/$(database)/documents/deda_sessions/$(request.auth.uid)).data.accountKey;
    }
    match /deda_stage71_admin_catalog/{identifier} {
      allow get, list: if stage71Manager();
      // Initial private backup import is permitted ONLY for the authenticated
      // active GENERAL MANAGER with the matching PIN session. No ordinary
      // account, employee or public client may create reserved IDs.
      allow create: if stage71Manager()
        && request.resource.data.identifier == identifier
        && request.resource.data.group in ['001','002']
        && request.resource.data.sequence is int
        && request.resource.data.sequence >= 1
        && request.resource.data.sequence <= 100
        && request.resource.data.baseColor == 'gold'
        && request.resource.data.status == 'available'
        && request.resource.data.keys().hasOnly([
          'identifier','group','sequence','baseColor','status'
        ])
        && (
          (request.resource.data.group == '001'
           && identifier.matches('^@DEDA-[A-Z0-9]{4,12}
      allow update: if stage71Manager()
        && resource.data.status == 'available'
        && request.resource.data.status in ['gifted','self_used']
        && request.resource.data.recipientOriginalId is string
        && stage71OriginalAccount(request.resource.data.recipientOriginalId)
        && (request.resource.data.status != 'self_used'
          || stage71SelfRecipient(request.resource.data.recipientOriginalId))
        && request.resource.data.grantedAt == request.time
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly([
          'status','recipientOriginalId','grantedAt'
        ])
        && !exists(stage71RegistryPath(identifier))
        && existsAfter(stage71RegistryPath(identifier))
        && getAfter(stage71RegistryPath(identifier)).data.recipientOriginalId ==
          request.resource.data.recipientOriginalId
        && getAfter(stage71RegistryPath(identifier)).data.kind ==
          request.resource.data.status
        && getAfter(stage71RegistryPath(identifier)).data.baseColor ==
          resource.data.baseColor;
    }
    match /deda_stage71_granted_registry/{identifier} {
      // Read by manager or the true original account owner; no client changes.
      allow get: if stage71Manager() || (
        signedIn() && resource.data.recipientOriginalId is string &&
        stage71SelfRecipient(resource.data.recipientOriginalId)
      );
      allow list: if stage71Manager() || (
        signedIn() && resource.data.recipientOriginalId is string &&
        stage71SelfRecipient(resource.data.recipientOriginalId)
      );
      allow update, delete: if false;
      allow create: if stage71Manager()
        && exists(stage71CatalogPath(identifier))
        && get(stage71CatalogPath(identifier)).data.status == 'available'
        && get(stage71CatalogPath(identifier)).data.identifier == identifier
        && request.resource.data.identifier == identifier
        && request.resource.data.kind in ['gifted','self_used']
        && request.resource.data.recipientOriginalId is string
        && stage71OriginalAccount(request.resource.data.recipientOriginalId)
        && (request.resource.data.kind != 'self_used'
          || stage71SelfRecipient(request.resource.data.recipientOriginalId))
        && request.resource.data.group ==
          get(stage71CatalogPath(identifier)).data.group
        && request.resource.data.baseColor ==
          get(stage71CatalogPath(identifier)).data.baseColor
        && request.resource.data.grantedByUid == request.auth.uid
        && request.resource.data.grantedAt == request.time
        && request.resource.data.keys().hasOnly([
          'identifier','recipientOriginalId','group','baseColor',
          'kind','grantedByUid','grantedAt'
        ])
        && existsAfter(stage71CatalogPath(identifier))
        && getAfter(stage71CatalogPath(identifier)).data.status ==
           request.resource.data.kind
        && getAfter(stage71CatalogPath(identifier)).data.recipientOriginalId ==
           request.resource.data.recipientOriginalId
        && getAfter(stage71CatalogPath(identifier)).data.grantedAt == request.time;
    }
    match /deda_stage71_active_identifier/{originalId} {
      // Canonical original account remains intact; switching selects only a
      // permanently owned ID. Neither foreign aliases nor invented aliases
      // can be activated by the phone.
      allow get: if stage71SelfRecipient(originalId);
      allow list, delete: if false;
      allow create, update: if stage71SelfRecipient(originalId)
        && request.resource.data.originalId == originalId
        && request.resource.data.activeId is string
        && request.resource.data.updatedAt == request.time
        && request.resource.data.keys().hasOnly([
          'originalId','activeId','updatedAt'
        ])
        && (
          request.resource.data.activeId == originalId ||
          (
            exists(stage71RegistryPath(request.resource.data.activeId))
            && get(stage71RegistryPath(request.resource.data.activeId)).data.recipientOriginalId == originalId
          )
        );
    }


"""

def add_rules(active):
    if not active.strip().startswith("rules_version = '2'"):
        raise ValueError('SAFE_STOP_RULES_VERSION')
    if MARK in active or active.count('match /databases/{database}/documents {')!=1:
        raise ValueError('SAFE_STOP_ALREADY_APPLIED_OR_DIFFERENT_ROOT')
    if 'function isGeneralManager()' not in active or 'function signedIn()' not in active:
        raise ValueError('SAFE_STOP_CANONICAL_ADMIN_ROLE_MISSING')
    # Add at root of collection match, preserving LIVE old security bytes.
    anchor='match /databases/{database}/documents {'
    candidate=active.replace(anchor,anchor+'\n'+RULE,1)
    if candidate.replace('\n'+RULE,'',1)!=active:
        raise ValueError('SAFE_STOP_UNEXPECTED_RULE_MUTATION')
    return candidate

def main():
    raw=os.getenv('DEDA_STAGE71_PRIMARY_SA') or os.getenv('DEDA_STAGE71_SECONDARY_SA')
    if not raw:
        print('SAFE_STOP_NO_GITHUB_CI_SA')
        return 2
    try:
        from google.oauth2 import service_account
        from google.auth.transport.requests import AuthorizedSession
        info=json.loads(raw)
        if info.get('type')!='service_account' or info.get('project_id')!=PROJECT:
            raise ValueError('wrong-project')
        credentials=service_account.Credentials.from_service_account_info(
          info,scopes=['https://www.googleapis.com/auth/cloud-platform'])
        http=AuthorizedSession(credentials)
        release=http.get(API+'projects/'+PROJECT+'/releases/cloud.firestore',timeout=25)
        if release.status_code!=200:
            raise ValueError('release-not-readable')
        name=release.json().get('rulesetName','')
        if not name.startswith('projects/'+PROJECT+'/rulesets/'):
            raise ValueError('wrong-ruleset')
        current=http.get(API+name,timeout=25)
        if current.status_code!=200:
            raise ValueError('ruleset-not-readable')
        files=current.json().get('source',{}).get('files',[])
        active='\n'.join(f['content'] for f in files
          if isinstance(f,dict) and isinstance(f.get('content'),str)
          and str(f.get('name','')).endswith('.rules'))
        changed=add_rules(active)
        OUT.write_text(changed)
        print('PASS_STAGE71_REAL_PUBLISHED_RULES_SHA16',
              hashlib.sha256(active.encode()).hexdigest()[:16])
        print('PASS_STAGE71_MANAGER_ONLY_CATALOG_UNIQUE_GRANTS_OFFLINE_NO_DEPLOY')
        return 0
    except Exception:
        print('SAFE_STOP_STAGE71_READ_ONLY_POLICY_INCOMPATIBLE')
        return 3

if __name__=='__main__':
    raise SystemExit(main())
))
          || (request.resource.data.group == '002'
           && identifier.matches('^@DEDA-[A-Z0-9]{6}
      allow update: if stage71Manager()
        && resource.data.status == 'available'
        && request.resource.data.status in ['gifted','self_used']
        && request.resource.data.recipientOriginalId is string
        && stage71OriginalAccount(request.resource.data.recipientOriginalId)
        && (request.resource.data.status != 'self_used'
          || stage71SelfRecipient(request.resource.data.recipientOriginalId))
        && request.resource.data.grantedAt == request.time
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly([
          'status','recipientOriginalId','grantedAt'
        ])
        && !exists(stage71RegistryPath(identifier))
        && existsAfter(stage71RegistryPath(identifier))
        && getAfter(stage71RegistryPath(identifier)).data.recipientOriginalId ==
          request.resource.data.recipientOriginalId
        && getAfter(stage71RegistryPath(identifier)).data.kind ==
          request.resource.data.status
        && getAfter(stage71RegistryPath(identifier)).data.baseColor ==
          resource.data.baseColor;
    }
    match /deda_stage71_granted_registry/{identifier} {
      // Read by manager or the true original account owner; no client changes.
      allow get: if stage71Manager() || (
        signedIn() && resource.data.recipientOriginalId is string &&
        stage71SelfRecipient(resource.data.recipientOriginalId)
      );
      allow list: if stage71Manager() || (
        signedIn() && resource.data.recipientOriginalId is string &&
        stage71SelfRecipient(resource.data.recipientOriginalId)
      );
      allow update, delete: if false;
      allow create: if stage71Manager()
        && exists(stage71CatalogPath(identifier))
        && get(stage71CatalogPath(identifier)).data.status == 'available'
        && get(stage71CatalogPath(identifier)).data.identifier == identifier
        && request.resource.data.identifier == identifier
        && request.resource.data.kind in ['gifted','self_used']
        && request.resource.data.recipientOriginalId is string
        && stage71OriginalAccount(request.resource.data.recipientOriginalId)
        && (request.resource.data.kind != 'self_used'
          || stage71SelfRecipient(request.resource.data.recipientOriginalId))
        && request.resource.data.group ==
          get(stage71CatalogPath(identifier)).data.group
        && request.resource.data.baseColor ==
          get(stage71CatalogPath(identifier)).data.baseColor
        && request.resource.data.grantedByUid == request.auth.uid
        && request.resource.data.grantedAt == request.time
        && request.resource.data.keys().hasOnly([
          'identifier','recipientOriginalId','group','baseColor',
          'kind','grantedByUid','grantedAt'
        ])
        && existsAfter(stage71CatalogPath(identifier))
        && getAfter(stage71CatalogPath(identifier)).data.status ==
           request.resource.data.kind
        && getAfter(stage71CatalogPath(identifier)).data.recipientOriginalId ==
           request.resource.data.recipientOriginalId
        && getAfter(stage71CatalogPath(identifier)).data.grantedAt == request.time;
    }
    match /deda_stage71_active_identifier/{originalId} {
      // Canonical original account remains intact; switching selects only a
      // permanently owned ID. Neither foreign aliases nor invented aliases
      // can be activated by the phone.
      allow get: if stage71SelfRecipient(originalId);
      allow list, delete: if false;
      allow create, update: if stage71SelfRecipient(originalId)
        && request.resource.data.originalId == originalId
        && request.resource.data.activeId is string
        && request.resource.data.updatedAt == request.time
        && request.resource.data.keys().hasOnly([
          'originalId','activeId','updatedAt'
        ])
        && (
          request.resource.data.activeId == originalId ||
          (
            exists(stage71RegistryPath(request.resource.data.activeId))
            && get(stage71RegistryPath(request.resource.data.activeId)).data.recipientOriginalId == originalId
          )
        );
    }


"""

def add_rules(active):
    if not active.strip().startswith("rules_version = '2'"):
        raise ValueError('SAFE_STOP_RULES_VERSION')
    if MARK in active or active.count('match /databases/{database}/documents {')!=1:
        raise ValueError('SAFE_STOP_ALREADY_APPLIED_OR_DIFFERENT_ROOT')
    if 'function isGeneralManager()' not in active or 'function signedIn()' not in active:
        raise ValueError('SAFE_STOP_CANONICAL_ADMIN_ROLE_MISSING')
    # Add at root of collection match, preserving LIVE old security bytes.
    anchor='match /databases/{database}/documents {'
    candidate=active.replace(anchor,anchor+'\n'+RULE,1)
    if candidate.replace('\n'+RULE,'',1)!=active:
        raise ValueError('SAFE_STOP_UNEXPECTED_RULE_MUTATION')
    return candidate

def main():
    raw=os.getenv('DEDA_STAGE71_PRIMARY_SA') or os.getenv('DEDA_STAGE71_SECONDARY_SA')
    if not raw:
        print('SAFE_STOP_NO_GITHUB_CI_SA')
        return 2
    try:
        from google.oauth2 import service_account
        from google.auth.transport.requests import AuthorizedSession
        info=json.loads(raw)
        if info.get('type')!='service_account' or info.get('project_id')!=PROJECT:
            raise ValueError('wrong-project')
        credentials=service_account.Credentials.from_service_account_info(
          info,scopes=['https://www.googleapis.com/auth/cloud-platform'])
        http=AuthorizedSession(credentials)
        release=http.get(API+'projects/'+PROJECT+'/releases/cloud.firestore',timeout=25)
        if release.status_code!=200:
            raise ValueError('release-not-readable')
        name=release.json().get('rulesetName','')
        if not name.startswith('projects/'+PROJECT+'/rulesets/'):
            raise ValueError('wrong-ruleset')
        current=http.get(API+name,timeout=25)
        if current.status_code!=200:
            raise ValueError('ruleset-not-readable')
        files=current.json().get('source',{}).get('files',[])
        active='\n'.join(f['content'] for f in files
          if isinstance(f,dict) and isinstance(f.get('content'),str)
          and str(f.get('name','')).endswith('.rules'))
        changed=add_rules(active)
        OUT.write_text(changed)
        print('PASS_STAGE71_REAL_PUBLISHED_RULES_SHA16',
              hashlib.sha256(active.encode()).hexdigest()[:16])
        print('PASS_STAGE71_MANAGER_ONLY_CATALOG_UNIQUE_GRANTS_OFFLINE_NO_DEPLOY')
        return 0
    except Exception:
        print('SAFE_STOP_STAGE71_READ_ONLY_POLICY_INCOMPATIBLE')
        return 3

if __name__=='__main__':
    raise SystemExit(main())
))
        )
        && !exists(
          /databases/$(database)/documents/deda_share_ids/$(identifier))
        && !exists(
          /databases/$(database)/documents/deda_owned_identifier_registry/$(identifier))
        && !exists(
          /databases/$(database)/documents/deda_owned_identifier_aliases/$(identifier))
        && !exists(stage71RegistryPath(identifier));
      allow delete: if false;
      allow update: if stage71Manager()
        && resource.data.status == 'available'
        && request.resource.data.status in ['gifted','self_used']
        && request.resource.data.recipientOriginalId is string
        && stage71OriginalAccount(request.resource.data.recipientOriginalId)
        && (request.resource.data.status != 'self_used'
          || stage71SelfRecipient(request.resource.data.recipientOriginalId))
        && request.resource.data.grantedAt == request.time
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly([
          'status','recipientOriginalId','grantedAt'
        ])
        && !exists(stage71RegistryPath(identifier))
        && existsAfter(stage71RegistryPath(identifier))
        && getAfter(stage71RegistryPath(identifier)).data.recipientOriginalId ==
          request.resource.data.recipientOriginalId
        && getAfter(stage71RegistryPath(identifier)).data.kind ==
          request.resource.data.status
        && getAfter(stage71RegistryPath(identifier)).data.baseColor ==
          resource.data.baseColor;
    }
    match /deda_stage71_granted_registry/{identifier} {
      // Read by manager or the true original account owner; no client changes.
      allow get: if stage71Manager() || (
        signedIn() && resource.data.recipientOriginalId is string &&
        stage71SelfRecipient(resource.data.recipientOriginalId)
      );
      allow list: if stage71Manager() || (
        signedIn() && resource.data.recipientOriginalId is string &&
        stage71SelfRecipient(resource.data.recipientOriginalId)
      );
      allow update, delete: if false;
      allow create: if stage71Manager()
        && exists(stage71CatalogPath(identifier))
        && get(stage71CatalogPath(identifier)).data.status == 'available'
        && get(stage71CatalogPath(identifier)).data.identifier == identifier
        && request.resource.data.identifier == identifier
        && request.resource.data.kind in ['gifted','self_used']
        && request.resource.data.recipientOriginalId is string
        && stage71OriginalAccount(request.resource.data.recipientOriginalId)
        && (request.resource.data.kind != 'self_used'
          || stage71SelfRecipient(request.resource.data.recipientOriginalId))
        && request.resource.data.group ==
          get(stage71CatalogPath(identifier)).data.group
        && request.resource.data.baseColor ==
          get(stage71CatalogPath(identifier)).data.baseColor
        && request.resource.data.grantedByUid == request.auth.uid
        && request.resource.data.grantedAt == request.time
        && request.resource.data.keys().hasOnly([
          'identifier','recipientOriginalId','group','baseColor',
          'kind','grantedByUid','grantedAt'
        ])
        && existsAfter(stage71CatalogPath(identifier))
        && getAfter(stage71CatalogPath(identifier)).data.status ==
           request.resource.data.kind
        && getAfter(stage71CatalogPath(identifier)).data.recipientOriginalId ==
           request.resource.data.recipientOriginalId
        && getAfter(stage71CatalogPath(identifier)).data.grantedAt == request.time;
    }
    match /deda_stage71_active_identifier/{originalId} {
      // Canonical original account remains intact; switching selects only a
      // permanently owned ID. Neither foreign aliases nor invented aliases
      // can be activated by the phone.
      allow get: if stage71SelfRecipient(originalId);
      allow list, delete: if false;
      allow create, update: if stage71SelfRecipient(originalId)
        && request.resource.data.originalId == originalId
        && request.resource.data.activeId is string
        && request.resource.data.updatedAt == request.time
        && request.resource.data.keys().hasOnly([
          'originalId','activeId','updatedAt'
        ])
        && (
          request.resource.data.activeId == originalId ||
          (
            exists(stage71RegistryPath(request.resource.data.activeId))
            && get(stage71RegistryPath(request.resource.data.activeId)).data.recipientOriginalId == originalId
          )
        );
    }


"""

def add_rules(active):
    if not active.strip().startswith("rules_version = '2'"):
        raise ValueError('SAFE_STOP_RULES_VERSION')
    if MARK in active or active.count('match /databases/{database}/documents {')!=1:
        raise ValueError('SAFE_STOP_ALREADY_APPLIED_OR_DIFFERENT_ROOT')
    if 'function isGeneralManager()' not in active or 'function signedIn()' not in active:
        raise ValueError('SAFE_STOP_CANONICAL_ADMIN_ROLE_MISSING')
    # Add at root of collection match, preserving LIVE old security bytes.
    anchor='match /databases/{database}/documents {'
    candidate=active.replace(anchor,anchor+'\n'+RULE,1)
    if candidate.replace('\n'+RULE,'',1)!=active:
        raise ValueError('SAFE_STOP_UNEXPECTED_RULE_MUTATION')
    return candidate

def main():
    raw=os.getenv('DEDA_STAGE71_PRIMARY_SA') or os.getenv('DEDA_STAGE71_SECONDARY_SA')
    if not raw:
        print('SAFE_STOP_NO_GITHUB_CI_SA')
        return 2
    try:
        from google.oauth2 import service_account
        from google.auth.transport.requests import AuthorizedSession
        info=json.loads(raw)
        if info.get('type')!='service_account' or info.get('project_id')!=PROJECT:
            raise ValueError('wrong-project')
        credentials=service_account.Credentials.from_service_account_info(
          info,scopes=['https://www.googleapis.com/auth/cloud-platform'])
        http=AuthorizedSession(credentials)
        release=http.get(API+'projects/'+PROJECT+'/releases/cloud.firestore',timeout=25)
        if release.status_code!=200:
            raise ValueError('release-not-readable')
        name=release.json().get('rulesetName','')
        if not name.startswith('projects/'+PROJECT+'/rulesets/'):
            raise ValueError('wrong-ruleset')
        current=http.get(API+name,timeout=25)
        if current.status_code!=200:
            raise ValueError('ruleset-not-readable')
        files=current.json().get('source',{}).get('files',[])
        active='\n'.join(f['content'] for f in files
          if isinstance(f,dict) and isinstance(f.get('content'),str)
          and str(f.get('name','')).endswith('.rules'))
        changed=add_rules(active)
        OUT.write_text(changed)
        print('PASS_STAGE71_REAL_PUBLISHED_RULES_SHA16',
              hashlib.sha256(active.encode()).hexdigest()[:16])
        print('PASS_STAGE71_MANAGER_ONLY_CATALOG_UNIQUE_GRANTS_OFFLINE_NO_DEPLOY')
        return 0
    except Exception:
        print('SAFE_STOP_STAGE71_READ_ONLY_POLICY_INCOMPATIBLE')
        return 3

if __name__=='__main__':
    raise SystemExit(main())
