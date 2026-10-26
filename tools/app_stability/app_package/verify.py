"""Verify internal APK against original100379, without launching either APK."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import zipfile

REPO = Path(__file__).resolve().parents[3]
REFERENCE_SHA = '52e9345528978d0944b8fe8a28cc1715395bfec624bf2c38f9c2157a3990a1da'
CERTIFICATE = 'a53d855b82d1280f324037428421838139ecf2e30174f9fcd0bd1878698b5f4a'
PACKAGE = 'com.diraq.ludo.d_iraq_ludo'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def package_info(text):
    match = re.search(r"^package: name='([^']+)' versionCode='([0-9]+)' versionName='([^']*)'", text, re.M)
    sdk = re.search(r"^sdkVersion:'([0-9]+)'", text, re.M)
    target = re.search(r"^targetSdkVersion:'([0-9]+)'", text, re.M)
    if not match or not sdk or not target:
        raise ValueError('APK package/SDK metadata missing')
    return {'package': match[1], 'versionCode': int(match[2]), 'versionName': match[3],
            'minSdk': int(sdk[1]), 'targetSdk': int(target[1]),
            'permissions': sorted(set(re.findall(r"^uses-permission[^:]*: name='([^']+)'", text, re.M)))}


def forbidden_export(name):
    lower = name.lower()
    return lower.endswith(('.jks', '.keystore', '.p12', '.pfx', '.pem')) or any(
        value in lower for value in ('key.properties', 'service-account', 'service_account', 'private-key'))


def tools():
    root = Path(os.environ['ANDROID_HOME'])/'build-tools'
    candidates = [p for p in root.iterdir() if (p/'aapt').is_file() and (p/'apksigner').is_file()]
    if not candidates:
        raise ValueError('Android verification tools missing')
    return max(candidates, key=lambda p: tuple(int(x) for x in re.findall(r'[0-9]+', p.name)))


def output(command):
    return subprocess.check_output(command, text=True, stderr=subprocess.STDOUT)


def verify(project, reference):
    project, reference = Path(project), Path(reference)
    data = json.loads((project/'internal-build-inputs.json').read_text())
    if data.get('completeOwnerDelivery') is not False or data.get('financialRestoreEnabled') is not False:
        raise ValueError('Internal-only build marker lost')
    if sha(reference) != REFERENCE_SHA:
        raise ValueError('Original reference APK fingerprint mismatch')
    for path, digest in data['sourceHashes'].items():
        if sha(project/path) != digest:
            raise ValueError('Compiled source or pinned lock drifted: '+path)
    # Verify critical native source/settings; launcher generation may change
    # mipmap resources legitimately, but never these authority/platform inputs.
    for path, digest in data['platformHashes'].items():
        if path.endswith(('.kt', '.kts')) or path.endswith('src/main/AndroidManifest.xml'):
            if sha(project/path) != digest:
                raise ValueError('Critical Android build input drifted: '+path)
    apk = project/'build/app/outputs/flutter-apk/app-release.apk'
    tool = tools()
    old_signer = output([str(tool/'apksigner'), 'verify', '--verbose', '--print-certs', str(reference)])
    new_signer = output([str(tool/'apksigner'), 'verify', '--verbose', '--print-certs', str(apk)])
    spec = importlib.util.spec_from_file_location('original_signers', REPO/'tools/deda_owner18_verify_signers.py')
    signers = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(signers)
    if signers.compare(old_signer, new_signer) != CERTIFICATE:
        raise ValueError('Original public signing certificate mismatch')
    old = package_info(output([str(tool/'aapt'), 'dump', 'badging', str(reference)]))
    new = package_info(output([str(tool/'aapt'), 'dump', 'badging', str(apk)]))
    if (new['package'] != PACKAGE or old['package'] != PACKAGE or\n        new['versionCode'] != data['versionCode'] or\n        new['versionCode'] <= old['versionCode']):
        raise ValueError('Internal package/version mismatch')
    for key in ('minSdk', 'targetSdk', 'permissions', 'versionName'):
        if new[key] != old[key]:
            raise ValueError('Original Android metadata changed: '+key)
    with zipfile.ZipFile(reference) as before, zipfile.ZipFile(apk) as after:
        if after.testzip() is not None or any(forbidden_export(name) for name in after.namelist()):
            raise ValueError('APK corruption or forbidden signing/config export')
        if 'lib/arm64-v8a/libapp.so' not in after.namelist() or 'AndroidManifest.xml' not in after.namelist():
            raise ValueError('Incomplete Android release APK')
        portraits = [name for name in before.namelist() if
                     name.startswith('assets/flutter_assets/assets/deda_owner_avatars_20261023/') and name.endswith('.jpg')]
        if len(portraits) != 3:
            raise ValueError('Original approved portrait set missing')
        for name in portraits:
            if hashlib.sha256(before.read(name)).digest() != hashlib.sha256(after.read(name)).digest():
                raise ValueError('Approved original artwork changed')
    return {**data, 'apkSha256': sha(apk), 'apkBytes': apk.stat().st_size,
            'certificateSha256': CERTIFICATE, 'packageVerification': new,
            'referenceApkSha256': REFERENCE_SHA, 'originalPortraitsVerified': 3,
            'sourceCommit': os.environ.get('GITHUB_SHA'), 'appLaunched': False,
            'productionMutation': False, 'completeOwnerDelivery': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('project', type=Path)
    parser.add_argument('reference', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = verify(args.project, args.reference)
    args.output.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps({key: result[key] for key in ('variant', 'apkSha256', 'apkBytes',
                     'certificateSha256', 'completeOwnerDelivery', 'appLaunched')}))
