"""Prepare a core-only OFFLINE Phase 01 probe in an empty Flutter scaffold."""
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ANDROID = 'http://schemas.android.com/apk/res/android'
TOOLS = 'http://schemas.android.com/tools'
ET.register_namespace('android', ANDROID)
ET.register_namespace('tools', TOOLS)


def render_probe(gate, key):
    # The key is written to the disposable tree only, never printed or committed.
    dart_key = json.dumps(key)
    dart = gate.PROBE.replace("bool matchesLab(FirebaseOptions options) =>", f'''const labOptions = FirebaseOptions(
    apiKey: {dart_key}, appId: '{gate.APP_ID}', messagingSenderId: '{gate.NUMBER}',
    projectId: '{gate.PROJECT}', storageBucket: '{gate.BUCKET}');

bool matchesLab(FirebaseOptions options) =>
    options.apiKey == labOptions.apiKey &&''').replace(
        'final app = await Firebase.initializeApp();', '''if (Firebase.apps.isNotEmpty) {
      throw StateError('Unexpected pre-initialized Firebase app');
    }
    final app = await Firebase.initializeApp(options: labOptions)\n        .timeout(const Duration(seconds: 5));''')
    gate.require(dart != gate.PROBE and 'Firebase.initializeApp(options: labOptions)' in dart,
                 'PROBE_ENTRY_ANCHOR_CHANGED')
    return dart


def prepare_probe(root, config, gate):
    root = Path(root).resolve()
    repo = Path(gate.ROOT).resolve()
    gate.require(root.is_dir() and root != repo and repo not in root.parents and root not in repo.parents,
                 'DISPOSABLE_SCAFFOLD_REQUIRED')
    gate.validate(config, gate.PACKAGE)
    gradle = root/'android/app/build.gradle.kts'
    text = gradle.read_text()
    gate.require(re.findall(r'applicationId\s*=\s*"([^"]+)"', text) == [gate.PACKAGE], 'LAB_GRADLE_PACKAGE_REQUIRED')
    gate.require('google-services' not in text and not list(root.rglob('google-services.json')),
                 'NATIVE_FIREBASE_CONFIG_NOT_ALLOWED')
    pub = root/'pubspec.yaml'
    original = pub.read_text()
    gate.require(re.search(r'^name:\s*uiddevice\s*$', original, re.M) and
                 not re.search(r'firebase|firestore|google_sign_in|dependency_overrides', original, re.I),
                 'FRESH_CORE_ONLY_SCAFFOLD_REQUIRED')
    main = root/'lib/main.dart'
    gate.require(main.is_file() and len(list((root/'lib').rglob('*.dart'))) == 1,
                 'FRESH_PROBE_ENTRY_REQUIRED')
    manifests = list((root/'android/app/src').rglob('AndroidManifest.xml'))
    primary = root/'android/app/src/main/AndroidManifest.xml'
    gate.require(primary in manifests and len(manifests) <= 3, 'MANIFEST_LAYOUT_CHANGED')
    parsed = [(p, ET.parse(p)) for p in manifests]
    for p, tree in parsed:
        doc = tree.getroot()
        for elem in list(doc):
            if elem.tag.startswith('uses-permission') and elem.get('{'+ANDROID+'}name') in (
                    'android.permission.INTERNET', 'android.permission.ACCESS_NETWORK_STATE'):
                doc.remove(elem)
        if p == primary:
            for name in ('android.permission.INTERNET', 'android.permission.ACCESS_NETWORK_STATE'):
                ET.SubElement(doc, 'uses-permission', {'{'+ANDROID+'}name':name, '{'+TOOLS+'}node':'remove'})
            app = doc.find('application')
            gate.require(app is not None, 'ANDROID_APPLICATION_REQUIRED')
            ET.SubElement(app, 'provider', {'{'+ANDROID+'}name':'com.google.firebase.provider.FirebaseInitProvider',
                                            '{'+TOOLS+'}node':'remove'})
    dart = render_probe(gate, config['client'][0]['api_key'][0]['current_key'])
    for p, tree in parsed:
        tree.write(p, encoding='utf-8', xml_declaration=True)
    pub.write_text('name: uiddevice\npublish_to: none\nversion: 0.1.0+1\nenvironment:\n  sdk: ">=3.6.0 <4.0.0"\ndependencies:\n  flutter:\n    sdk: flutter\n  firebase_core: 3.15.2\ndev_dependencies:\n  flutter_test:\n    sdk: flutter\nflutter:\n  uses-material-design: true\n')
    main.write_text(dart)
    return {'package': gate.PACKAGE, 'core_only': True, 'network_permission_removal_requested': True,
            'native_auto_init_removal_requested': True, 'merged_manifest_verified': False,
            'live_connection_verified': False, 'auth_allowed': False, 'full_app_launch_allowed': False}
