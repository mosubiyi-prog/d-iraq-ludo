"""Bounded local status polling. Never print policy/source/PIN/UID/exception."""
import argparse
import json
import time
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument('expected', choices=['waiting', 'restart-ready', 'passed'])
parser.add_argument('--timeout', type=int, default=180)
args = parser.parse_args()
deadline = time.monotonic() + args.timeout
while time.monotonic() < deadline:
    try:
        with urllib.request.urlopen('http://127.0.0.1:8766/status', timeout=2) as response:
            value = json.load(response)
        if value['status'] == 'failed':
            raise SystemExit('native-pin-check-failed-see-sanitized-report')
        if value['status'] == args.expected:
            expected = {'waiting': 0, 'restart-ready': 16, 'passed': 20}[args.expected]
            if len(value['passed']) != expected or (args.expected == 'passed' and value['phase'] != 2):
                raise SystemExit('incomplete-native-pin-result')
            print(json.dumps({'status': value['status'], 'passed': len(value['passed'])}))
            break
    except (OSError, ValueError, KeyError):
        pass
    time.sleep(1)
else:
    raise SystemExit('native-pin-timeout-no-success-inferred')
