"""Bounded localhost fixture polling; no credentials or external endpoints."""
import argparse
import json
import time
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument('expected', choices=['waiting', 'background-ready', 'backgrounded', 'restart-ready', 'passed'])
parser.add_argument('--timeout', type=int, default=180)
args = parser.parse_args()
deadline = time.monotonic() + args.timeout
while time.monotonic() < deadline:
    try:
        with urllib.request.urlopen('http://127.0.0.1:8765/status', timeout=2) as response:
            value = json.load(response)
        if value['status'] == 'failed':
            raise SystemExit(json.dumps(value))
        if value['status'] == args.expected:
            if args.expected == 'restart-ready' and len(value['passed']) != 18:
                raise SystemExit('incomplete first-phase result')
            if args.expected == 'passed' and (len(value['passed']) != 24 or value.get('phase') != 2):
                raise SystemExit('incomplete cold-restart result')
            print(json.dumps({'status': value['status'], 'passed': len(value['passed'])}))
            break
    except (OSError, ValueError, KeyError):
        pass
    time.sleep(1)
else:
    raise SystemExit('native result timed out; no success inferred')
