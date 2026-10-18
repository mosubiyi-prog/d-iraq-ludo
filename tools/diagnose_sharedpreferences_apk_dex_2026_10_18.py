#!/usr/bin/env python3
"""Read-only binary audit of SHA-pinned DEDA 100342 and 100353 APKs.

No rebuilding, resigning, installing, repackaging, network account access,
production publishing, or modification to either original APK.
"""
from __future__ import annotations
import hashlib
import json
import sys
import zipfile
from pathlib import Path
from androguard.core.dex import DEX

SUBSTRINGS = (
    "SharedPreferencesApiRegistrar",
    "SharedPreferencesPlugin",
    "Messages$SharedPreferencesApi",
    "Messages$SharedPreferencesAsyncApi",
)

def audit(filename: str) -> dict:
    blob = Path(filename).read_bytes()
    result = {
        "file": Path(filename).name,
        "sha256": hashlib.sha256(blob).hexdigest(),
        "dex": [],
        "target_classes": [],
        "referenced_methods": [],
    }
    seen_refs = set()
    with zipfile.ZipFile(filename) as archive:
        dexnames = sorted(n for n in archive.namelist() if n.startswith("classes") and n.endswith(".dex"))
        result["dex"] = dexnames
        for name in dexnames:
            d = DEX(archive.read(name))
            for cls in d.get_classes():
                descriptor = cls.get_name()
                if any(piece in descriptor for piece in SUBSTRINGS):
                    methods = [
                        {"name": str(m.get_name()), "descriptor": str(m.get_descriptor())}
                        for m in cls.get_methods()
                    ]
                    result["target_classes"].append({
                        "dex": name, "class": descriptor, "methods": methods,
                    })
            for method in d.get_methods():
                cls = str(method.get_class_name())
                nm = str(method.get_name())
                if "sharedpreferences" in cls.lower() and nm in ("getAll", "getAllWithPrefix", "getAllPrefs"):
                    sig = str(method.get_descriptor())
                    key = (cls, nm, sig)
                    if key not in seen_refs:
                        seen_refs.add(key)
                        result["referenced_methods"].append({
                            "class": cls, "name": nm, "descriptor": sig,
                        })
    return result

def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: audit.py verified_100342.apk verified_100353.apk")
    old, new = (audit(p) for p in sys.argv[1:])
    print(json.dumps({"old_100342_phone_verified": old, "new_100353_fail": new}, indent=2))
    for title, dat in (("100342 original", old), ("100353 rebuilt", new)):
        target = [
            c for c in dat["target_classes"]
            if "SharedPreferencesApiRegistrar" in c["class"]
        ]
        print("\n=== " + title + " ===")
        if not target:
            print("NOTE: unminified registrar class not found (possible obfuscation or different plugin)")
        for c in target:
            print("class:", c["class"], "dex:", c["dex"])
            for m in c["methods"]:
                print(" defined:", m["name"], m["descriptor"])
        print("sharedpreferences getAll references:", len(dat["referenced_methods"]))
        for m in dat["referenced_methods"]:
            print(" referenced:", m["class"], m["name"], m["descriptor"])

if __name__ == "__main__":
    main()
