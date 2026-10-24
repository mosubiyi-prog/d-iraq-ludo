"""GET-only current Firebase Rules snapshot, private local merge; NO DEPLOY.

No Firestore document API, no ruleset creation, no release update, no policy
contents/keys in logs/artifacts. Credentials are scoped to firebase.readonly.
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import sys

from merge import ROOT, GuardError, digest, merge

PROJECT = 'deda-25b88'
API = 'https://firebaserules.googleapis.com/v1/'
RELEASE = f'projects/{PROJECT}/releases/cloud.firestore'
SCOPE = 'https://www.googleapis.com/auth/firebase.readonly'


class ReadOnlyRules:
    def __init__(self, http):
        self.http = http
        self.gets = 0

    def get(self, name):
        if name != RELEASE and not re.fullmatch(r'projects/' + PROJECT + r'/rulesets/[A-Za-z0-9_-]{1,160}', name):
            raise GuardError('endpoint-not-readonly-rules-allowlist')
        response = self.http.get(API + name, timeout=30, allow_redirects=False)
        self.gets += 1
        if response.status_code != 200:
            raise GuardError('rules-read-http-denied')
        try:
            return response.json()
        except Exception:
            raise GuardError('rules-response-not-json') from None


def snapshot(reader):
    before = reader.get(RELEASE)
    name = before.get('rulesetName', '')
    if not re.fullmatch(r'projects/' + PROJECT + r'/rulesets/[A-Za-z0-9_-]{1,160}', name):
        raise GuardError('unexpected-ruleset-name')
    data = reader.get(name)
    files = data.get('source', {}).get('files', [])
    if len(files) != 1 or not isinstance(files[0], dict) or not isinstance(files[0].get('content'), str) or not str(files[0].get('name', '')).endswith('.rules'):
        raise GuardError('one-rules-file-required')
    text = files[0]['content']
    after = reader.get(RELEASE)
    if after.get('rulesetName') != name:
        raise GuardError('release-changed-during-read')
    return text, {'rulesetName': name, 'releaseUpdateTime': before.get('updateTime'),
                  'readAtUTC': datetime.now(timezone.utc).isoformat()}


def session_reader():
    raw = os.getenv('DEDA_RULES_PRIMARY_SA') or os.getenv('DEDA_RULES_SECONDARY_SA')
    if not raw:
        raise GuardError('existing-ci-credential-missing')
    try:
        info = json.loads(raw)
        if info.get('type') != 'service_account' or info.get('project_id') != PROJECT or info.get('token_uri') != 'https://oauth2.googleapis.com/token':
            raise GuardError('credential-project-or-token-endpoint-mismatch')
        from google.oauth2 import service_account
        from google.auth.transport.requests import AuthorizedSession
        credential = service_account.Credentials.from_service_account_info(info, scopes=[SCOPE])
        return ReadOnlyRules(AuthorizedSession(credential))
    except GuardError:
        raise
    except Exception:
        raise GuardError('credential-unavailable') from None


def prepare(reader, private_dir, public_dir):
    private_dir = private_dir.resolve()
    public_dir = public_dir.resolve()
    if (private_dir == ROOT or ROOT in private_dir.parents or private_dir in ROOT.parents or
            public_dir == ROOT or ROOT in public_dir.parents or public_dir in ROOT.parents or
            public_dir == private_dir or private_dir in public_dir.parents or public_dir in private_dir.parents):
        raise GuardError('unsafe-private-output-location')
    if private_dir.exists() and any(private_dir.iterdir()):
        raise GuardError('private-output-must-be-empty')
    if public_dir.exists() and any(public_dir.iterdir()):
        raise GuardError('public-output-must-be-empty')
    active, metadata = snapshot(reader)
    candidate = (ROOT / 'tools/app_stability/progress_archive/firestore.rules').read_text()
    merged, proof = merge(active, candidate)
    private_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(private_dir, 0o700)
    for name, text in {'original.private.rules': active, 'candidate.private.rules': merged,
                       'release.private.json': json.dumps(metadata)}.items():
        target = private_dir / name
        target.write_text(text)
        os.chmod(target, 0o600)
    (private_dir / 'firebase.json').write_text(json.dumps({
        'firestore': {'rules': 'candidate.private.rules'},
        'emulators': {'firestore': {'host': '127.0.0.1', 'port': 8080},
                      'ui': {'enabled': False}, 'singleProjectMode': True}}))
    public_dir.mkdir(parents=True, exist_ok=True)
    report = {**proof, 'status': 'prepared-not-tested', 'readScope': SCOPE,
              'readAtUTC': metadata['readAtUTC'], 'releaseUpdateTime': metadata['releaseUpdateTime'],
              'rulesetNameSHA256': digest(metadata['rulesetName']), 'rulesApiGets': reader.gets,
              'productionDocumentApiCalls': 0, 'productionMutationCalls': 0,
              'privateSourceUploaded': False}
    (public_dir / 'rules-compat-report.json').write_text(json.dumps(report, indent=2) + '\n')
    return report


def verify_after(reader, private_dir, public_dir):
    metadata = json.loads((private_dir / 'release.private.json').read_text())
    report_path = public_dir / 'rules-compat-report.json'
    report = json.loads(report_path.read_text())
    if report.get('status') != 'emulator-passed-awaiting-release-verify':
        raise GuardError('emulator-result-not-passed')
    if (digest((private_dir / 'original.private.rules').read_text()) != report.get('originalSHA256') or
            digest((private_dir / 'candidate.private.rules').read_text()) != report.get('candidateSHA256') or
            digest(metadata['rulesetName']) != report.get('rulesetNameSHA256')):
        raise GuardError('review-files-changed-after-snapshot')
    current = reader.get(RELEASE)
    if current.get('rulesetName') != metadata['rulesetName']:
        raise GuardError('release-changed-during-emulator-check')
    report.update({'status': 'verified', 'sameReleaseBeforeAfter': True,
                   'verifiedAtUTC': datetime.now(timezone.utc).isoformat(),
                   'rulesApiGets': report['rulesApiGets'] + reader.gets})
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--private-dir', type=Path, required=True)
    parser.add_argument('--public-dir', type=Path, required=True)
    parser.add_argument('--verify-after', action='store_true')
    args = parser.parse_args()
    try:
        reader = session_reader()
        report = verify_after(reader, args.private_dir, args.public_dir) if args.verify_after else prepare(reader, args.private_dir, args.public_dir)
        print(json.dumps({'status': report['status'], 'originalSHA256': report['originalSHA256'],
                          'candidateSHA256': report['candidateSHA256'], 'scope': SCOPE}))
        return 0
    except GuardError as error:
        print('RULES_COMPAT_STOP', str(error))
        return 2
    except Exception:
        print('RULES_COMPAT_STOP', 'credential-api-or-private-output-failure')
        return 2


if __name__ == '__main__':
    sys.exit(main())
