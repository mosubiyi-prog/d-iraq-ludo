"""Read only the discussed public ID projections and active rule source."""
import json
import os
from pathlib import Path
from google.oauth2 import service_account
from google.auth.transport.requests import AuthorizedSession

raw = os.getenv('DEDA_STAGE69_PRIMARY_SA') or os.getenv('DEDA_STAGE69_SECONDARY_SA')
info = json.loads(raw)
assert info['project_id'] == 'deda-25b88'
credentials = service_account.Credentials.from_service_account_info(
    info, scopes=['https://www.googleapis.com/auth/cloud-platform'])
http = AuthorizedSession(credentials)
out = Path('six-identity-readonly'); out.mkdir(exist_ok=True)
base = 'https://firestore.googleapis.com/v1/projects/deda-25b88/databases/(default)/documents/'
report = {}
for path in ['deda_public_active_aliases/@DEDA-AQPYXJ',
             'deda_public_alias_routes/@DEDA-IRAQI',
             'deda_stage71_active_identifier/@DEDA-AQPYXJ']:
    response = http.get(base + path, timeout=30)
    if response.status_code == 404:
        report[path] = {'exists': False}; continue
    response.raise_for_status(); fields = response.json().get('fields', {})
    allowed = ['originalId','activeId','aliasId','baseColor']
    report[path] = {'exists': True, 'fieldNames': sorted(fields),
                   'values': {key: fields[key] for key in allowed if key in fields}}
rulesbase = 'https://firebaserules.googleapis.com/v1'
response = http.get(rulesbase + '/projects/deda-25b88/releases/cloud.firestore', timeout=30)
response.raise_for_status(); name = response.json()['rulesetName']
assert name.startswith('projects/deda-25b88/rulesets/')
response = http.get(rulesbase + '/' + name, timeout=30); response.raise_for_status()
rules = '\n'.join(item['content'] for item in response.json()['source']['files'])
(out/'active.rules').write_text(rules)
(out/'report.json').write_text(json.dumps(report, indent=2))
print(json.dumps(report, indent=2))
print('READ ONLY: no Firestore document writes, wallets, login changes or deployment')
