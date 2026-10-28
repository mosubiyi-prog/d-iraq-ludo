"""Stage40: inspect immutable original DEDA source archive, NO edits/deploy.

The public git lib/main.dart is NOT the source of original SocialProgressWallet.
The signed private APK build uses 100380-baseline.tar.gz restored through
tools/restore_deda_stability_baseline.py. Never claim writer is fenced until
that actual source has been analyzed and a signed private build tested.
"""
import hashlib
import json
import re
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ARCHIVE = ROOT / "tools/app_stability/100380-baseline.tar.gz"
MANIFEST = ROOT / "tools/app_stability/100380-baseline-manifest.json"
MARKERS = (
    "class DedaSocialProgressWallet", "deda_social_progress_v1_",
    "taskClaims", "xpNotifier",
)
def main():
    manifest = json.loads(MANIFEST.read_text())
    data = ARCHIVE.read_bytes()
    if hashlib.sha256(data).hexdigest() != manifest["archiveSHA256"]:
        raise AssertionError("IMMUTABLE_BASELINE_ARCHIVE_HASH_MISMATCH")
    found = []
    with tarfile.open(ARCHIVE, "r:gz") as archive:
        for entry in archive:
            if not entry.isfile() or not entry.name.endswith(".dart"):
                continue
            if entry.size > 7 * 1024 * 1024:
                raise AssertionError("Unexpected huge source")
            raw = archive.extractfile(entry).read().decode("utf-8")
            if not any(m in raw for m in MARKERS):
                continue
            if "lib/" not in entry.name:
                raise AssertionError("Unexpected archive source location")
            lines = raw.splitlines()
            for i, line in enumerate(lines):
                if any(m in line for m in MARKERS):
                    found.append((entry.name,i+1,line.strip()))
            if "class DedaSocialProgressWallet" in raw:
                print("STAGE40_WALLET_FILE:",entry.name)
                names = [
                    "class DedaSocialProgressWallet", "claimTask",
                    "taskClaims", "xpNotifier", "xp += ",
                    "'xp':", "'taskClaims':", "xp =", "_writeState",
                    "save(", "prefs.setString",
                ]
                for needle in names:
                    occurrences = [m.start() for m in re.finditer(re.escape(needle),raw)]
                    print("STAGE40_TOKEN",repr(needle),"count",len(occurrences))
                    for offset in occurrences[:8]:
                        left = raw.rfind("\n",0,offset)
                        lineno = raw.count("\n",0,offset)+1
                        snippet = raw[max(0,left-260):min(len(raw),offset+500)]
                        print("STAGE40_CONTEXT",needle,"line",lineno,repr(snippet))
    if not any("class DedaSocialProgressWallet" in item[2] for item in found):
        raise AssertionError("Original signed DEDA SocialProgressWallet NOT FOUND")
    print("STAGE40_AUDIT_SUCCESS — original writer located; NO modifications or rollout")
if __name__=="__main__":
    main()
