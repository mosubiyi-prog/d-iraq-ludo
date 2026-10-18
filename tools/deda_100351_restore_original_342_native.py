#!/usr/bin/env python3
"""Restore precisely the proven DEDA 100342 Android native layer in a private
100351 QA APK, preserving its newly compiled Dart code and version manifest.

Inputs: original-342.apk staged-351.apk output-unsigned.apk
This produces an UNSIGNED staging ZIP only. Release signing must follow.
No Firebase, account, Play or source app data is accessed.
"""
import copy
import hashlib
import sys
import zipfile
from pathlib import Path

ORIGINAL_APK_SHA256 = "4fd93e0d0596c5d6846b3d24620d7ec9bdb77f169c47abd7cf782770c320857d"
NATIVE_342_SHA256 = "9a0daefeb0cc218711309358ddf46bd45349164dcdc9dc30ea927153df19841e"
NATIVE_DRIFT_SHA256 = "2272abb2abfbb441eab05fec367a8df3f3151b9c2216f8ec2a8cee460731ffd4"
SERVICE_PREFIX = "META-INF/services/"
NATIVE_LIBS = (
    "lib/arm64-v8a/libflutter.so",
    "lib/armeabi-v7a/libflutter.so",
    "lib/x86_64/libflutter.so",
    "resources.arsc",
)
NATIVE_FILES = (
    "classes.dex",
    "assets/dexopt/baseline.prof",
    "assets/dexopt/baseline.profm",
)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def restore(original_path, staged_path, output_path):
    original_path, staged_path, output_path = map(Path, (original_path, staged_path, output_path))
    assert original_path != staged_path and staged_path != output_path
    assert sha256(original_path.read_bytes()) == ORIGINAL_APK_SHA256, (
        "SAFE_STOP: original 100342 APK is not the exact approved binary")
    with zipfile.ZipFile(original_path) as old, zipfile.ZipFile(staged_path) as new:
        assert old.testzip() is None and new.testzip() is None, "SAFE_STOP corrupt APK"
        old_names, new_names = set(old.namelist()), set(new.namelist())
        assert set(NATIVE_FILES).issubset(old_names & new_names)
        assert set(NATIVE_LIBS).issubset(old_names & new_names)
        assert {"AndroidManifest.xml", "classes.dex"}.issubset(old_names & new_names)
        assert sha256(old.read("classes.dex")) == NATIVE_342_SHA256
        # Android manifest MUST be identical byte-for-byte except versionCode.
        # This guarantees the new APK did not change permissions, components,
        # exported services, native plugin declarations, or application id.
        old_manifest = old.read("AndroidManifest.xml")
        new_manifest = new.read("AndroidManifest.xml")
        original_version = (100342).to_bytes(4, "little")
        assert old_manifest.count(original_version) == 1, (
            "SAFE_STOP original manifest version marker changed")
        allowed_versions = {100343, 100351}  # proof APK, then target release
        version_candidates = [
            v for v in allowed_versions
            if new_manifest == old_manifest.replace(
                original_version, v.to_bytes(4, "little"), 1)
        ]
        assert len(version_candidates) == 1, (
            "SAFE_STOP Android manifest differs beyond approved versionCode")
        before_dex = sha256(new.read("classes.dex"))
        assert before_dex in {NATIVE_342_SHA256, NATIVE_DRIFT_SHA256}, (
            "SAFE_STOP: unexpected new native code, inspect before patch: " + before_dex)
        for item in NATIVE_LIBS:
            assert sha256(old.read(item)) == sha256(new.read(item)), (
                "SAFE_STOP: native engine/resource drift: " + item)
        # The AOT-compiled Dart logic MUST remain the 100351 version.
        assert sha256(old.read("lib/arm64-v8a/libapp.so")) != sha256(
            new.read("lib/arm64-v8a/libapp.so")), "SAFE_STOP: new Dart code absent"
        orig_services = {n for n in old_names if n.startswith(SERVICE_PREFIX)}
        new_services = {n for n in new_names if n.startswith(SERVICE_PREFIX)}
        expected_orig = {"bq1", "ck1", "mg1", "wt1", "mx", "x8"}
        expected_drift = {"du1", "hk1", "iq1", "rg1", "mx", "x8"}
        assert {n.removeprefix(SERVICE_PREFIX) for n in orig_services} == expected_orig, (
            "SAFE_STOP: 100342 native service registry unexpectedly changed")
        assert {n.removeprefix(SERVICE_PREFIX) for n in new_services} in (
            expected_orig, expected_drift), (
            "SAFE_STOP: new service registry changed beyond reviewed 342/343 drift")
        # Do NOT copy original manifest: it contains versionCode 100342.
        # The build's manifest contains the intended versionCode 100351.
        # Every other new-Dart asset and all three new libapp.so files remain.
        with zipfile.ZipFile(output_path, "w", allowZip64=True) as out:
            for info in new.infolist():
                name = info.filename
                if name.startswith(SERVICE_PREFIX):
                    continue
                if name.startswith("META-INF/") and name.upper().endswith(
                    (".RSA", ".DSA", ".SF", "MANIFEST.MF")
                ):
                    continue
                data = old.read(name) if name in NATIVE_FILES else new.read(name)
                out.writestr(copy.copy(info), data)
            for name in sorted(orig_services):
                out.writestr(copy.copy(old.getinfo(name)), old.read(name))
        with zipfile.ZipFile(output_path) as result:
            assert result.testzip() is None, "SAFE_STOP: patched APK damaged"
            assert sha256(result.read("classes.dex")) == NATIVE_342_SHA256
            assert {n for n in result.namelist() if n.startswith(SERVICE_PREFIX)} == orig_services
            for name in orig_services:
                assert result.read(name) == old.read(name), "SAFE_STOP: service mismatch"
            for name in NATIVE_FILES:
                assert result.read(name) == old.read(name), "SAFE_STOP: native mismatch"
            for abi in ("arm64-v8a", "armeabi-v7a", "x86_64"):
                name = f"lib/{abi}/libapp.so"
                assert result.read(name) == new.read(name), "SAFE_STOP: Dart AOT replaced"
            assert result.read("AndroidManifest.xml") == new.read("AndroidManifest.xml"), (
                "SAFE_STOP: new version manifest replaced")
    print("PASS: original 100342 classes.dex, native services and baseline profile restored")
    print("PASS: staged 100351 Dart libapp.so, permissions, assets and manifest preserved")
    print("PASS: unsigned APK ready for zipalign and same-keystore release signing")


if __name__ == "__main__":
    assert len(sys.argv) == 4, "usage: restore.py 342.apk 351.apk patched-unsigned.apk"
    restore(*sys.argv[1:])
