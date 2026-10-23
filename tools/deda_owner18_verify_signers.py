"""Compare public signing certificates after apksigner verify succeeds."""
from pathlib import Path
import re
import sys

def certificates(text):
    # Android Build Tools changed "Signer #1" to "V2 Signer:".
    found = set(re.findall(
        r'(?m)^(?:Signer #[0-9]+|V[0-9.]+ Signer):? certificate SHA-256 digest: ([0-9a-fA-F]{64})\s*$',
        text))
    result = {x.lower() for x in found}
    if len(result) != 1:
        raise ValueError('SIGNING_CERTIFICATE_MISSING_OR_AMBIGUOUS_STOP')
    return result

def compare(original, candidate):
    old, new = certificates(original), certificates(candidate)
    if old != new:
        raise ValueError('SIGNATURE_MISMATCH_STOP')
    return next(iter(old))

if __name__ == '__main__':
    digest = compare(Path(sys.argv[1]).read_text(), Path(sys.argv[2]).read_text())
    print('PASS exact same original signing certificate SHA256:', digest)
