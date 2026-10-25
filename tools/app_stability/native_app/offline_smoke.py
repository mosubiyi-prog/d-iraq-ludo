"""Launch only the internal signed app pair on a disposable OFFLINE emulator.

No real account/PIN, provider calls, production network, grant or purchase.
Only Android launch timing/logged-out smoke; not section speed or restoration.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import time

REPO = Path(__file__).resolve().parents[3]
PACKAGE = 'com.diraq.ludo.d_iraq_ludo'
CHAIN = 'DEDA_INTERNAL_OFFLINE'


def adb(*args, binary=False, check=True):
    result = subprocess.run(['adb', *args], capture_output=True,
                            text=not binary, timeout=90)
    if check and result.returncode != 0:
        raise RuntimeError('ADB operation failed: '+str(args[:2]))
    return result.stdout


def valid_firewall(output, chain, ipv6=False):
    lines = [line for line in output.splitlines() if line.startswith('-A '+chain+' ')]
    destinations = ('::1/128',) if ipv6 else ('127.0.0.0/8', '10.0.2.2/32')
    if len(lines) != len(destinations)+1:
        return False
    for line, destination in zip(lines, destinations):
        if line != '-A '+chain+' -d '+destination+' -j RETURN':
            return False
    return re.fullmatch(r'-A '+re.escape(chain)+r' -j REJECT(?: --reject-with [a-zA-Z0-9-]+)?', lines[-1]) is not None


def block_network():
    adb('root')
    adb('wait-for-device')
    if adb('shell', 'id', '-u').strip() != '0':
        raise RuntimeError('Rooted disposable emulator required; APK NOT launched')
    for tool, destinations in [('iptables', ('127.0.0.0/8', '10.0.2.2/32')),
                               ('ip6tables', ('::1/128',))]:
        adb('shell', tool, '-N', CHAIN)
        for destination in destinations:
            adb('shell', tool, '-A', CHAIN, '-d', destination, '-j', 'RETURN')
        adb('shell', tool, '-A', CHAIN, '-j', 'REJECT')
        adb('shell', tool, '-I', 'OUTPUT', '1', '-j', CHAIN)
        output = adb('shell', tool, '-S', 'OUTPUT')
        jumps = [line for line in output.splitlines() if line.startswith('-A OUTPUT ')]
        if not jumps or jumps[0].strip() != '-A OUTPUT -j '+CHAIN:
            raise RuntimeError('Offline guard is not first OUTPUT rule; APK NOT launched')
        if not valid_firewall(adb('shell', tool, '-S', CHAIN), CHAIN, tool == 'ip6tables'):
            raise RuntimeError('Offline guard mismatch; APK NOT launched')


def timings(text):
    result = {}
    for key in ('TotalTime', 'WaitTime'):
        match = re.search(r'^'+key+r': ([0-9]+)\s*$', text, re.M)
        if not match:
            raise ValueError('Android launch measurement missing: '+key)
        result[key+'Ms'] = int(match[1])
    return result


def current_client_matches(record, target):
    spec = importlib.util.spec_from_file_location('smoke_restore', REPO/'tools/restore_deda_stability_baseline.py')
    restore = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(restore)
    options = {'startup_metrics': True}
    if record['variant'] == 'candidate':
        options.update(auth_runtime=True, pilot=True, admin_firebase_adapter=True,
                       progress_backup_runtime=True, section_entry=True, lazy_sections=True)
    restore.restore(target, **options)
    for path, digest in record['sourceHashes'].items():
        if hashlib.sha256((target/path).read_bytes()).hexdigest() != digest:
            raise ValueError('Internal APK does not match current client source: '+path)


def run(control, candidate, out):
    out.mkdir(parents=True, exist_ok=False)
    report = {'format': 1, 'sourceCommit': os.environ.get('GITHUB_SHA'),
              'artifactSourceCommit': '66797aaedb549d28885e5b844293cb2335e99573',
              'completeOwnerDelivery': False, 'physicalPhoneTabletTested': False,
              'authenticatedSectionsTested': False, 'sectionSpeedupProven': False,
              'offlineGuardVerified': False, 'appLaunched': False, 'variants': {}}
    report_path = out/'report.json'
    try:
        records = []
        for variant, root in [('control', control), ('candidate', candidate)]:
            record = json.loads((root/'verification.json').read_text())
            apks = list(root.glob('*.apk'))
            if len(apks) != 1 or record['variant'] != variant or record.get('completeOwnerDelivery') is not False:
                raise ValueError('Unexpected internal APK artifact')
            if hashlib.sha256(apks[0].read_bytes()).hexdigest() != record['apkSha256']:
                raise ValueError('Internal APK transport fingerprint mismatch')
            current_client_matches(record, out.parent/('expected-client-'+variant))
            records.append((variant, apks[0], record))
        block_network()
        report['offlineGuardVerified'] = True
        for variant, apk, record in records:
            # Same package/certificate/version: candidate updates control IN
            # PLACE. Disposable emulator has no real user data or accounts.
            adb('install', '-r', str(apk))
            runs = []
            for attempt in range(3):
                adb('shell', 'am', 'force-stop', PACKAGE)
                adb('logcat', '-c')
                measure = timings(adb('shell', 'am', 'start', '-W', '-n', PACKAGE+'/.MainActivity'))
                report['appLaunched'] = True
                time.sleep(2)
                if not adb('shell', 'pidof', PACKAGE, check=False).strip():
                    raise RuntimeError('Internal app process exited')
                logs = adb('logcat', '-d')
                signatures = [name for name, pattern in {
                    'android-fatal': r'FATAL EXCEPTION',
                    'native-method-mismatch': r'NoSuchMethodError',
                    'flutter-unhandled': r'E/flutter.*Unhandled Exception',
                }.items() if re.search(pattern, logs)]
                if signatures:
                    report['fatalSignatures'] = signatures
                    raise RuntimeError('Internal app fatal smoke signature')
                runs.append(measure)
            (out/(variant+'-logged-out-offline.png')).write_bytes(adb('exec-out', 'screencap', '-p', binary=True))
            report['variants'][variant] = {'apkSha256': record['apkSha256'], 'runs': runs,
                'medianAndroidTotalTimeMs': statistics.median(x['TotalTimeMs'] for x in runs),
                'processAlive': True, 'fatalSignatureAbsent': True}
            report_path.write_text(json.dumps(report, indent=2)+'\n')
        report['passed'] = True
        report['productionNetworkBlocked'] = True
        report['scope'] = 'Logged-out OFFLINE Android launch only; NOT authenticated section timing, full restoration or final acceptance.'
    except Exception as error:
        report['passed'] = False
        # Controlled error category only; never export raw Android/SDK logs.
        report['failureClass'] = type(error).__name__
        raise
    finally:
        report_path.write_text(json.dumps(report, indent=2)+'\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('control', type=Path)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    run(args.control, args.candidate, args.output)
