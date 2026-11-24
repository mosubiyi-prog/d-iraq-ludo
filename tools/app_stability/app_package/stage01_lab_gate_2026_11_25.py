"""Stage 01: offline lab configuration gate; never calls Firebase or Auth.
The full application remains on hold. A separate core-only probe is the only
permitted phase-01 entry; its SDK initialization is not a connectivity test.
The uploaded JSON stays outside the repository. No APK, signing or deployment.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
import unittest
import sys
from stage01_lab_prepare_probe_2026_11_25 import prepare_probe

ROOT = Path(__file__).resolve().parents[3]

PROJECT = 'deda-qa-uid-lab-20261108'
NUMBER = '180856267046'
PACKAGE = 'com.deda.qa.uiddevice'
APP_ID = '1:180856267046:android:4c5670efc62169738121e7'
BUCKET = PROJECT + '.firebasestorage.app'
SHA1 = 'd77cc54940b41dbf567445987a1dc9ef2412eb39'
PRODUCTION = 'deda-25b88'
PRODUCTION_PACKAGE = 'com.diraq.ludo.d_iraq_ludo'


def require(ok, reason):
    if not ok:
        raise ValueError(reason)


def validate(data, build_package):
    require(build_package == PACKAGE, 'LAB_PACKAGE_REQUIRED')
    require(PRODUCTION not in json.dumps(data).lower(), 'PRODUCTION_CONFIG_BLOCKED')
    info = data['project_info']
    require((info['project_id'], info['project_number'], info['storage_bucket']) ==
            (PROJECT, NUMBER, BUCKET), 'LAB_PROJECT_MISMATCH')
    clients = data['client']
    require(len(clients) == 1, 'LAB_CLIENT_NOT_EXCLUSIVE')
    c = clients[0]
    ci = c['client_info']
    require(ci['mobilesdk_app_id'] == APP_ID and
            ci['android_client_info']['package_name'] == PACKAGE, 'LAB_APP_MISMATCH')
    oauth = c['oauth_client']
    require(all(x['client_id'].startswith(NUMBER + '-') and
                x['client_id'].endswith('.apps.googleusercontent.com') for x in oauth),
            'LAB_OAUTH_PROJECT_MISMATCH')
    android = [x for x in oauth if x['client_type'] == 1]
    web = [x for x in oauth if x['client_type'] == 3]
    require(len(android) == 1 and len(web) == 1 and
            android[0]['android_info']['package_name'] == PACKAGE and
            android[0]['android_info']['certificate_hash'].lower() == SHA1,
            'LAB_OAUTH_OR_CERTIFICATE_MISMATCH')
    keys = c['api_key']
    require(len(keys) == 1 and re.fullmatch(r'AIza[\w-]{35}', keys[0]['current_key']),
            'LAB_API_KEY_FORMAT_MISMATCH')
    return {'project': PROJECT, 'package': PACKAGE, 'app_id': APP_ID,
            'sha1_registered': True, 'configuration_validated_offline': True,
            'full_app_launch_allowed': False, 'auth_allowed': False,
            'live_connection_verified': False}


# Independent core-only probe: no DEDA startup, FirebaseAuth, Firestore,
# local account reads, or fallback to a different project. A disposable Android
# scaffold must contain only firebase_core and the approved native config.
# The Android package and native config must be verified before any build/run.
PROBE = '''import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

bool matchesLab(FirebaseOptions options) =>
    options.projectId == 'deda-qa-uid-lab-20261108' &&
    options.appId == '1:180856267046:android:4c5670efc62169738121e7' &&
    options.messagingSenderId == '180856267046' &&
    options.storageBucket == 'deda-qa-uid-lab-20261108.firebasestorage.app';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var status = 'BLOCKED: phase 01 lab configuration';
  try {
    final app = await Firebase.initializeApp();
    if (matchesLab(app.options) &&
        Firebase.apps.length == 1 && Firebase.apps.every((a) => matchesLab(a.options))) {
      status = 'LAB CONFIG MATCHED - AUTH AND FULL APP HELD';
    }
  } catch (_) {
    // Fail closed. Never start DEDA or try another Firebase project.
  }
  runApp(MaterialApp(home: Scaffold(body: Center(child: Text(status)))));
}
'''


class Tests(unittest.TestCase):
    def setUp(self):
        self.data = {'project_info': {'project_id': PROJECT, 'project_number': NUMBER,
                     'storage_bucket': BUCKET}, 'client': [{'client_info': {
                     'mobilesdk_app_id': APP_ID, 'android_client_info': {'package_name': PACKAGE}},
                     'oauth_client': [{'client_id': NUMBER+'-fake.apps.googleusercontent.com',
                     'client_type': 1, 'android_info': {'package_name': PACKAGE,
                     'certificate_hash': SHA1}}, {'client_id': NUMBER+'-fake2.apps.googleusercontent.com',
                     'client_type': 3}], 'api_key': [{'current_key': 'AIza'+'x'*35}]}]}

    def test_valid(self):
        self.assertFalse(validate(self.data, PACKAGE)['auth_allowed'])
        self.assertFalse(validate(self.data, PACKAGE)['full_app_launch_allowed'])

    def test_reject_production_package(self):
        with self.assertRaises(ValueError): validate(self.data, PRODUCTION_PACKAGE)

    def test_reject_wrong_project_and_nested_production(self):
        for value in ('other-project', PRODUCTION):
            data = copy.deepcopy(self.data); data['project_info']['project_id'] = value
            with self.assertRaises(ValueError): validate(data, PACKAGE)
        data = copy.deepcopy(self.data); data['extra'] = PRODUCTION
        with self.assertRaises(ValueError): validate(data, PACKAGE)

    def test_reject_wrong_client_and_cert(self):
        for field, value in [('package_name', PRODUCTION_PACKAGE), ('certificate_hash', '0'*40)]:
            data = copy.deepcopy(self.data)
            data['client'][0]['oauth_client'][0]['android_info'][field] = value
            with self.assertRaises(ValueError): validate(data, PACKAGE)
        data = copy.deepcopy(self.data); data['client'].append(data['client'][0])
        with self.assertRaises(ValueError): validate(data, PACKAGE)

    def test_reject_wrong_app_and_key(self):
        data = copy.deepcopy(self.data); data['client'][0]['client_info']['mobilesdk_app_id'] = 'wrong'
        with self.assertRaises(ValueError): validate(data, PACKAGE)
        data = copy.deepcopy(self.data); data['client'][0]['api_key'] = []
        with self.assertRaises(ValueError): validate(data, PACKAGE)

    def test_probe_is_core_only(self):
        for marker in ('FirebaseAuth', 'signIn', 'Firestore', 'DedaApp', PRODUCTION):
            self.assertNotIn(marker, PROBE)
        self.assertEqual(PROBE.count('Firebase.initializeApp()'), 1)
        self.assertIn('AUTH AND FULL APP HELD', PROBE)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--config', type=Path)
    parser.add_argument('--build-package')
    parser.add_argument('--prepare-probe', type=Path, help='Existing disposable Flutter scaffold; offline only')
    args = parser.parse_args()
    if args.prepare_probe and not args.config:
        parser.error('--prepare-probe requires --config')
    if args.self_test:
        result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Tests))
        if not result.wasSuccessful(): raise SystemExit(1)
    if args.config:
        raw = args.config.read_bytes()
        report = validate(json.loads(raw), args.build_package)
        report['config_sha256'] = hashlib.sha256(raw).hexdigest()
        if args.prepare_probe:
            report['probe'] = prepare_probe(args.prepare_probe, json.loads(raw), sys.modules[__name__])
        print(json.dumps(report))
    elif not args.self_test:
        parser.error('provide --config and --build-package, or --self-test')


if __name__ == '__main__':
    main()
