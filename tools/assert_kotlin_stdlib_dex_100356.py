#!/usr/bin/env python3
"""Fail a DEDA private APK if SharedPreferences registrar has obfuscated Continuation.

Inspect APK Dalvik DEX method definitions, not just substrings or Flutter tests.
Uses only Python stdlib and never writes to the APK.
"""
import io
import struct
import sys
import zipfile
from pathlib import Path

NEEDED = "(Ljava/lang/String;Ljava/util/List;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;"
REGISTRAR = "Lio/flutter/plugins/sharedpreferences/SharedPreferencesApiRegistrar;"
CONTINUATION = "Lkotlin/coroutines/Continuation;"
COROUTINE_SINGLETONS = "Lkotlin/coroutines/intrinsics/CoroutineSingletons;"
KOTLIN_RESULT = "Lkotlin/Result;"

def u32(b, i):
    return struct.unpack_from("<I", b, i)[0]

def uleb(b, i):
    n = 0
    for j in range(5):
        v = b[i]
        i += 1
        n |= (v & 127) << (7 * j)
        if not v & 128:
            return n, i
    raise AssertionError("Invalid DEX uleb")

def dex_methods(blob):
    assert blob.startswith(b"dex\n"), "SAFE_STOP: invalid DEX header"
    count, offset = u32(blob, 0x38), u32(blob, 0x3c)
    strings = []
    for n in range(count):
        i = u32(blob, offset + 4 * n)
        _, i = uleb(blob, i)
        strings.append(blob[i:blob.index(b"\0", i)].decode("utf-8", errors="replace"))
    count, offset = u32(blob, 0x40), u32(blob, 0x44)
    types = [strings[u32(blob, offset + 4 * n)] for n in range(count)]
    count, offset = u32(blob, 0x48), u32(blob, 0x4c)
    protos = []
    for n in range(count):
        shorty, ret, pars = struct.unpack_from("<III", blob, offset + 12 * n)
        _ = shorty
        args = []
        if pars:
            args = [
                types[struct.unpack_from("<H", blob, pars + 4 + 2 * j)[0]]
                for j in range(u32(blob, pars))
            ]
        protos.append("(" + "".join(args) + ")" + types[ret])
    count, offset = u32(blob, 0x58), u32(blob, 0x5c)
    methods = []
    for n in range(count):
        cl, proto, name = struct.unpack_from("<HHI", blob, offset + 8 * n)
        methods.append((types[cl], strings[name], protos[proto]))
    count, offset = u32(blob, 0x60), u32(blob, 0x64)
    defined = []
    classes = set()
    for n in range(count):
        cl = types[u32(blob, offset + 32 * n)]
        classes.add(cl)
        if cl != REGISTRAR:
            continue
        i = u32(blob, offset + 32 * n + 24)
        assert i, "SAFE_STOP: registrar class missing method definitions"
        fs, i = uleb(blob, i)
        fi, i = uleb(blob, i)
        nd, i = uleb(blob, i)
        nv, i = uleb(blob, i)
        for j in range(fs + fi):
            _, i = uleb(blob, i)
            _, i = uleb(blob, i)
        for nmethods in (nd, nv):
            idx = 0
            for j in range(nmethods):
                delta, i = uleb(blob, i)
                idx += delta
                _, i = uleb(blob, i)  # access flags
                _, i = uleb(blob, i)  # code offset
                defined.append(methods[idx])
    return defined, classes

def main():
    assert len(sys.argv) == 2, "Usage: assert_dex.py signed_private_100356.apk"
    path = Path(sys.argv[1])
    assert path.is_file() and path.stat().st_size > 1000000, "SAFE_STOP: APK missing"
    all_methods = []
    classes = set()
    with zipfile.ZipFile(path) as apk:
        assert apk.testzip() is None, "SAFE_STOP: corrupt APK ZIP"
        names = [n for n in apk.namelist() if n.startswith("classes") and n.endswith(".dex")]
        assert names, "SAFE_STOP: no DEX"
        for name in names:
            methods, dex_classes = dex_methods(apk.read(name))
            all_methods.extend(methods)
            classes.update(dex_classes)
    expected = (REGISTRAR, "getAll", NEEDED)
    actual = [m for m in all_methods if m[0] == REGISTRAR and m[1] == "getAll"]
    print("SharedPreferencesApiRegistrar.getAll definitions:", actual)
    assert actual == [expected], "SAFE_STOP: original Continuation method signature not preserved"
    assert CONTINUATION in classes, "SAFE_STOP: kotlin.coroutines.Continuation still obfuscated or absent"
    assert COROUTINE_SINGLETONS in classes, "SAFE_STOP: runtime CoroutineSingletons was stripped or renamed by R8"
    assert KOTLIN_RESULT in classes, "SAFE_STOP: kotlin.Result runtime class missing from APK DEX"
    print("PASS: runtime method exact signature preserved in actual release APK DEX")
    print("PASS: Kotlin Continuation, CoroutineSingletons, AND Result present with correct names; Android runtime test still required")

if __name__ == "__main__":
    main()
