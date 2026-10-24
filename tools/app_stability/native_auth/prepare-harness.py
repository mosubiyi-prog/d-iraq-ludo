"""Runtime-bound original DedaPinAuth in a disposable native app; no production config."""
import argparse
import hashlib
import importlib.util
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('native_transport_tools',
    ROOT / 'tools/app_stability/native_transport/prepare-harness.py')
transport = importlib.util.module_from_spec(spec)
spec.loader.exec_module(transport)
PROJECT = 'demo-deda-live-progress-compat'
PACKAGE = 'dev.deda.qa.deda_auth_qa'


def prepare(harness, baseline):
    harness, baseline = harness.resolve(), baseline.resolve()
    if harness == ROOT or ROOT in harness.parents:
        raise ValueError('harness must be outside repository')
    if not (harness / '.metadata').is_file():
        raise ValueError('fresh flutter-create harness required')
    app = harness / 'android/app'
    gradle, manifest = app / 'build.gradle.kts', app / 'src/main/AndroidManifest.xml'
    if (not gradle.is_file() or PACKAGE not in gradle.read_text() or
            not manifest.is_file() or (app / 'google-services.json').exists()):
        raise ValueError('isolated package without Firebase configuration required')
    if (harness / 'native-pin-source-manifest.json').exists():
        raise ValueError('refusing to overwrite prepared harness')
    expected = json.loads((ROOT / 'tools/app_stability/100380-baseline-manifest.json').read_text())
    pin = baseline / 'lib/deda_pin_auth.dart'
    if hashlib.sha256(pin.read_bytes()).hexdigest() != expected['files']['lib/deda_pin_auth.dart']:
        raise ValueError('original PinAuth source hash mismatch')
    locked = transport.versions(baseline / 'pubspec.lock')
    wanted = {k: v for k, v in locked.items() if k.startswith(transport.FAMILIES)}
    if not all(name in wanted for name in transport.FAMILIES):
        raise ValueError('required transport families missing')
    lines = ['name: deda_auth_qa', 'publish_to: none', 'version: 0.0.1+1',
             'environment:', "  sdk: '>=3.4.0 <4.0.0'", 'dependencies:',
             '  flutter:', '    sdk: flutter']
    lines += [f'  {name}: {wanted[name]}' for name in transport.FAMILIES]
    lines += ['dependency_overrides:'] + [f'  {k}: {v}' for k, v in sorted(wanted.items())]
    lines += ['flutter:', '  uses-material-design: true']
    (harness / 'pubspec.yaml').write_text('\n'.join(lines) + '\n')
    (harness / 'analysis_options.yaml').unlink(missing_ok=True)
    shutil.rmtree(harness / 'test', ignore_errors=True)
    sources = {'lib/deda_session_transition_gate.dart': ROOT / 'lib/deda_session_transition_gate.dart',
               'lib/deda_auth_session_runtime.dart': ROOT / 'lib/deda_auth_session_runtime.dart',
               'lib/deda_published_place_recovery.dart': ROOT / 'lib/deda_published_place_recovery.dart'}
    sources.update({'lib/deda_pin_auth.dart': pin, 'lib/main.dart': Path(__file__).with_name('main.dart')})
    hashes = {}
    for name, source in sources.items():
        shutil.copy2(source, harness / name)
        if name == 'lib/deda_pin_auth.dart':
            binding_spec = importlib.util.spec_from_file_location('auth_binding', ROOT / 'tools/app_stability/bind_auth_runtime.py')
            binding = importlib.util.module_from_spec(binding_spec)
            binding_spec.loader.exec_module(binding)
            (harness / name).write_text(binding.bind_pin(source.read_text()))
        hashes[name] = hashlib.sha256((harness / name).read_bytes()).hexdigest()
    text = manifest.read_text().replace('<application', '<application android:usesCleartextTraffic="true"', 1)
    if 'android.permission.INTERNET' not in text:
        text = text.replace('<application', '<uses-permission android:name="android.permission.INTERNET"/>\n    <application', 1)
    manifest.write_text(text)
    (harness / 'native-pin-source-manifest.json').write_text(json.dumps({
        'scope': 'runtime-bound PIN and place recovery, isolated native SDK, no privileged identity seeds; fixed approved-place fixtures only',
        'projectId': PROJECT, 'package': PACKAGE, 'files': hashes,
        'originalPinAuthSHA256': expected['files']['lib/deda_pin_auth.dart'],
        'pinnedTransportVersions': wanted}, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('harness', type=Path)
    parser.add_argument('baseline', type=Path)
    parser.add_argument('--verify', action='store_true')
    args = parser.parse_args()
    if args.verify:
        transport.verify(args.harness, args.baseline)
    else:
        prepare(args.harness, args.baseline)
