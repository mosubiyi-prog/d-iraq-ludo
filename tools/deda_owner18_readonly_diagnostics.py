"""Read ONLY repair-related live state; never writes accounts, funds or rules."""
import json
import os
from pathlib import Path

from google.oauth2 import service_account
from google.auth.transport.requests import AuthorizedSession

PROJECT = 'deda-25b88'
raw = os.getenv('DEDA_STAGE69_PRIMARY_SA') or os.getenv('DEDA_STAGE69_SECONDARY_SA')
if not raw:
    raise SystemExit('BLOCKED: existing Firebase diagnostic credential unavailable')
info = json.loads(raw)
assert info.get('project_id') == PROJECT
cred = service_account.Credentials.from_service_account_info(
    info, scopes=['https://www.googleapis.com/auth/cloud-platform'])
http = AuthorizedSession(cred)
base = f'https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents'
out = Path('owner18-diagnostics')
out.mkdir(exist_ok=True)
report = {}
for collection in ['deda_stage71_admin_catalog', 'deda_stage71_granted_registry']:
    response = http.get(f'{base}/{collection}?pageSize=300', timeout=30)
    response.raise_for_status()
    data = response.json()
    docs = data.get('documents', [])
    assert not data.get('nextPageToken'), 'catalog scan requires pagination'
    report[collection] = {'count': len(docs)}
    if collection.endswith('catalog'):
        groups = {}
        for d in docs:
            g = d.get('fields', {}).get('group', {}).get('stringValue', 'MISSING')
            groups[g] = groups.get(g, 0) + 1
        report[collection]['groups'] = groups
for path in [
    'deda_stage71_granted_registry/@DEDA-IRAQI',
    'deda_stage71_active_identifier/@DEDA-AQPYXJ',
    'deda_diamond_gift_balances/@DEDA-AQPYXJ',
]:
    r = http.get(f'{base}/{path}', timeout=30)
    if r.status_code == 404:
        report[path] = {'exists': False}
        continue
    r.raise_for_status()
    fields = r.json().get('fields', {})
    # Restrict emitted data to explicitly discussed ID grant/activation/wallet.
    allowed = {'identifier', 'recipientOriginalId', 'kind', 'group',
               'baseColor', 'originalId', 'activeId', 'balance', 'publicId'}
    report[path] = {k: v for k, v in fields.items() if k in allowed}
def related_fields(path):
    result = http.get(f'{base}/{path}', timeout=30)
    if result.status_code == 404:
        return None
    if result.status_code != 200:
        raise RuntimeError('Related identity diagnostic HTTP ' + str(result.status_code))
    return result.json().get('fields', {})

def value(fields, key, kind='stringValue'):
    return (fields or {}).get(key, {}).get(kind)

route = related_fields('deda_share_ids/@DEDA-AQPYXJ')
owner_uid = value(route, 'ownerUid')
if owner_uid:
    profile = related_fields('users/' + owner_uid)
    session = related_fields('deda_sessions/' + owner_uid)
    key = value(profile, 'accountKey')
    report['discussed_owner_identity_checks'] = {
        'profile_exists': profile is not None,
        'session_matches_account': bool(key and key == value(session, 'accountKey')),
        'profile_original_id_matches': value(profile, 'sharePersonalId') == '@DEDA-AQPYXJ',
        'route_active': value(route, 'active', 'booleanValue') is True,
    }
    if key:
        gm = related_fields('deda_gm_personal_diamond_wallets/' + key)
        report['existing_manager_personal_wallet'] = {
            'exists': gm is not None, 'balance': value(gm, 'balance', 'integerValue')}
for collection, identifier in [
    ('deda_stage74_id_gift_receipts','@DEDA-IRAQI'),
    ('deda_public_active_aliases','@DEDA-AQPYXJ'),
    ('deda_public_alias_routes','@DEDA-IRAQI'),
]:
    fields = related_fields(collection + '/' + identifier)
    report[collection + '_discussed_identifier'] = {
        'exists': fields is not None,
        'originalId': value(fields, 'originalId'),
        'activeId': value(fields, 'activeId'),
        'received': bool(value(fields, 'receivedAt', 'timestampValue')),
    }

rulesbase = 'https://firebaserules.googleapis.com/v1'
r = http.get(f'{rulesbase}/projects/{PROJECT}/releases/cloud.firestore', timeout=30)
r.raise_for_status()
name = r.json()['rulesetName']
assert name.startswith(f'projects/{PROJECT}/rulesets/')
r = http.get(f'{rulesbase}/{name}', timeout=30)
r.raise_for_status()
rules = '\n'.join(x['content'] for x in r.json()['source']['files'])
(out / 'active.rules').write_text(rules)
report['rules'] = {'frame_receipts': 'match /deda_lab_frame_receipts/' in rules,
                   'admin200': 'match /deda_stage71_admin_catalog/' in rules}
(out / 'report.json').write_text(json.dumps(report, indent=2, ensure_ascii=False))
print(json.dumps(report, indent=2, ensure_ascii=False))
print('READ ONLY: no Firestore writes, no deployment, no account or wallet changes')
