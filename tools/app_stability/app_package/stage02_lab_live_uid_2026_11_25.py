"""Live Auth-only check for one pre-provisioned lab account, no signup/data writes."""
import hashlib
import json
import os
import urllib.error
import urllib.parse
import urllib.request

from stage01_lab_gate_2026_11_25 import validate, PROJECT, NUMBER, PACKAGE

UID = 'PLmG06Uhhheef1hDE2MLfX6DEpg2'
EMAIL = 'deda-qa-test@example.com'
FINGERPRINT = '705e70c89ef87374a56ed7cf1f31fc408050935b04a9b4120b8b11685872a323'


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def main():
    stage = 'config'
    try:
        data = json.loads(os.environ['LAB_CONFIG'])
        canonical = json.dumps(data, sort_keys=True, separators=(',', ':')).encode()
        if hashlib.sha256(canonical).hexdigest() != FINGERPRINT:
            raise ValueError('config fingerprint')
        validate(data, PACKAGE)
        key = data['client'][0]['api_key'][0]['current_key']
        opener = urllib.request.build_opener(NoRedirect(), urllib.request.ProxyHandler({}))
        base = 'https://identitytoolkit.googleapis.com/v1/'
        query = '?' + urllib.parse.urlencode({'key': key})

        def request(path, body=None):
            if path not in ('projects', 'accounts:signInWithPassword', 'accounts:lookup'):
                raise ValueError('endpoint forbidden')
            req = urllib.request.Request(base + path + query,
                data=None if body is None else json.dumps(body).encode(),
                headers={'Content-Type': 'application/json', 'Accept': 'application/json'},
                method='GET' if body is None else 'POST')
            with opener.open(req, timeout=20) as response:
                if response.status != 200:
                    raise ValueError('unexpected status')
                return json.loads(response.read(131072))

        stage = 'metadata'
        meta = request('projects')
        domains = meta.get('authorizedDomains', [])
        if PROJECT + '.firebaseapp.com' not in domains or any('deda-25b88' in str(x).lower() for x in domains):
            raise ValueError('lab domain mismatch')
        if 'projectId' in meta and str(meta['projectId']) not in (PROJECT, NUMBER):
            raise ValueError('lab project mismatch')

        stage = 'credential'
        password = os.environ.get('LAB_PASSWORD', '')
        if len(password) < 16:
            raise ValueError('dedicated test credential missing or weak')

        def login():
            response = request('accounts:signInWithPassword',
                {'email': EMAIL, 'password': password, 'returnSecureToken': True})
            if response.get('localId') != UID or response.get('email') != EMAIL:
                raise ValueError('unexpected UID or email')
            token = response.get('idToken')
            if not isinstance(token, str) or not token:
                raise ValueError('missing ID token')
            # Server-side lookup validates the issued token against the same lab.
            users = request('accounts:lookup', {'idToken': token}).get('users', [])
            if len(users) != 1 or users[0].get('localId') != UID or users[0].get('email') != EMAIL:
                raise ValueError('server account mismatch')
            if 'password' not in [p.get('providerId') for p in users[0].get('providerUserInfo', [])]:
                raise ValueError('password provider missing')
            return response['localId']

        stage = 'first_signin'
        first = login()
        print('PASS_LAB_FIRST_SIGNIN_PINNED_UID_AND_SERVER_LOOKUP')
        stage = 'second_independent_signin'
        second = login()
        if first != second or second != UID:
            raise ValueError('UID drift')
        print('PASS_LAB_SECOND_SIGNIN_SAME_PINNED_UID_AND_SERVER_LOOKUP')
        print('AUTH_ONLY_NO_SIGNUP_NO_FIRESTORE_NO_DEVICE_NO_FULL_APP_RUNTIME')
    except Exception as exc:
        # Do not print credential, tokens, request URL, or response payload.
        code = exc.code if isinstance(exc, urllib.error.HTTPError) else ''
        print('BLOCK_STAGE02_LIVE_UID', stage, type(exc).__name__, code)
        raise SystemExit(1) from None


if __name__ == '__main__':
    main()
