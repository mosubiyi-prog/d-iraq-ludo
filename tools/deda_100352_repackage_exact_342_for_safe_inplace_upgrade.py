#!/usr/bin/env python3
"""Repackage the byte-pinned, phone-verified DEDA 100342 APK with ONLY a higher Android versionCode.

This does not rebuild Flutter, mutate storage, update Firebase, or use an alternate signing key.
Output is UNSIGNED; the private Actions workflow aligns, signs and verifies it separately.
"""
from __future__ import annotations
from copy import copy
from hashlib import sha256
from pathlib import Path
import struct
import sys
import zipfile

ORIGINAL_APK_SHA256 = "4fd93e0d0596c5d6846b3d24620d7ec9bdb77f169c47abd7cf782770c320857d"
ORIGINAL_DEX_SHA256 = "9a0daefeb0cc218711309358ddf46bd45349164dcdc9dc30ea927153df19841e"
OLD_VERSION = 100342
SAFE_UPDATE_VERSION = 100352
MANIFEST_VERSION_OFFSET = 16676

def digest(data: bytes) -> str:
    return sha256(data).hexdigest()

def main(source: Path, output: Path) -> None:
    assert source.is_file() and source != output
    assert digest(source.read_bytes()) == ORIGINAL_APK_SHA256, "SAFE_STOP: exact original APK changed"
    output.parent.mkdir(parents=True, exist_ok=True)
    original_names = {}
    with zipfile.ZipFile(source, "r") as original:
        assert original.testzip() is None
        original_names = set(original.namelist())
        manifest = original.read("AndroidManifest.xml")
        dex = original.read("classes.dex")
        assert digest(dex) == ORIGINAL_DEX_SHA256
        assert "lib/arm64-v8a/libapp.so" in original_names
        assert len(manifest) == 31168, "SAFE_STOP: unexpected original binary AndroidManifest.xml"
        value_bytes = struct.pack("<I", OLD_VERSION)
        assert manifest.count(value_bytes) == 1, "SAFE_STOP: old version field ambiguous"
        assert manifest[MANIFEST_VERSION_OFFSET:MANIFEST_VERSION_OFFSET+4] == value_bytes
        # Binary XML typed value: size=8, type=TYPE_INT_DEC (0x10).
        assert manifest[MANIFEST_VERSION_OFFSET-4:MANIFEST_VERSION_OFFSET] == bytes.fromhex("08000010")
        revised = (
            manifest[:MANIFEST_VERSION_OFFSET]
            + struct.pack("<I", SAFE_UPDATE_VERSION)
            + manifest[MANIFEST_VERSION_OFFSET+4:]
        )
        assert len(revised) == len(manifest)
        assert revised[:MANIFEST_VERSION_OFFSET] == manifest[:MANIFEST_VERSION_OFFSET]
        assert revised[MANIFEST_VERSION_OFFSET+4:] == manifest[MANIFEST_VERSION_OFFSET+4:]
        with zipfile.ZipFile(output, "w", allowZip64=True) as unsigned:
            for entry in original.infolist():
                filename = entry.filename
                # APK Signing Scheme v2/v3 blocks aren't ZIP entries; rewriting ZIP strips old signature.
                if filename.startswith("META-INF/") and filename.upper().endswith((".RSA", ".DSA", ".EC", ".SF", ".MF")):
                    continue
                data = revised if filename == "AndroidManifest.xml" else original.read(filename)
                unsigned.writestr(copy(entry), data)
        with zipfile.ZipFile(output) as rebuilt:
            assert rebuilt.testzip() is None
            assert original_names == set(rebuilt.namelist()), "SAFE_STOP: APK entries changed"
            for filename in original.namelist():
                expected = revised if filename == "AndroidManifest.xml" else original.read(filename)
                assert rebuilt.read(filename) == expected, "SAFE_STOP: unexpected APK change in "+filename
    print("PASS: exact 100342 app/native resources/assets preserved; Android versionCode only 100342 -> 100352")
    print("PASS: ZIP verified; output awaits zipalign, SAME-certificate signing, and signed APK checks")

if __name__ == "__main__":
    assert len(sys.argv) == 3, "usage: repackage.py original.apk unsigned.apk"
    main(Path(sys.argv[1]), Path(sys.argv[2]))
