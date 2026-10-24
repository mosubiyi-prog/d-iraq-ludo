"""Prepare only a disposable flutter-create harness, never the DEDA app tree."""
import argparse
import hashlib
import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MODULES = (
    'deda_session_transition_gate.dart', 'deda_session_flow_prototype.dart',
    'deda_session_principal_tracker.dart', 'deda_owner_session_firebase_port.dart',
    'deda_legacy_progress_capture.dart', 'deda_progress_evidence_store.dart',
    'deda_progress_backup_coordinator.dart', 'deda_progress_backup_runtime.dart',
)
FAMILIES = ('firebase_core', 'firebase_auth', 'cloud_firestore', 'shared_preferences')


def versions(lock):
    result = {}
    package = None
    for line in lock.read_text().splitlines():
        match = re.fullmatch(r'  ([a-z0-9_]+):', line)
        if match:
            package = match[1]
        match = re.fullmatch(r'    version: "([^"]+)"', line)
        if match and package:
            result[package] = match[1]
    return result


def prepare(harness, baseline):
    harness, baseline = harness.resolve(), baseline.resolve()
    if harness == ROOT or ROOT in harness.parents:
        raise ValueError('harness must be outside the repository')
    if not (harness / '.metadata').is_file():
        raise ValueError('requires a fresh flutter-create harness')
    manifest = harness / 'android/app/src/main/AndroidManifest.xml'
    if not manifest.is_file() or (harness / 'android/app/google-services.json').exists():
        raise ValueError('requires isolated Android without Firebase config')
    gradle = harness / 'android/app/build.gradle.kts'
    if not gradle.is_file() or 'dev.deda.qa.deda_transport_qa' not in gradle.read_text():
        raise ValueError('requires the isolated QA application ID')
    if (harness / 'native-source-manifest.json').exists():
        raise ValueError('refusing to overwrite an already prepared harness')
    lock = versions(baseline / 'pubspec.lock')
    wanted = {name: version for name, version in lock.items() if name.startswith(FAMILIES)}
    if not all(name in wanted for name in FAMILIES):
        raise ValueError('baseline is missing required pinned transports')
    spec = ["name: deda_transport_qa", "publish_to: none", "version: 0.0.1+1",
            "environment:", "  sdk: '>=3.4.0 <4.0.0'", "dependencies:",
            "  flutter:", "    sdk: flutter"]
    spec += [f'  {name}: {wanted[name]}' for name in FAMILIES]
    spec += ['dependency_overrides:']
    spec += [f'  {name}: {version}' for name, version in sorted(wanted.items())]
    spec += ['flutter:', '  uses-material-design: true']
    (harness / 'pubspec.yaml').write_text('\n'.join(spec) + '\n')
    # These files belong to flutter-create's disposable counter app only.
    (harness / 'analysis_options.yaml').unlink(missing_ok=True)
    shutil.rmtree(harness / 'test', ignore_errors=True)
    copied = {}
    for name in MODULES:
        source = ROOT / 'lib' / name
        shutil.copy2(source, harness / 'lib' / name)
        copied['lib/' + name] = hashlib.sha256(source.read_bytes()).hexdigest()
    shutil.copy2(Path(__file__).with_name('main.dart'), harness / 'lib/main.dart')
    copied['lib/main.dart'] = hashlib.sha256((harness / 'lib/main.dart').read_bytes()).hexdigest()
    text = manifest.read_text()
    text = text.replace('<application', '<application android:usesCleartextTraffic="true"', 1)
    if 'android.permission.INTERNET' not in text:
        text = text.replace('<application', '<uses-permission android:name="android.permission.INTERNET"/>\n    <application', 1)
    manifest.write_text(text)
    (harness / 'native-source-manifest.json').write_text(json.dumps({
        'scope': 'disposable native plugin harness, not DEDA APK',
        'projectId': 'demo-deda-progress-archive', 'files': copied,
        'pinnedTransportVersions': wanted,
    }, indent=2) + '\n')


def verify(harness, baseline):
    expected = {k: v for k, v in versions(baseline / 'pubspec.lock').items() if k.startswith(FAMILIES)}
    actual = versions(harness / 'pubspec.lock')
    if any(actual.get(name) != version for name, version in expected.items()):
        raise ValueError('native plugin versions drifted from the baseline')
    print(json.dumps({'pinnedTransportPackages': len(expected), 'verified': True}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('harness', type=Path)
    parser.add_argument('baseline', type=Path)
    parser.add_argument('--verify', action='store_true')
    args = parser.parse_args()
    if args.verify:
        verify(args.harness, args.baseline)
    else:
        prepare(args.harness, args.baseline)
