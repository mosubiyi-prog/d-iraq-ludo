import base64
import os
from pathlib import Path

raw = os.environ['DEDA_KEYSTORE_BASE64'].strip()
if raw.startswith('DEDA_KEYSTORE_BASE64='):
    raw = raw.split('=', 1)[1].strip()
raw = ''.join(raw.split())

output = Path('android/app/deda-release.jks')
output.write_bytes(base64.b64decode(raw, validate=True))
if output.stat().st_size == 0:
    raise SystemExit('Signing key is empty')

print('Permanent signing key restored.')
